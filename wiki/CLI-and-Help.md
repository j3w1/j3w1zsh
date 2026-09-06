# CLI and Help

Use `j3w1zsh help`, `j3w1zsh help edit`, `j3w1zsh help remote`, `j3w1zsh help codex`, `j3w1zsh help claude`, or `j3w1zsh help packages`. Global output options may appear before or after the command until `--`:

```text
--json
--plain
--color=auto|always|never
```

`--json` emits one envelope with `schema_version`, `command`, `status`, and `data`. Errors add a stable error code. JSON and plain output never include ANSI or a human banner.

`doctor` checks required binaries plus the locally resolvable Git upstream. On WSL it also reports `wsl-interop` from actual harmless Windows PowerShell execution without touching the clipboard. The upstream check makes no network request; use `update --dry-run` for current remote relation evidence.

## Command families

- Installation: `install`, `plan`, `status`, `doctor`, `platform`, `reset-phase`.
- Maintenance: `update`, `backup`, `restore`, `migrate`.
- Daily use: `edit`, `attach`, `remote`, `codex`, `claude`.
- Declarative layers: `packages`, `theme`, `workspace`, `wiki`.

`install` is the explicit refresh boundary for selected rolling software. Package-enabled runs refresh the selected platform, npm, Python-user, and WSL Codex sets even when their prior phase markers are complete; configuration-only phases keep normal fingerprint caching. `install --dry-run` and `plan` describe the full selected action without mutation. `update` updates j3w1zsh itself and does not imply a full operating-system or Termux upgrade.

`packages repair-provenance` is an exceptional recovery command, not routine pruning. It requires an exact manager and one or more exact package names, supports a mutation-free dry-run, and accepts only ledger ownership claims that the named manager currently reports absent. Actual repair preserves local evidence, retains unrelated records, and invalidates phase `20-packages`.

`edit [PATH]` runs `nvim -- PATH`. With no path it uses `J3W1ZSH_EDIT_ROOT`, defaulting to `$HOME/Documents`.

`attach` opens `tma`; `attach SESSION` attaches exactly that session; `--new`, `--list`, and confirmed `--kill` are bounded operations. Attaching creates another tmux client and does not disconnect an existing client.

`codex status` reports only public portable-baseline metadata on WSL. `codex disable openaiDeveloperDocs` opts out without changing the current user config; `codex reset openaiDeveloperDocs --yes` explicitly restores only the managed public endpoint. See [Configuration and User Overrides](Configuration-and-User-Overrides) for the ownership contract.

`claude status` is available on native Arch (best effort) and WSL. It reports only executable
availability and local npm package metadata; it does not launch Claude Code or inspect
authentication, configuration, session, MCP, plugin, trust, or project state. See
[Configuration and User Overrides](Configuration-and-User-Overrides) for the ownership boundary.

## Exit codes

| Code | Meaning |
|---:|---|
| 0 | Success, healthy status, or no required change |
| 1 | Validation, verification, runtime, or health failure |
| 2 | Invalid command, option, or argument |
| 20 | External or manual checkpoint required |
| 21 | Protected authored, staged, ahead, or divergent state requires owner review |
