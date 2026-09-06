#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/j3w1zsh-claude.XXXXXX")"
trap 'rm -rf -- "$test_root"' EXIT

home="$test_root/home"
project="$test_root/project"
fixture_bin="$test_root/bin"
npm_log="$test_root/npm.log"
claude_log="$test_root/claude.log"
system_path='/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'
mkdir -p "$home/.claude" "$project/.claude" "$fixture_bin"

cat >"$home/.claude/settings.json" <<'EOF'
{"owner":"settings"}
EOF
cat >"$home/.claude.json" <<'EOF'
{"owner":"session-and-trust"}
EOF
cat >"$project/.claude/settings.json" <<'EOF'
{"owner":"project-settings"}
EOF
cat >"$project/.mcp.json" <<'EOF'
{"mcpServers":{"owner":"project-server"}}
EOF

sensitive_paths=(
  "$home/.claude/settings.json"
  "$home/.claude.json"
  "$project/.claude/settings.json"
  "$project/.mcp.json"
)
sensitive_digests=()
for path in "${sensitive_paths[@]}"; do
  sensitive_digests+=("$(sha256sum "$path" | awk '{print $1}')")
done

cat >"$fixture_bin/npm" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$J3W1ZSH_TEST_NPM_LOG"
case "${1:-}" in
list) printf '%s\n' '{"dependencies":{"@anthropic-ai/claude-code":{"version":"2.3.4-beta.1+build.9"}}}' ;;
*) exit 2 ;;
esac
EOF
cat >"$fixture_bin/claude" <<'EOF'
#!/usr/bin/env bash
printf 'Claude executable must not be launched by j3w1zsh claude status.\n' >>"$J3W1ZSH_TEST_CLAUDE_LOG"
exit 99
EOF
cat >"$fixture_bin/j3w1zsh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$fixture_bin/npm" "$fixture_bin/claude" "$fixture_bin/j3w1zsh"
mkdir -p "$home/.local/bin"
cp -- "$fixture_bin/j3w1zsh" "$home/.local/bin/j3w1zsh"

run_cli() {
  local platform="$1"
  shift
  (
    cd "$project"
    env HOME="$home" XDG_STATE_HOME="$home/.local/state" XDG_CONFIG_HOME="$home/.config" XDG_CACHE_HOME="$home/.cache" \
      PATH="$fixture_bin:$system_path" J3W1ZSH_TEST_MODE=1 J3W1ZSH_TEST_PLATFORM="$platform" \
      J3W1ZSH_TEST_NPM_LOG="$npm_log" J3W1ZSH_TEST_CLAUDE_LOG="$claude_log" \
      "$repo_root/bin/j3w1zsh" "$@"
  )
}

assert_sensitive_bytes_unchanged() {
  local index path
  for index in "${!sensitive_paths[@]}"; do
    path="${sensitive_paths[$index]}"
    [[ $(sha256sum "$path" | awk '{print $1}') == "${sensitive_digests[$index]}" ]]
  done
}

for platform in arch wsl; do
  status="$(run_cli "$platform" claude status --json)"
  jq -e '
    .schema_version == 1 and .command == "claude-status" and .status == "ok" and
    .data == {
      platform: .data.platform,
      applicable: true,
      available: true,
      package:{name:"@anthropic-ai/claude-code",version:"2.3.4-beta.1+build.9"},
      configuration_managed:false
    }
  ' <<<"$status" >/dev/null
  [[ $status != *"$home" && $status != *"$project" ]]
done
[[ ! -e $claude_log ]]
[[ $(grep -Fc 'list --global --depth=0 --json -- @anthropic-ai/claude-code' "$npm_log") == 2 ]]
assert_sensitive_bytes_unchanged

mv -- "$fixture_bin/claude" "$fixture_bin/claude.disabled"
set +e
missing="$(run_cli arch claude status --json)"
missing_result=$?
set -e
[[ $missing_result == 1 ]]
jq -e '
  .schema_version == 1 and .command == "claude-status" and .status == "error" and
  .data.applicable == true and .data.available == false and .data.package.version == null and
  .data.configuration_managed == false
' <<<"$missing" >/dev/null
[[ ! -e $claude_log ]]
assert_sensitive_bytes_unchanged

termux="$(run_cli termux claude status --json)"
jq -e '
  .schema_version == 1 and .command == "claude-status" and .status == "ok" and
  .data.applicable == false and .data.available == false and .data.package.version == null and
  .data.configuration_managed == false
' <<<"$termux" >/dev/null
[[ ! -e $claude_log && $(grep -Fc 'list --global --depth=0 --json -- @anthropic-ai/claude-code' "$npm_log") == 2 ]]
assert_sensitive_bytes_unchanged

mv -- "$fixture_bin/claude.disabled" "$fixture_bin/claude"
help_output="$(run_cli arch help claude)"
grep -Fqx '  j3w1zsh claude status [--json]' <<<"$help_output"
grep -Fq 'without launching Claude Code' <<<"$help_output"

preset="$test_root/claude-preset.json"
jq '
  .id="claude-test" | .features=["claude"] |
  .platforms.arch={pacman:[],npm_global:[],pip_user:[]} |
  .platforms.wsl={pacman:[],npm_global:[],pip_user:[]} |
  .platforms.termux={pkg:[],npm_global:[],pip_user:[]}
' "$repo_root/presets/minimal.json" >"$preset"

required_packages() {
  local platform="$1" manager="$2" preset_path="${3:-$preset}"
  # shellcheck disable=SC2016 # The child Bash process expands its own environment.
  env HOME="$home" J3W1ZSH_REPO_ROOT="$repo_root" J3W1ZSH_TEST_MODE=1 J3W1ZSH_TEST_PLATFORM="$platform" TEST_PRESET="$preset_path" TEST_MANAGER="$manager" \
    bash -c '
      set -Eeuo pipefail
      source "$J3W1ZSH_REPO_ROOT/scripts/lib/core/init.sh"
      source "$J3W1ZSH_REPO_ROOT/scripts/lib/presets.sh"
      source "$J3W1ZSH_REPO_ROOT/scripts/lib/packages.sh"
      j3w1zsh_resolve_preset "$TEST_PRESET"
      j3w1zsh_required_packages_json "$TEST_MANAGER"
    '
}

for platform in arch wsl; do
  pacman_required="$(required_packages "$platform" pacman)"
  npm_required="$(required_packages "$platform" npm_global)"
  jq -e 'index("nodejs-lts-krypton") and index("npm")' <<<"$pacman_required" >/dev/null
  jq -e 'index("@anthropic-ai/claude-code")' <<<"$npm_required" >/dev/null
done
termux_npm_required="$(required_packages termux npm_global)"
[[ $termux_npm_required == '[]' ]]
default_npm_required="$(required_packages arch npm_global "$repo_root/presets/j3w1.json")"
jq -e '. == ["@anthropic-ai/claude-code"]' <<<"$default_npm_required" >/dev/null

override_dir="$home/.config/j3w1zsh"
mkdir -p "$override_dir"
jq -n '{schema_version:1,additions:{},exclusions:{npm_global:["@anthropic-ai/claude-code"]}}' >"$override_dir/packages.json"
set +e
# shellcheck disable=SC2016 # The child Bash process expands its own environment.
excluded_output="$(env HOME="$home" XDG_CONFIG_HOME="$home/.config" J3W1ZSH_REPO_ROOT="$repo_root" J3W1ZSH_TEST_MODE=1 J3W1ZSH_TEST_PLATFORM=arch TEST_PRESET="$preset" \
  bash -c '
    set -Eeuo pipefail
    source "$J3W1ZSH_REPO_ROOT/scripts/lib/core/init.sh"
    source "$J3W1ZSH_REPO_ROOT/scripts/lib/presets.sh"
    source "$J3W1ZSH_REPO_ROOT/scripts/lib/packages.sh"
    j3w1zsh_resolve_preset "$TEST_PRESET"
    j3w1zsh_packages_for_manager_json npm_global
  ' 2>&1)"
excluded_result=$?
set -e
[[ $excluded_result == 1 ]]
grep -Fq 'Package exclusions cannot remove core or selected-feature requirements' <<<"$excluded_output"

doctor_marker="$home/.local/state/j3w1zsh/phases/00-preflight.json"
mkdir -p "$(dirname -- "$doctor_marker")"
jq -n --arg preset "$preset" '{preset_source:$preset,no_packages:false}' >"$doctor_marker"
set +e
doctor="$(run_cli arch doctor --json)"
doctor_result=$?
set -e
[[ $doctor_result == 1 ]]
jq -e '(.data.checks[] | select(.name == "claude") | .ok) == true' <<<"$doctor" >/dev/null

# shellcheck disable=SC2016 # The child Bash process expands its own environment.
env HOME="$home" XDG_STATE_HOME="$home/.local/state" XDG_CONFIG_HOME="$home/.config" XDG_CACHE_HOME="$home/.cache" \
  PATH="$fixture_bin:$system_path" J3W1ZSH_REPO_ROOT="$repo_root" J3W1ZSH_TEST_MODE=1 J3W1ZSH_TEST_PLATFORM=arch J3W1ZSH_TEST_VERIFY_ADAPTERS=1 \
  TEST_PRESET="$preset" bash -c '
    set -Eeuo pipefail
    source "$J3W1ZSH_REPO_ROOT/scripts/lib/core/init.sh"
    source "$J3W1ZSH_REPO_ROOT/scripts/lib/presets.sh"
    source "$J3W1ZSH_REPO_ROOT/scripts/phases/90-verify.sh"
    j3w1zsh_resolve_preset "$TEST_PRESET"
    j3w1zsh_ensure_dirs
    phase_90_verify
  '

printf 'Claude Code feature, status privacy boundary, package closure, and doctor checks passed.\n'
