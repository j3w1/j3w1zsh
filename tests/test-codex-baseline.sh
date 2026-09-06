#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/j3w1zsh-codex-baseline.XXXXXX")"
trap 'rm -rf -- "$test_root"' EXIT

python3 -c 'import tomlkit' >/dev/null
jq -e '.schema_version == 1 and (.keys | length) == 4' "$repo_root/templates/codex-baseline-ownership.json" >/dev/null

baseline="$repo_root/templates/codex-config.toml"
ownership="$repo_root/templates/codex-baseline-ownership.json"
helper="$repo_root/scripts/codex-config.py"
managed_key='mcp_servers.openaiDeveloperDocs.url'
managed_url='https://developers.openai.com/mcp'

run_helper() {
  local operation="$1" home="$2" baseline_file="${3:-$baseline}" ownership_file="${4:-$ownership}"
  python3 "$helper" "$operation" \
    --config "$home/.codex/config.toml" \
    --state "$home/.local/state/j3w1zsh/codex/baseline.json" \
    --baseline "$baseline_file" \
    --ownership "$ownership_file"
}

first_home="$test_root/first-home"
mkdir -p "$first_home"
first="$(run_helper reconcile "$first_home")"
jq -e --arg key "$managed_key" '
  .pending == 1 and .actions == [{key:$key,action:"create"}]
' <<<"$first" >/dev/null
grep -Fqx 'approval_policy = "on-request"' "$first_home/.codex/config.toml"
grep -Fqx 'sandbox_mode = "workspace-write"' "$first_home/.codex/config.toml"
grep -Fqx "url = \"$managed_url\"" "$first_home/.codex/config.toml"
jq -e --arg key "$managed_key" --arg url "$managed_url" '
  .schema_version == 1 and .keys == {($key):{mode:"managed",last_applied:$url}}
' "$first_home/.local/state/j3w1zsh/codex/baseline.json" >/dev/null
first_config_digest="$(sha256sum "$first_home/.codex/config.toml")"
first_state_digest="$(sha256sum "$first_home/.local/state/j3w1zsh/codex/baseline.json")"
rerun="$(run_helper reconcile "$first_home")"
jq -e --arg key "$managed_key" '.actions == [{key:$key,action:"unchanged"}]' <<<"$rerun" >/dev/null
[[ $(sha256sum "$first_home/.codex/config.toml") == "$first_config_digest" ]]
[[ $(sha256sum "$first_home/.local/state/j3w1zsh/codex/baseline.json") == "$first_state_digest" ]]

custom_home="$test_root/custom-home"
mkdir -p "$custom_home/.codex"
cat >"$custom_home/.codex/config.toml" <<'EOF'
# User-owned Codex policy and local state.
approval_policy = "never"
sandbox_mode = "danger-full-access"
model = "gpt-5.6-sol"
model_reasoning_effort = "xhigh"

[projects."/private/project"]
trust_level = "trusted"

[features]
prevent_idle_sleep = true

[tui]
status_line = ["model", "reasoning", "git-branch", "permissions"]

[mcp_servers.personal]
url = "https://private.example.test/mcp"
EOF
custom="$(run_helper reconcile "$custom_home")"
jq -e --arg key "$managed_key" '.actions == [{key:$key,action:"add"}]' <<<"$custom" >/dev/null
grep -Fqx 'approval_policy = "never"' "$custom_home/.codex/config.toml"
grep -Fqx 'sandbox_mode = "danger-full-access"' "$custom_home/.codex/config.toml"
grep -Fqx 'model = "gpt-5.6-sol"' "$custom_home/.codex/config.toml"
grep -Fqx 'model_reasoning_effort = "xhigh"' "$custom_home/.codex/config.toml"
grep -Fqx 'url = "https://private.example.test/mcp"' "$custom_home/.codex/config.toml"
grep -Fqx '[projects."/private/project"]' "$custom_home/.codex/config.toml"
if rg -n 'private|gpt-5\.6-sol|xhigh|never|danger-full-access' "$custom_home/.local/state/j3w1zsh/codex/baseline.json"; then
  printf 'Codex baseline state copied a user-owned value.\n' >&2
  exit 1
fi

# An existing historical portable value is adopted without rewriting the user file.
adopt_home="$test_root/adopt-home"
mkdir -p "$adopt_home/.codex"
cp "$baseline" "$adopt_home/.codex/config.toml"
adopt_digest="$(sha256sum "$adopt_home/.codex/config.toml")"
adopt="$(run_helper reconcile "$adopt_home")"
jq -e --arg key "$managed_key" '.actions == [{key:$key,action:"adopt"}]' <<<"$adopt" >/dev/null
[[ $(sha256sum "$adopt_home/.codex/config.toml") == "$adopt_digest" ]]

# Advance only a local value equal to the previously managed public baseline.
next_url='https://developers.openai.com/mcp/v2'
next_baseline="$test_root/codex-next.toml"
next_ownership="$test_root/codex-next-ownership.json"
sed "s#https://developers.openai.com/mcp#${next_url}#" "$baseline" >"$next_baseline"
jq --arg old "$managed_url" --arg next "$next_url" '
  .keys |= map(if .path == "mcp_servers.openaiDeveloperDocs.url" then .historical_values=[$old,$next] else . end)
' "$ownership" >"$next_ownership"
advance="$(run_helper reconcile "$adopt_home" "$next_baseline" "$next_ownership")"
jq -e --arg key "$managed_key" '.actions == [{key:$key,action:"advance"}]' <<<"$advance" >/dev/null
grep -Fqx "url = \"$next_url\"" "$adopt_home/.codex/config.toml"

# An older historical value advances immediately on adoption rather than becoming an override.
historical_home="$test_root/historical-home"
mkdir -p "$historical_home/.codex"
cp "$baseline" "$historical_home/.codex/config.toml"
historical="$(run_helper reconcile "$historical_home" "$next_baseline" "$next_ownership")"
jq -e --arg key "$managed_key" '.actions == [{key:$key,action:"advance"}]' <<<"$historical" >/dev/null
grep -Fqx "url = \"$next_url\"" "$historical_home/.codex/config.toml"
jq -e --arg key "$managed_key" --arg url "$next_url" '.keys[$key] == {mode:"managed",last_applied:$url}' \
  "$historical_home/.local/state/j3w1zsh/codex/baseline.json" >/dev/null

# A retired portable key is removed only when its local value remains managed.
retired_baseline="$test_root/codex-retired.toml"
retired_ownership="$test_root/codex-retired-ownership.json"
sed '/^\[mcp_servers\.openaiDeveloperDocs\]/,$d' "$next_baseline" >"$retired_baseline"
jq '
  .keys |= map(if .path == "mcp_servers.openaiDeveloperDocs.url" then .retired=true else . end)
' "$next_ownership" >"$retired_ownership"
retired="$(run_helper reconcile "$adopt_home" "$retired_baseline" "$retired_ownership")"
jq -e --arg key "$managed_key" '.actions == [{key:$key,action:"remove"}]' <<<"$retired" >/dev/null
if grep -Fq 'openaiDeveloperDocs' "$adopt_home/.codex/config.toml"; then
  printf 'A retired managed Codex key was not removed.\n' >&2
  exit 1
fi
grep -Fqx '[sandbox_workspace_write]' "$adopt_home/.codex/config.toml"
jq -e --arg key "$managed_key" '.keys[$key].mode == "retired"' "$adopt_home/.local/state/j3w1zsh/codex/baseline.json" >/dev/null

# A different managed key value becomes an override and survives later changes.
override_home="$test_root/override-home"
mkdir -p "$override_home/.codex" "$override_home/.local/state/j3w1zsh/codex"
cat >"$override_home/.codex/config.toml" <<'EOF'
[mcp_servers.openaiDeveloperDocs]
url = "https://owner.example.test/docs"

[mcp_servers.personal]
url = "https://private.example.test/mcp"
EOF
jq -n --arg key "$managed_key" --arg prior "$managed_url" \
  '{schema_version:1,keys:{($key):{mode:"managed",last_applied:$prior}}}' \
  >"$override_home/.local/state/j3w1zsh/codex/baseline.json"
override="$(run_helper reconcile "$override_home" "$next_baseline" "$next_ownership")"
jq -e --arg key "$managed_key" '.actions == [{key:$key,action:"preserve-override"}]' <<<"$override" >/dev/null
grep -Fqx 'url = "https://owner.example.test/docs"' "$override_home/.codex/config.toml"
jq -e --arg key "$managed_key" '.keys[$key].mode == "overridden"' "$override_home/.local/state/j3w1zsh/codex/baseline.json" >/dev/null

run_codex() {
  local home="$1"
  shift
  env HOME="$home" XDG_CONFIG_HOME="$home/.config" XDG_STATE_HOME="$home/.local/state" XDG_CACHE_HOME="$home/.cache" \
    J3W1ZSH_TEST_MODE=1 J3W1ZSH_TEST_PLATFORM=wsl "$repo_root/bin/j3w1zsh" codex "$@"
}

disabled="$(run_codex "$override_home" disable openaiDeveloperDocs --json)"
jq -e --arg key "$managed_key" '.command == "codex-disable" and .status == "ok" and .data.key == $key and .data.action == "disabled"' <<<"$disabled" >/dev/null
disabled_plan="$(run_helper plan "$override_home")"
jq -e --arg key "$managed_key" '.actions == [{key:$key,action:"disabled"}]' <<<"$disabled_plan" >/dev/null
grep -Fqx 'url = "https://owner.example.test/docs"' "$override_home/.codex/config.toml"
reset="$(run_codex "$override_home" reset openaiDeveloperDocs --yes --json)"
jq -e --arg key "$managed_key" '.command == "codex-reset" and .status == "ok" and .data.key == $key and .data.action == "reset"' <<<"$reset" >/dev/null
grep -Fqx "url = \"$managed_url\"" "$override_home/.codex/config.toml"
grep -Fqx 'url = "https://private.example.test/mcp"' "$override_home/.codex/config.toml"
codex_status="$(run_codex "$override_home" status --json)"
jq -e --arg key "$managed_key" '
  .command == "codex-status" and .status == "ok" and .data.actions == [{key:$key,action:"unchanged"}]
' <<<"$codex_status" >/dev/null
if grep -Fq 'owner.example.test' <<<"$codex_status" || grep -Fq 'private.example.test' <<<"$codex_status"; then
  printf 'Codex status exposed a user-owned value.\n' >&2
  exit 1
fi

malformed_home="$test_root/malformed-home"
mkdir -p "$malformed_home/.codex"
printf '[mcp_servers.openaiDeveloperDocs\nurl = "broken"\n' >"$malformed_home/.codex/config.toml"
malformed_before="$(sha256sum "$malformed_home/.codex/config.toml")"
set +e
run_helper reconcile "$malformed_home" >"$test_root/malformed.json"
malformed_result=$?
set -e
[[ $malformed_result == 3 ]]
jq -e '.status == "blocked" and .reason == "malformed-config"' "$test_root/malformed.json" >/dev/null
[[ $(sha256sum "$malformed_home/.codex/config.toml") == "$malformed_before" ]]
[[ ! -e $malformed_home/.local/state/j3w1zsh/codex/baseline.json ]]

symlink_home="$test_root/symlink-home"
symlink_target="$test_root/symlink-target.toml"
mkdir -p "$symlink_home/.codex"
printf 'owner-authored = true\n' >"$symlink_target"
ln -s "$symlink_target" "$symlink_home/.codex/config.toml"
set +e
run_helper reconcile "$symlink_home" >"$test_root/symlink.json"
symlink_result=$?
set -e
[[ $symlink_result == 3 ]]
jq -e '.status == "blocked" and .reason == "unsafe-config"' "$test_root/symlink.json" >/dev/null
[[ ! -e $symlink_home/.local/state/j3w1zsh/codex/baseline.json ]]

# Dry-run reads only and exposes public key/action metadata in the action graph.
dry_home="$test_root/dry-home"
mkdir -p "$dry_home"
dry_preset="$test_root/codex-preset.json"
jq '
  .id="codex-baseline-test" | .features=["codex"] |
  .platforms.arch={pacman:[],npm_global:[],pip_user:[]} |
  .platforms.wsl={pacman:[],npm_global:[],pip_user:[]} |
  .platforms.termux={pkg:[],npm_global:[],pip_user:[]}
' "$repo_root/presets/minimal.json" >"$dry_preset"
dry_before="$(find "$dry_home" -mindepth 1 -printf '%P\n' | LC_ALL=C sort)"
dry_run="$(env HOME="$dry_home" XDG_CONFIG_HOME="$dry_home/.config" XDG_STATE_HOME="$dry_home/.local/state" XDG_CACHE_HOME="$dry_home/.cache" \
  J3W1ZSH_TEST_MODE=1 J3W1ZSH_TEST_PLATFORM=wsl "$repo_root/bin/j3w1zsh" install --preset "$dry_preset" --only 70-codex --dry-run --json)"
dry_after="$(find "$dry_home" -mindepth 1 -printf '%P\n' | LC_ALL=C sort)"
[[ $dry_before == "$dry_after" ]]
jq -e --arg key "$managed_key" '
  .status == "ok" and .data.dry_run == true and
  (.data.actions | map(select(.id == "codex-baseline" and .phase == "70-codex" and .kind == "file-reconciliation" and (.reason | contains("create portable key: " + $key)))) | length) == 1
' <<<"$dry_run" >/dev/null

printf 'Codex portable baseline ownership, migration, safety, status, and dry-run tests passed.\n'
