#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
test_root="$(mktemp -d)"
trap 'rm -rf -- "$test_root"' EXIT

fixture_home="$test_root/home"
fixture_bin="$test_root/bin"
adapter_log="$test_root/powershell.log"
mkdir -p "$fixture_home" "$fixture_bin"

cat >"$fixture_bin/powershell.exe" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'powershell.exe' >>"$TEST_HOST_ADAPTER_LOG"
printf ' %q' "$@" >>"$TEST_HOST_ADAPTER_LOG"
printf '\n' >>"$TEST_HOST_ADAPTER_LOG"
exit "${TEST_POWERSHELL_EXIT:-0}"
EOF
cat >"$fixture_bin/wslpath" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ ${1:-} == -w && $# == 2 ]]
printf '%s\n' "$2"
EOF
chmod +x "$fixture_bin/powershell.exe" "$fixture_bin/wslpath"

run_install() {
  env \
    HOME="$fixture_home" \
    XDG_STATE_HOME="$fixture_home/.local/state" \
    XDG_CONFIG_HOME="$fixture_home/.config" \
    XDG_CACHE_HOME="$fixture_home/.cache" \
    PATH="$fixture_bin:$PATH" \
    J3W1ZSH_REPO_ROOT="$repo_root" \
    J3W1ZSH_TEST_MODE=1 \
    J3W1ZSH_TEST_PLATFORM=wsl \
    J3W1ZSH_TEST_EFFECTIVE_UID=1000 \
    J3W1ZSH_TEST_HOST_ADAPTERS=1 \
    TEST_HOST_ADAPTER_LOG="$adapter_log" \
    TEST_POWERSHELL_EXIT="${TEST_POWERSHELL_EXIT:-0}" \
    "$repo_root/bin/j3w1zsh" install --preset j3w1 --from 50-theme --force --yes --plain </dev/null
}

phase_dir="$fixture_home/.local/state/j3w1zsh/phases"
manual_marker="$fixture_home/.local/state/j3w1zsh/manual/windows-terminal-restart.json"
failure_output="$test_root/failure.out"
set +e
TEST_POWERSHELL_EXIT=7 run_install >"$failure_output" 2>&1
failure_status=$?
set -e
[[ $failure_status == 7 ]]
grep -Fxq '[+] Phase 50-theme' "$failure_output"
if grep -Fq 'Phase 60-neovim' "$failure_output"; then
  printf 'Phase 60 executed after the Windows host adapter failed.\n' >&2
  exit 1
fi
[[ ! -e $phase_dir/50-theme.json && ! -e $phase_dir/60-neovim.json && ! -e $manual_marker ]]
[[ $(wc -l <"$adapter_log") == 1 ]]

# A successful host adapter creates the restart checkpoint but still cannot
# mark phase 50 or execute phase 60 until the owner confirms the terminal reload.
: >"$adapter_log"
checkpoint_output="$test_root/checkpoint.out"
set +e
TEST_POWERSHELL_EXIT=0 run_install >"$checkpoint_output" 2>&1
checkpoint_status=$?
set -e
[[ $checkpoint_status == 20 ]]
[[ -f $manual_marker && ! -e $phase_dir/50-theme.json && ! -e $phase_dir/60-neovim.json ]]
[[ $(wc -l <"$adapter_log") == 1 ]]

# The next run is a real TTY confirmation. It must not invoke the Windows host
# adapter again; it clears the checkpoint and marks phase 50 exactly once.
confirm_wrapper="$test_root/confirm.sh"
cat >"$confirm_wrapper" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
export HOME=$(printf '%q' "$fixture_home")
export XDG_STATE_HOME=$(printf '%q' "$fixture_home/.local/state")
export XDG_CONFIG_HOME=$(printf '%q' "$fixture_home/.config")
export XDG_CACHE_HOME=$(printf '%q' "$fixture_home/.cache")
export PATH=$(printf '%q' "$fixture_bin:$PATH")
export J3W1ZSH_REPO_ROOT=$(printf '%q' "$repo_root")
export J3W1ZSH_TEST_MODE=1
export J3W1ZSH_TEST_PLATFORM=wsl
export J3W1ZSH_TEST_EFFECTIVE_UID=1000
export J3W1ZSH_TEST_HOST_ADAPTERS=1
export TEST_HOST_ADAPTER_LOG=$(printf '%q' "$adapter_log")
export TEST_POWERSHELL_EXIT=0
exec $(printf '%q' "$repo_root/bin/j3w1zsh") install --preset j3w1 --only 50-theme --force --yes --plain
EOF
chmod +x "$confirm_wrapper"
printf 'y\n' | timeout 20 script -qefc "$confirm_wrapper" "$test_root/confirm.transcript" >/dev/null
[[ ! -e $manual_marker && -f $phase_dir/50-theme.json && ! -e $phase_dir/60-neovim.json ]]
[[ $(wc -l <"$adapter_log") == 1 ]]
jq -e --arg commit "$(git -C "$repo_root" rev-parse HEAD)" \
  '.phase == "50-theme" and .platform == "wsl" and .verified_commit == $commit' \
  "$phase_dir/50-theme.json" >/dev/null

printf 'WSL host-theme failure boundary, restart checkpoint, and phase-50 completion tests passed.\n'
