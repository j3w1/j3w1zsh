#!/usr/bin/env python3
"""Bounded, ownership-aware reconciliation for j3w1zsh's Codex baseline.

This helper deliberately knows only the public keys declared in the tracked
ownership manifest.  It uses tomlkit so edits preserve comments and unrelated
TOML syntax.  It never emits local Codex values.
"""

from __future__ import annotations

import argparse
import json
import os
import stat
import sys
import tempfile
from pathlib import Path
from typing import Any

try:
    import tomlkit
except ImportError:  # Report only the public prerequisite, never config bytes.
    print(json.dumps({"status": "blocked", "reason": "tomlkit-unavailable"}))
    sys.exit(3)


SCHEMA_VERSION = 1
MANAGED_PATH = "mcp_servers.openaiDeveloperDocs.url"
MANAGED_ID = "openaiDeveloperDocs"


class ReconcileError(Exception):
    """A safe-to-report reconciliation failure."""

    def __init__(self, reason: str):
        super().__init__(reason)
        self.reason = reason


def reject_unsafe_file(path: Path, label: str) -> None:
    """Allow a missing path or one regular file; never follow a symlink."""
    try:
        file_mode = os.lstat(path).st_mode
    except FileNotFoundError:
        return
    if stat.S_ISLNK(file_mode) or not stat.S_ISREG(file_mode):
        raise ReconcileError(f"unsafe-{label}")


def read_regular(path: Path, label: str) -> str | None:
    reject_unsafe_file(path, label)
    if not path.exists():
        return None
    try:
        return path.read_text(encoding="utf-8")
    except (OSError, UnicodeError) as error:
        raise ReconcileError(f"unreadable-{label}") from error


def load_json(path: Path, label: str) -> dict[str, Any] | None:
    raw = read_regular(path, label)
    if raw is None:
        return None
    try:
        value = json.loads(raw)
    except json.JSONDecodeError as error:
        raise ReconcileError(f"malformed-{label}") from error
    if not isinstance(value, dict):
        raise ReconcileError(f"malformed-{label}")
    return value


def load_manifest(path: Path) -> dict[str, Any]:
    manifest = load_json(path, "ownership-manifest")
    if manifest is None:
        raise ReconcileError("missing-ownership-manifest")
    keys = manifest.get("keys")
    if (
        manifest.get("schema_version") != SCHEMA_VERSION
        or not isinstance(keys, list)
        or len(keys) != 4
    ):
        raise ReconcileError("invalid-ownership-manifest")
    entries = {entry.get("path"): entry for entry in keys if isinstance(entry, dict)}
    expected = {
        MANAGED_PATH: "managed-portable",
        "approval_policy": "initial-default",
        "sandbox_mode": "initial-default",
        "sandbox_workspace_write.network_access": "initial-default",
    }
    if set(entries) != set(expected) or any(
        entries[path].get("ownership") != ownership for path, ownership in expected.items()
    ):
        raise ReconcileError("invalid-ownership-manifest")
    historic_values = entries[MANAGED_PATH].get("historical_values")
    if (
        not isinstance(historic_values, list)
        or not historic_values
        or not all(isinstance(item, str) and item for item in historic_values)
    ):
        raise ReconcileError("invalid-ownership-manifest")
    if any(
        "historical_values" in entries[path] or "retired" in entries[path]
        for path in expected
        if path != MANAGED_PATH
    ):
        raise ReconcileError("invalid-ownership-manifest")
    retired = entries[MANAGED_PATH].get("retired", False)
    if not isinstance(retired, bool):
        raise ReconcileError("invalid-ownership-manifest")
    return manifest


def parse_toml(raw: str, label: str) -> Any:
    try:
        return tomlkit.parse(raw)
    except Exception as error:  # tomlkit exposes parser-specific exception types.
        raise ReconcileError(f"malformed-{label}") from error


def table_value(document: Any) -> Any | None:
    try:
        servers = document["mcp_servers"]
    except KeyError:
        return None
    try:
        return servers[MANAGED_ID]
    except (KeyError, TypeError):
        return None


def managed_value(document: Any) -> str | None:
    server = table_value(document)
    if server is None:
        return None
    try:
        value = server["url"]
    except (KeyError, TypeError):
        return None
    if hasattr(value, "unwrap"):
        value = value.unwrap()
    if not isinstance(value, str):
        raise ReconcileError("invalid-managed-value")
    return value


def set_managed_value(document: Any, value: str) -> None:
    try:
        servers = document["mcp_servers"]
    except KeyError:
        servers = tomlkit.table()
        document.add("mcp_servers", servers)
    if not hasattr(servers, "__getitem__") or not hasattr(servers, "__setitem__"):
        raise ReconcileError("invalid-managed-table")
    try:
        server = servers[MANAGED_ID]
    except KeyError:
        server = tomlkit.table()
        servers.add(MANAGED_ID, server)
    if not hasattr(server, "__setitem__"):
        raise ReconcileError("invalid-managed-table")
    server["url"] = value


def remove_managed_value(document: Any) -> None:
    try:
        servers = document["mcp_servers"]
        server = servers[MANAGED_ID]
    except (KeyError, TypeError):
        return
    if not hasattr(server, "pop"):
        raise ReconcileError("invalid-managed-table")
    server.pop("url", None)
    if len(server) == 0:
        servers.pop(MANAGED_ID, None)


def state_entry(state: dict[str, Any] | None) -> dict[str, Any] | None:
    if state is None:
        return None
    keys = state.get("keys")
    if state.get("schema_version") != SCHEMA_VERSION or not isinstance(keys, dict):
        raise ReconcileError("invalid-baseline-state")
    if set(keys) != {MANAGED_PATH}:
        raise ReconcileError("invalid-baseline-state")
    entry = keys[MANAGED_PATH]
    if not isinstance(entry, dict) or set(entry) != {"mode", "last_applied"}:
        raise ReconcileError("invalid-baseline-state")
    if entry["mode"] not in {"managed", "overridden", "disabled", "retired"} or not isinstance(
        entry["last_applied"], str
    ):
        raise ReconcileError("invalid-baseline-state")
    return entry


def new_state(mode: str, last_applied: str) -> dict[str, Any]:
    return {
        "schema_version": SCHEMA_VERSION,
        "keys": {MANAGED_PATH: {"mode": mode, "last_applied": last_applied}},
    }


def baseline_document(path: Path) -> tuple[Any, str]:
    raw = read_regular(path, "baseline")
    if raw is None:
        raise ReconcileError("missing-baseline")
    document = parse_toml(raw, "baseline")
    value = managed_value(document)
    if value is None:
        raise ReconcileError("invalid-baseline")
    return document, value


def classify(config: Path, state_path: Path, baseline: Path, ownership: Path) -> dict[str, Any]:
    manifest = load_manifest(ownership)
    entries = {item["path"]: item for item in manifest["keys"]}
    retired = entries[MANAGED_PATH].get("retired", False)
    baseline_doc, baseline_value = (None, None) if retired else baseline_document(baseline)
    config_raw = read_regular(config, "config")
    state = load_json(state_path, "baseline-state")
    entry = state_entry(state)
    result: dict[str, Any] = {
        "schema_version": SCHEMA_VERSION,
        "config_exists": config_raw is not None,
        "key": MANAGED_PATH,
        "baseline": baseline_value,
        "config_document": baseline_doc if config_raw is None else parse_toml(config_raw, "config"),
        "state": state,
    }
    if entry is not None and entry["mode"] == "disabled":
        result["action"] = "disabled"
        return result
    if retired:
        local_value = None if config_raw is None else managed_value(result["config_document"])
        if local_value is None:
            result["action"] = "unchanged"
        elif entry is not None and entry["mode"] == "managed" and local_value == entry["last_applied"]:
            result["action"] = "remove"
        elif entry is None and local_value in entries[MANAGED_PATH]["historical_values"]:
            result["action"] = "remove"
        else:
            result["action"] = "preserve-override"
        return result
    if config_raw is None:
        result["action"] = "create"
        return result
    local_value = managed_value(result["config_document"])
    if entry is None:
        if local_value is None:
            result["action"] = "add"
        else:
            historical_values = entries[MANAGED_PATH]["historical_values"]
            if local_value in historical_values:
                result["action"] = "adopt" if local_value == baseline_value else "advance"
            else:
                result["action"] = "preserve-override"
        return result
    if entry["mode"] == "overridden":
        result["action"] = "preserve-override"
        return result
    if local_value == entry["last_applied"]:
        result["action"] = "unchanged" if local_value == baseline_value else "advance"
    else:
        result["action"] = "preserve-override"
    return result


def compact_result(result: dict[str, Any]) -> dict[str, Any]:
    action = result["action"]
    return {
        "schema_version": SCHEMA_VERSION,
        "config_exists": result["config_exists"],
        "managed": 1,
        "current": int(action in {"unchanged", "adopt"}),
        "overridden": int(action == "preserve-override"),
        "disabled": int(action == "disabled"),
        "pending": int(action in {"create", "add", "advance", "remove"}),
        "actions": [{"key": MANAGED_PATH, "action": action}],
    }


def atomic_write(path: Path, contents: str) -> None:
    parent = path.parent
    if not parent.is_dir() or parent.is_symlink():
        raise ReconcileError("unsafe-output-parent")
    try:
        descriptor, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=parent, text=True)
        with os.fdopen(descriptor, "w", encoding="utf-8", newline="") as output:
            output.write(contents)
            output.flush()
            os.fsync(output.fileno())
        os.chmod(temporary, 0o600)
        os.replace(temporary, path)
    except OSError as error:
        try:
            os.unlink(temporary)
        except (OSError, UnboundLocalError):
            pass
        raise ReconcileError("atomic-write-failed") from error


def reconcile(arguments: argparse.Namespace) -> dict[str, Any]:
    result = classify(arguments.config, arguments.state, arguments.baseline, arguments.ownership)
    action = result["action"]
    if action == "disabled":
        return compact_result(result)
    document = result["config_document"]
    baseline_value = result["baseline"]
    if action in {"create", "add", "advance"}:
        set_managed_value(document, baseline_value)
        output_state = new_state("managed", baseline_value)
    elif action == "remove":
        prior = state_entry(result["state"])
        last_applied = managed_value(result["config_document"]) if prior is None else prior["last_applied"]
        remove_managed_value(document)
        output_state = new_state("retired", last_applied)
    elif action == "adopt":
        output_state = new_state("managed", baseline_value)
    elif action == "preserve-override":
        prior = state_entry(result["state"])
        last_applied = baseline_value if prior is None else prior["last_applied"]
        output_state = new_state("overridden", last_applied)
    elif action == "unchanged":
        output_state = result["state"]
    else:
        output_state = new_state("managed", baseline_value)
    if action in {"create", "add", "advance", "remove"}:
        arguments.config.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        atomic_write(arguments.config, tomlkit.dumps(document))
    if output_state is not None:
        arguments.state.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        atomic_write(arguments.state, json.dumps(output_state, sort_keys=True) + "\n")
    return compact_result(result)


def disable(arguments: argparse.Namespace) -> dict[str, Any]:
    _, baseline_value = baseline_document(arguments.baseline)
    load_manifest(arguments.ownership)
    state = load_json(arguments.state, "baseline-state")
    entry = state_entry(state)
    last_applied = baseline_value if entry is None else entry["last_applied"]
    arguments.state.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    atomic_write(arguments.state, json.dumps(new_state("disabled", last_applied), sort_keys=True) + "\n")
    return {"schema_version": SCHEMA_VERSION, "key": MANAGED_PATH, "action": "disabled"}


def reset(arguments: argparse.Namespace) -> dict[str, Any]:
    result = classify(arguments.config, arguments.state, arguments.baseline, arguments.ownership)
    document = result["config_document"]
    set_managed_value(document, result["baseline"])
    arguments.config.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    atomic_write(arguments.config, tomlkit.dumps(document))
    arguments.state.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    atomic_write(arguments.state, json.dumps(new_state("managed", result["baseline"]), sort_keys=True) + "\n")
    return {"schema_version": SCHEMA_VERSION, "key": MANAGED_PATH, "action": "reset"}


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("operation", choices=("plan", "reconcile", "disable", "reset"))
    parser.add_argument("--config", required=True, type=Path)
    parser.add_argument("--state", required=True, type=Path)
    parser.add_argument("--baseline", required=True, type=Path)
    parser.add_argument("--ownership", required=True, type=Path)
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    try:
        if arguments.operation == "plan":
            output = compact_result(classify(arguments.config, arguments.state, arguments.baseline, arguments.ownership))
        elif arguments.operation == "reconcile":
            output = reconcile(arguments)
        elif arguments.operation == "disable":
            output = disable(arguments)
        else:
            output = reset(arguments)
    except ReconcileError as error:
        print(json.dumps({"status": "blocked", "reason": error.reason}))
        return 3
    print(json.dumps(output, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
