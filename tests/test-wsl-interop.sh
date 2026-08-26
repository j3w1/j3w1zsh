#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
test_root="$(mktemp -d)"
trap 'rm -rf -- "$test_root"' EXIT

fixture_home="$test_root/wsl-home"
termux_home="$test_root/termux-home"
fixture_bin="$test_root/bin"
interop_log="$test_root/interop.log"
clipboard_log="$test_root/clipboard.log"
package_log="$test_root/package.log"
preset="$test_root/interop-preset.json"
real_git="$(command -v git)"
mkdir -p "$fixture_home/.local/bin" "$fixture_home/.local/state/j3w1zsh/phases" \
  "$termux_home/.local/bin" "$termux_home/.local/state/j3w1zsh/phases" "$fixture_bin"

jq '
  .id="interop-test" | .features=[] |
  .platforms.arch={pacman:[],npm_global:[],pip_user:[]} |
  .platforms.wsl={pacman:["must-not-refresh"],npm_global:[],pip_user:[]} |
  .platforms.termux={pkg:[],npm_global:[],pip_user:[]}
' "$repo_root/presets/minimal.json" >"$preset"

cat >"$fixture_bin/powershell.exe" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '<CALL>\n' >>"$TEST_INTEROP_LOG"
for argument in "$@"; do
  printf '<%s>\n' "$argument" >>"$TEST_INTEROP_LOG"
  [[ $argument != *Clipboard* ]] || printf 'powershell clipboard mutation\n' >>"$TEST_CLIPBOARD_LOG"
done
exit "${TEST_POWERSHELL_EXIT:-0}"
EOF
cat >"$fixture_bin/clip.exe" <<'EOF'
#!/usr/bin/env bash
printf 'clip.exe clipboard mutation\n' >>"$TEST_CLIPBOARD_LOG"
EOF
cat >"$fixture_bin/pacman" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$TEST_PACKAGE_LOG"
exit 99
EOF
cat >"$fixture_bin/git" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
if [[ ${1:-} == -C && ${3:-} == rev-parse && ${4:-} == --is-inside-work-tree ]]; then
  exit 0
fi
if [[ ${1:-} == -C && ${3:-} == rev-parse && ${4:-} == --verify && ${5:-} == '@{upstream}^{commit}' ]]; then
  exit 0
fi
exec "$TEST_REAL_GIT" "$@"
EOF
cat >"$fixture_home/.local/bin/j3w1zsh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cp "$fixture_home/.local/bin/j3w1zsh" "$termux_home/.local/bin/j3w1zsh"
chmod +x "$fixture_bin/powershell.exe" "$fixture_bin/clip.exe" "$fixture_bin/pacman" "$fixture_bin/git" \
  "$fixture_home/.local/bin/j3w1zsh" "$termux_home/.local/bin/j3w1zsh"

for home in "$fixture_home" "$termux_home"; do
  jq -n --arg preset "$preset" \
    '{preset_source:$preset,theme_source:"j3w1zsh",no_packages:false,packages_only:false}' \
    >"$home/.local/state/j3w1zsh/phases/00-preflight.json"
done

run_cli() {
  local platform="$1" home="$2" powershell_exit="$3"
  shift 3
  env \
    HOME="$home" \
    XDG_STATE_HOME="$home/.local/state" \
    XDG_CONFIG_HOME="$home/.config" \
    XDG_CACHE_HOME="$home/.cache" \
    PATH="$fixture_bin:$PATH" \
    J3W1ZSH_REPO_ROOT="$repo_root" \
    J3W1ZSH_TEST_MODE=1 \
    J3W1ZSH_TEST_PLATFORM="$platform" \
    J3W1ZSH_TEST_EFFECTIVE_UID=1000 \
    J3W1ZSH_TEST_VERIFY_ADAPTERS=1 \
    TEST_INTEROP_LOG="$interop_log" \
    TEST_CLIPBOARD_LOG="$clipboard_log" \
    TEST_PACKAGE_LOG="$package_log" \
    TEST_POWERSHELL_EXIT="$powershell_exit" \
    TEST_REAL_GIT="$real_git" \
    "$repo_root/bin/j3w1zsh" "$@"
}

# An executable powershell.exe path is insufficient when Windows PE execution fails.
: >"$interop_log"
set +e
broken_doctor="$(run_cli wsl "$fixture_home" 126 doctor --json)"
broken_doctor_status=$?
set -e
[[ $broken_doctor_status == 1 ]]
jq -e '.status == "error" and any(.data.checks[]; .name == "wsl-interop" and .ok == false)' \
  <<<"$broken_doctor" >/dev/null
grep -Fxq '<-NoLogo>' "$interop_log"
grep -Fxq '<-NoProfile>' "$interop_log"
grep -Fxq '<-NonInteractive>' "$interop_log"
grep -Fxq '<-Command>' "$interop_log"
grep -Fxq '<exit 0>' "$interop_log"
[[ ! -e $clipboard_log ]]

# Healthy Windows PE execution makes the explicit doctor check healthy without touching clipboard state.
healthy_doctor="$(run_cli wsl "$fixture_home" 0 doctor --json)"
jq -e '.status == "ok" and any(.data.checks[]; .name == "wsl-interop" and .ok == true)' \
  <<<"$healthy_doctor" >/dev/null
[[ ! -e $clipboard_log ]]

# Phase 90 must checkpoint instead of recording false success when interop is broken.
phase_marker="$fixture_home/.local/state/j3w1zsh/phases/90-verify.json"
manual_marker="$fixture_home/.local/state/j3w1zsh/manual/wsl-interop-restart.json"
phase_failure_output="$test_root/phase-failure.out"
set +e
run_cli wsl "$fixture_home" 126 install --preset "$preset" --only 90-verify --yes --plain \
  >"$phase_failure_output" 2>&1
phase_failure_status=$?
set -e
[[ $phase_failure_status == 20 ]]
[[ -f $manual_marker && ! -e $phase_marker ]]
jq -e '
  .checkpoint == "wsl-interop-restart" and
  (.message | contains("wsl --shutdown")) and
  (.message | contains("every running WSL distribution")) and
  (.message | contains("j3w1zsh install --only 90-verify"))
' "$manual_marker" >/dev/null
grep -Fq 'From Windows PowerShell:' "$phase_failure_output"
grep -Fq 'wsl --shutdown' "$phase_failure_output"
grep -Fq 'WARNING: this stops every running WSL distribution.' "$phase_failure_output"
grep -Fq 'j3w1zsh install --only 90-verify' "$phase_failure_output"
[[ ! -e $clipboard_log ]]

# The bounded continuation re-probes PE execution, clears only its checkpoint, and completes phase 90.
calls_before="$(grep -c '^<CALL>$' "$interop_log")"
run_cli wsl "$fixture_home" 0 install --preset "$preset" --only 90-verify --yes --plain \
  >"$test_root/phase-continuation.out"
[[ ! -e $manual_marker && -f $phase_marker ]]
[[ $(grep -c '^<CALL>$' "$interop_log") == $((calls_before + 1)) ]]
[[ ! -e $package_log ]]
jq -e --arg commit "$(git -C "$repo_root" rev-parse HEAD)" \
  '.phase == "90-verify" and .platform == "wsl" and .verified_commit == $commit' \
  "$phase_marker" >/dev/null
[[ ! -e $clipboard_log ]]

# Termux does not expose or execute the WSL-only health probe.
termux_calls_before="$(grep -c '^<CALL>$' "$interop_log")"
termux_doctor="$(run_cli termux "$termux_home" 99 doctor --json)"
jq -e '.status == "ok" and all(.data.checks[]; .name != "wsl-interop")' <<<"$termux_doctor" >/dev/null
run_cli termux "$termux_home" 99 install --preset "$preset" --only 90-verify --yes --plain \
  >"$test_root/termux-phase.out"
[[ $(grep -c '^<CALL>$' "$interop_log") == "$termux_calls_before" ]]
[[ -f $termux_home/.local/state/j3w1zsh/phases/90-verify.json ]]
[[ ! -e $clipboard_log ]]

printf 'WSL PE execution health, doctor, phase-90 checkpoint continuation, clipboard safety, and Termux isolation tests passed.\n'
