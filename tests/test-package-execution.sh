#!/usr/bin/env bash
# shellcheck disable=SC2016
set -Eeuo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
test_root="$(mktemp -d)"
trap 'rm -rf -- "$test_root"' EXIT

fake_bin="$test_root/bin"
package_db="$test_root/packages.db"
package_log="$test_root/packages.log"
system_root="$test_root/system-root"
mkdir -p "$fake_bin" "$system_root/usr/bin" "$system_root/usr/lib/node_modules/corepack/dist"

cat >"$fake_bin/sudo" <<'EOF'
#!/usr/bin/env bash
printf 'sudo %s\n' "$*" >>"$TEST_PACKAGE_LOG"
exec "$@"
EOF

cat >"$fake_bin/pacman" <<'EOF'
#!/usr/bin/env bash
set -u
printf 'pacman %s\n' "$*" >>"$TEST_PACKAGE_LOG"
case "${1:-}" in
-Q)
  package="${*: -1}"
  grep -Fxq "pacman:$package" "$TEST_PACKAGE_DB"
  ;;
-Qqo)
  path="${*: -1}"
  case "$path" in
  "$TEST_SYSTEM_ROOT/usr/bin/pnpm" | "$TEST_SYSTEM_ROOT/usr/bin/pnpx")
    grep -Fxq 'pacman:pnpm' "$TEST_PACKAGE_DB" || exit 1
    printf 'pnpm\n'
    ;;
  "$TEST_SYSTEM_ROOT/usr/lib/node_modules/corepack/dist/pnpm.js" | "$TEST_SYSTEM_ROOT/usr/lib/node_modules/corepack/dist/pnpx.js")
    grep -Fxq 'pacman:corepack' "$TEST_PACKAGE_DB" || exit 1
    printf 'corepack\n'
    ;;
  *) exit 1 ;;
  esac
  ;;
-Sy)
  [[ "$*" == '-Sy --needed archlinux-keyring' ]] || exit 2
  [[ ${TEST_FAIL_MANAGER:-} != pacman ]] || exit 42
  [[ ${TEST_FAIL_PACMAN_STEP:-} != keyring ]] || exit 41
  if grep -Fxq 'pacman:archlinux-keyring-current' "$TEST_PACKAGE_DB"; then
    printf 'pacman-keyring skipped current\n' >>"$TEST_PACKAGE_LOG"
  else
    grep -Fxq 'pacman:archlinux-keyring' "$TEST_PACKAGE_DB" || printf 'pacman:archlinux-keyring\n' >>"$TEST_PACKAGE_DB"
    printf 'pacman:archlinux-keyring-current\n' >>"$TEST_PACKAGE_DB"
    printf 'pacman-keyring upgraded first\n' >>"$TEST_PACKAGE_LOG"
  fi
  ;;
-Su)
  [[ ${TEST_FAIL_MANAGER:-} != pacman ]] || exit 42
  [[ ${TEST_FAIL_PACMAN_STEP:-} != full ]] || exit 42
  if [[ ${TEST_PACMAN_NETWORK_FAILURE:-} == 1 ]]; then
    printf '%s\n' "error: failed retrieving file 'fixture.pkg.tar.zst': Operation too slow" >&2
    printf '%s\n' 'error: failed to commit transaction (failed to retrieve some files)' >&2
    exit 42
  fi
  if [[ ${TEST_NO_INSTALL_MANAGER:-} != pacman ]]; then
    for package in "$@"; do
      case "$package" in -Su | --needed) continue ;; esac
      grep -Fxq "pacman:$package" "$TEST_PACKAGE_DB" || printf 'pacman:%s\n' "$package" >>"$TEST_PACKAGE_DB"
    done
  fi
  ;;
-S)
  [[ ${TEST_FAIL_MANAGER:-} != pacman ]] || exit 42
  if [[ ${TEST_NO_INSTALL_MANAGER:-} != pacman ]]; then
    for package in "$@"; do
      case "$package" in -S | --needed) continue ;; esac
      grep -Fxq "pacman:$package" "$TEST_PACKAGE_DB" || printf 'pacman:%s\n' "$package" >>"$TEST_PACKAGE_DB"
    done
  fi
  ;;
*) exit 2 ;;
esac
EOF

cat >"$fake_bin/dpkg-query" <<'EOF'
#!/usr/bin/env bash
printf 'pkg-query %s\n' "$*" >>"$TEST_PACKAGE_LOG"
package="${*: -1}"
grep -Fxq "pkg:$package" "$TEST_PACKAGE_DB" || exit 1
printf 'install ok installed\n'
EOF

cat >"$fake_bin/pkg" <<'EOF'
#!/usr/bin/env bash
set -u
printf 'pkg %s\n' "$*" >>"$TEST_PACKAGE_LOG"
case "${1:-}" in
upgrade) exit 0 ;;
install)
  [[ ${TEST_FAIL_MANAGER:-} != pkg ]] || exit 42
  if [[ ${TEST_NO_INSTALL_MANAGER:-} != pkg ]]; then
    for package in "$@"; do
      case "$package" in install | -y | --) continue ;; esac
      grep -Fxq "pkg:$package" "$TEST_PACKAGE_DB" || printf 'pkg:%s\n' "$package" >>"$TEST_PACKAGE_DB"
    done
  fi
  ;;
*) exit 2 ;;
esac
EOF

cat >"$fake_bin/npm" <<'EOF'
#!/usr/bin/env bash
set -u
printf 'npm %s\n' "$*" >>"$TEST_PACKAGE_LOG"
case "${1:-}" in
list)
  package="${*: -1}"
  grep -Fxq "npm_global:$package" "$TEST_PACKAGE_DB"
  ;;
install)
  [[ ${TEST_FAIL_MANAGER:-} != npm_global ]] || exit 42
  if [[ ${TEST_NO_INSTALL_MANAGER:-} != npm_global ]]; then
    for package in "$@"; do
      case "$package" in install | --global | -g | --) continue ;; esac
      grep -Fxq "npm_global:$package" "$TEST_PACKAGE_DB" || printf 'npm_global:%s\n' "$package" >>"$TEST_PACKAGE_DB"
    done
  fi
  ;;
*) exit 2 ;;
esac
EOF

cat >"$fake_bin/python" <<'EOF'
#!/usr/bin/env bash
set -u
printf 'python %s\n' "$*" >>"$TEST_PACKAGE_LOG"
[[ ${1:-} == -m && ${2:-} == pip ]] || exit 2
case "${3:-}" in
show)
  package="${*: -1}"
  grep -Fxq "pip_user:$package" "$TEST_PACKAGE_DB"
  ;;
install)
  [[ ${TEST_FAIL_MANAGER:-} != pip_user ]] || exit 42
  if [[ ${TEST_NO_INSTALL_MANAGER:-} != pip_user ]]; then
    for package in "$@"; do
      case "$package" in -m | pip | install | --user | --upgrade | --) continue ;; esac
      grep -Fxq "pip_user:$package" "$TEST_PACKAGE_DB" || printf 'pip_user:%s\n' "$package" >>"$TEST_PACKAGE_DB"
    done
  fi
  ;;
*) exit 2 ;;
esac
EOF

cat >"$fake_bin/corepack" <<'EOF'
#!/usr/bin/env bash
printf 'corepack %s\n' "$*" >>"$TEST_PACKAGE_LOG"
exit 99
EOF
chmod +x "$fake_bin"/*

preset="$test_root/package-execution-preset.json"
jq '
  .id="package-execution" | .features=[] |
  .platforms.arch={pacman:["pacman-target"],npm_global:["npm-target"],pip_user:["pip-target"]} |
  .platforms.wsl={pacman:["pacman-target"],npm_global:["npm-target"],pip_user:["pip-target"]} |
  .platforms.termux={pkg:["pkg-target"],npm_global:["npm-target"],pip_user:["pip-target"]}
' "$repo_root/presets/minimal.json" >"$preset"

collision_preset="$test_root/collision-preset.json"
jq '
  .id="collision" | .features=[] |
  .platforms.arch={pacman:["pnpm"],npm_global:[],pip_user:[]} |
  .platforms.wsl={pacman:["pnpm"],npm_global:[],pip_user:[]} |
  .platforms.termux={pkg:[],npm_global:[],pip_user:[]}
' "$repo_root/presets/minimal.json" >"$collision_preset"

packages_help="$("$repo_root/bin/j3w1zsh" help packages)"
grep -q 'repair-provenance --manager MANAGER' <<<"$packages_help"
install_help="$("$repo_root/bin/j3w1zsh" help install)"
grep -q 'refreshes selected rolling software' <<<"$install_help"

fixture_home="$test_root/home"
reset_fixture() {
  local platform="$1"
  rm -rf -- "$fixture_home"
  mkdir -p "$fixture_home"
  : >"$package_db"
  : >"$package_log"
  local package
  for package in bash coreutils git jq; do
    printf '%s:%s\n' "$([[ $platform == termux ]] && printf pkg || printf pacman)" "$package" >>"$package_db"
  done
  if [[ $platform != termux ]]; then
    printf '%s\n' pacman:archlinux-keyring pacman:archlinux-keyring-current >>"$package_db"
  fi
}

run_fixture() {
  local platform="$1"
  shift
  timeout 12 env \
    HOME="$fixture_home" \
    XDG_STATE_HOME="$fixture_home/.local/state" \
    XDG_CONFIG_HOME="$fixture_home/.config" \
    XDG_CACHE_HOME="$fixture_home/.cache" \
    PATH="$fake_bin:$PATH" \
    J3W1ZSH_TEST_MODE=1 \
    J3W1ZSH_TEST_EFFECTIVE_UID=1000 \
    J3W1ZSH_TEST_PLATFORM="$platform" \
    J3W1ZSH_TEST_PACKAGE_ADAPTERS=1 \
    J3W1ZSH_TEST_SYSTEM_ROOT="$system_root" \
    TEST_SYSTEM_ROOT="$system_root" \
    TEST_PACKAGE_DB="$package_db" \
    TEST_PACKAGE_LOG="$package_log" \
    TEST_FAIL_MANAGER="${TEST_FAIL_MANAGER:-}" \
    TEST_FAIL_PACMAN_STEP="${TEST_FAIL_PACMAN_STEP:-}" \
    TEST_PACMAN_NETWORK_FAILURE="${TEST_PACMAN_NETWORK_FAILURE:-0}" \
    TEST_NO_INSTALL_MANAGER="${TEST_NO_INSTALL_MANAGER:-}" \
    "$repo_root/bin/j3w1zsh" "$@" </dev/null
}

# Every base phase is invoked as a simple command. This adversarial body would
# be swallowed if a phase function were ever placed back inside an if/&&/||
# condition: `false` would be ignored, the sentinel would be written, and the
# phase would return success.
for audited_phase in 00-preflight 10-platform 20-packages 30-shell 40-config 50-theme 60-neovim 70-codex 80-github 90-verify; do
  audit_home="$test_root/phase-audit-$audited_phase"
  mkdir -p "$audit_home"
  set +e
  env \
    HOME="$audit_home" \
    XDG_STATE_HOME="$audit_home/.local/state" \
    XDG_CONFIG_HOME="$audit_home/.config" \
    XDG_CACHE_HOME="$audit_home/.cache" \
    J3W1ZSH_REPO_ROOT="$repo_root" \
    J3W1ZSH_TEST_MODE=1 \
    J3W1ZSH_TEST_PLATFORM=wsl \
    TEST_AUDITED_PHASE="$audited_phase" \
    TEST_AUDIT_SENTINEL="$audit_home/swallowed-failure" \
    bash -c '
      set -Eeuo pipefail
      source "$J3W1ZSH_REPO_ROOT/scripts/lib/core/init.sh"
      source "$J3W1ZSH_REPO_ROOT/scripts/commands/install.sh"
      J3W1ZSH_FORCE=1
      J3W1ZSH_DRY_RUN=0
      export J3W1ZSH_FORCE J3W1ZSH_DRY_RUN
      j3w1zsh_test_failing_phase() { false; touch "$TEST_AUDIT_SENTINEL"; return 0; }
      phase_00_preflight() { j3w1zsh_test_failing_phase; }
      phase_10_platform() { j3w1zsh_test_failing_phase; }
      phase_20_packages() { j3w1zsh_test_failing_phase; }
      phase_30_shell() { j3w1zsh_test_failing_phase; }
      phase_40_config() { j3w1zsh_test_failing_phase; }
      phase_50_theme() { j3w1zsh_test_failing_phase; }
      phase_60_neovim() { j3w1zsh_test_failing_phase; }
      phase_70_codex() { j3w1zsh_test_failing_phase; }
      phase_80_github() { j3w1zsh_test_failing_phase; }
      phase_90_verify() { j3w1zsh_test_failing_phase; }
      j3w1zsh_execute_phase "$TEST_AUDITED_PHASE" "" ""
      touch "$TEST_AUDIT_SENTINEL.after"
    ' >/dev/null 2>&1
  audit_result=$?
  set -e
  [[ $audit_result == 1 ]]
  [[ ! -e $audit_home/swallowed-failure && ! -e $audit_home/swallowed-failure.after ]]
  [[ ! -e $audit_home/.local/state/j3w1zsh/phases/$audited_phase.json ]]
done

assert_no_false_record() {
  local manager="$1" package="$2" ledger="$fixture_home/.local/state/j3w1zsh/packages/provenance.json"
  [[ ! -f $ledger ]] || jq -e --arg manager "$manager" --arg package "$package" \
    'all(.packages[]; .manager != $manager or .package != $package)' "$ledger" >/dev/null
}

assert_arch_refresh_sequence() {
  local selected="$1" sync_line upgrade_line
  [[ $(grep -Fxc 'pacman -Sy --needed archlinux-keyring' "$package_log") == 1 ]]
  [[ $(grep -Fxc "pacman -Su --needed $selected" "$package_log") == 1 ]]
  sync_line="$(grep -Fnx 'pacman -Sy --needed archlinux-keyring' "$package_log" | cut -d: -f1)"
  upgrade_line="$(grep -Fnx "pacman -Su --needed $selected" "$package_log" | cut -d: -f1)"
  ((sync_line < upgrade_line))
  if grep -Eq '^pacman -Syy|^pacman -Syu|^pacman -Suu' "$package_log"; then
    printf 'Explicit Arch refresh used forced database refresh, a combined transaction, or downgrade semantics.\n' >&2
    exit 1
  fi
  if grep -E '^pacman -Sy( |$)' "$package_log" | grep -Fvx 'pacman -Sy --needed archlinux-keyring' >/dev/null; then
    printf 'Explicit Arch refresh used an unsupported standalone sync transaction.\n' >&2
    exit 1
  fi
}

selected_fixture_packages='bash coreutils git jq pacman-target'

mapfile -t standalone_sync_sites < <(rg -n 'j3w1zsh_run sudo pacman -Sy( |")' "$repo_root/scripts" --glob '*.sh')
[[ ${#standalone_sync_sites[@]} == 1 ]]
[[ ${standalone_sync_sites[0]} == *'j3w1zsh_run sudo pacman -Sy --needed archlinux-keyring'* ]]
if rg -n 'pacman -Syy' "$repo_root/scripts" --glob '*.sh' >/dev/null; then
  printf 'Routine implementation contains a forced Pacman database refresh.\n' >&2
  exit 1
fi

# One aggregate phase reconciles all three typed package actions exactly once.
reset_fixture wsl
success_output="$(run_fixture wsl install --preset "$preset" --packages-only --force --yes --plain)"
[[ $(grep -c '^\[+\] Phase 20-packages$' <<<"$success_output") == 1 ]]
assert_arch_refresh_sequence "$selected_fixture_packages"
grep -Fxq 'pacman-keyring skipped current' "$package_log"
[[ $(grep -Fc 'pacman -Q -- pacman-target' "$package_log") == 2 ]]
grep -Fxq 'pacman:pacman-target' "$package_db"
grep -Fxq 'npm_global:npm-target' "$package_db"
grep -Fxq 'pip_user:pip-target' "$package_db"
phase_marker="$fixture_home/.local/state/j3w1zsh/phases/20-packages.json"
ledger="$fixture_home/.local/state/j3w1zsh/packages/provenance.json"
[[ -f $phase_marker && ! -e $fixture_home/.local/state/j3w1zsh/phases/30-shell.json ]]
jq -e '
  (.packages[] | select(.manager=="pacman" and .package=="pacman-target") | .pre_existing==false and .installed_by_j3w1zsh==true) and
  (.packages[] | select(.manager=="pacman" and .package=="bash") | .pre_existing==true and .installed_by_j3w1zsh==false)
' "$ledger" >/dev/null
ledger_before="$(sha256sum "$ledger")"
: >"$package_log"
rerun_output="$(run_fixture wsl install --preset "$preset" --packages-only --yes --plain)"
[[ $(grep -c '^\[+\] Phase 20-packages$' <<<"$rerun_output") == 1 ]]
if grep -q 'Skipping completed phase: 20-packages' <<<"$rerun_output"; then
  printf 'Explicit package refresh skipped a completed phase marker.\n' >&2
  exit 1
fi
assert_arch_refresh_sequence "$selected_fixture_packages"
grep -Fxq 'pacman-keyring skipped current' "$package_log"
grep -Fq 'npm install --global npm-target' "$package_log"
grep -Fq 'python -m pip install --user --upgrade pip-target' "$package_log"
[[ $(sha256sum "$ledger") == "$ledger_before" ]]

# A repeat explicit install with one selected package missing still uses the
# same coherent full transaction and preserves the original ownership record.
grep -Fxv 'pacman:pacman-target' "$package_db" >"$package_db.next"
mv -- "$package_db.next" "$package_db"
: >"$package_log"
run_fixture wsl install --preset "$preset" --packages-only --yes --plain >/dev/null
assert_arch_refresh_sequence "$selected_fixture_packages"
grep -Fxq 'pacman:pacman-target' "$package_db"
[[ $(sha256sum "$ledger") == "$ledger_before" ]]

# A stale native-Arch keyring is reconciled in the first transaction and the
# full upgrade with every selected target follows immediately.
reset_fixture arch
grep -Fxv 'pacman:archlinux-keyring-current' "$package_db" >"$package_db.next"
mv -- "$package_db.next" "$package_db"
stale_output="$(run_fixture arch install --preset "$preset" --packages-only --force --yes --plain)"
[[ $(grep -c '^\[+\] Phase 20-packages$' <<<"$stale_output") == 1 ]]
assert_arch_refresh_sequence "$selected_fixture_packages"
grep -Fxq 'pacman-keyring upgraded first' "$package_log"
grep -Fxq 'pacman:archlinux-keyring-current' "$package_db"
grep -Fxq 'pacman:pacman-target' "$package_db"
[[ -f $phase_marker ]]

# Dry-run describes the bounded keyring-first sequence without executing a
# Pacman command or writing package state.
reset_fixture wsl
dry_run_json="$(run_fixture wsl install --preset "$preset" --packages-only --force --yes --dry-run --json)"
jq -e '
  .status == "ok" and .data.dry_run == true and
  (.data.actions[] | select(.id == "pacman-packages") | .reason |
    contains("run pacman -Sy --needed archlinux-keyring, then immediately run pacman -Su --needed"))
' <<<"$dry_run_json" >/dev/null
[[ ! -s $package_log && ! -e $phase_marker && ! -e $ledger ]]

# Failure of the keyring transaction stops before the full upgrade, package
# provenance, phase completion, and every later phase.
reset_fixture wsl
set +e
TEST_FAIL_PACMAN_STEP=keyring run_fixture wsl install --preset "$preset" --force --yes --plain >"$test_root/keyring-failure.out" 2>&1
keyring_failure_result=$?
set -e
[[ $keyring_failure_result == 41 ]]
grep -Fxq 'pacman -Sy --needed archlinux-keyring' "$package_log"
if grep -Eq '^pacman -Su( |$)|^npm install|^python -m pip install' "$package_log"; then
  printf 'Keyring failure continued into a later package transaction.\n' >&2
  exit 1
fi
[[ ! -e $phase_marker && ! -e $ledger ]]
[[ ! -e $fixture_home/.local/state/j3w1zsh/phases/30-shell.json ]]
[[ ! -e $fixture_home/.local/state/j3w1zsh/phases/90-verify.json ]]

# A retrieval timeout in the full-upgrade transaction remains a network error,
# not a signing diagnosis. It stops the phase after the successful keyring
# preflight, and the same package phase is resumable on retry.
reset_fixture wsl
set +e
TEST_PACMAN_NETWORK_FAILURE=1 run_fixture wsl install --preset "$preset" --force --yes --plain >"$test_root/network-failure.out" 2>&1
network_failure_result=$?
set -e
[[ $network_failure_result == 42 ]]
assert_arch_refresh_sequence "$selected_fixture_packages"
grep -q 'failed retrieving file.*Operation too slow' "$test_root/network-failure.out"
grep -q 'failed to commit transaction (failed to retrieve some files)' "$test_root/network-failure.out"
if grep -Eqi 'unknown trust|invalid signature|keyring (failure|error)|signing failure' "$test_root/network-failure.out"; then
  printf 'Network retrieval failure was misclassified as a signing or keyring failure.\n' >&2
  exit 1
fi
[[ ! -e $phase_marker && ! -e $ledger ]]
[[ ! -e $fixture_home/.local/state/j3w1zsh/phases/30-shell.json ]]
[[ ! -e $fixture_home/.local/state/j3w1zsh/phases/90-verify.json ]]
: >"$package_log"
retry_output="$(run_fixture wsl install --preset "$preset" --packages-only --force --yes --plain)"
assert_arch_refresh_sequence "$selected_fixture_packages"
[[ $(grep -c '^\[+\] Phase 20-packages$' <<<"$retry_output") == 1 && -f $phase_marker ]]
jq -e '.packages[] | select(.manager=="pacman" and .package=="pacman-target" and .installed_by_j3w1zsh==true)' "$ledger" >/dev/null

# Package-free and package-only selection retain their exact boundaries.
reset_fixture wsl
package_free_output="$(run_fixture wsl install --preset "$preset" --no-packages --only 20-packages --force --yes --plain 2>&1)"
[[ $(grep -c '^\[+\] Phase 20-packages$' <<<"$package_free_output") == 1 ]]
[[ -f $phase_marker && ! -f $ledger ]]
if grep -Eq '^(pacman -S|npm install|python -m pip install)' "$package_log"; then
  printf 'Package-free mode invoked an acquisition command.\n' >&2
  exit 1
fi

assert_manager_failure() {
  local platform="$1" manager="$2" package="$3" result
  reset_fixture "$platform"
  set +e
  TEST_FAIL_MANAGER="$manager" run_fixture "$platform" install --preset "$preset" --force --yes --plain >"$test_root/failure-$manager.out" 2>&1
  result=$?
  set -e
  [[ $result == 42 ]]
  [[ ! -e $phase_marker ]]
  [[ ! -e $fixture_home/.local/state/j3w1zsh/phases/30-shell.json ]]
  [[ ! -e $fixture_home/.local/state/j3w1zsh/phases/40-config.json ]]
  [[ ! -e $fixture_home/.local/state/j3w1zsh/phases/90-verify.json ]]
  assert_no_false_record "$manager" "$package"
}

assert_manager_failure wsl pacman pacman-target
assert_manager_failure wsl npm_global npm-target
assert_manager_failure wsl pip_user pip-target
assert_manager_failure termux pkg pkg-target

# A zero transaction exit is insufficient: manager verification must turn true
# before provenance or a phase marker can be written.
reset_fixture wsl
set +e
TEST_NO_INSTALL_MANAGER=pacman run_fixture wsl install --preset "$preset" --force --yes --plain >"$test_root/unverified.out" 2>&1
unverified_result=$?
set -e
[[ $unverified_result == 1 ]]
grep -q 'did not verify the required package' "$test_root/unverified.out"
[[ ! -e $phase_marker ]]
assert_no_false_record pacman pacman-target

# A failed transaction is deterministic: no marker is created, and the next
# healthy run reconciles once and records only manager-verified packages.
reset_fixture wsl
set +e
TEST_FAIL_MANAGER=pacman run_fixture wsl install --preset "$preset" --packages-only --force --yes --plain >/dev/null 2>&1
first_result=$?
set -e
[[ $first_result == 42 && ! -e $phase_marker ]]
retry_output="$(run_fixture wsl install --preset "$preset" --packages-only --force --yes --plain)"
[[ $(grep -c '^\[+\] Phase 20-packages$' <<<"$retry_output") == 1 && -f $phase_marker ]]
jq -e '.packages[] | select(.manager=="pacman" and .package=="pacman-target" and .installed_by_j3w1zsh==true)' "$ledger" >/dev/null

# Termux uses the same aggregate phase and post-manager verification contract.
reset_fixture termux
termux_output="$(run_fixture termux install --preset "$preset" --packages-only --force --yes --plain)"
[[ $(grep -c '^\[+\] Phase 20-packages$' <<<"$termux_output") == 1 ]]
grep -Fxq 'pkg:pkg-target' "$package_db"
grep -Fxq 'npm_global:npm-target' "$package_db"
grep -Fxq 'pip_user:pip-target' "$package_db"
jq -e '.packages[] | select(.manager=="pkg" and .package=="pkg-target" and .installed_by_j3w1zsh==true)' "$ledger" >/dev/null
grep -Fq 'pkg upgrade -y' "$package_log"
grep -Fq 'pkg install -y bash coreutils git jq pkg-target' "$package_log"
: >"$package_log"
run_fixture termux install --preset "$preset" --packages-only --yes --plain >/dev/null
grep -Fq 'pkg upgrade -y' "$package_log"
grep -Fq 'pkg install -y bash coreutils git jq pkg-target' "$package_log"
grep -Fq 'npm install --global npm-target' "$package_log"
grep -Fq 'python -m pip install --user --upgrade pip-target' "$package_log"
if grep -Eq '^sudo |systemctl|systemd' "$package_log"; then
  printf 'Termux package refresh invoked a privileged or systemd operation.\n' >&2
  exit 1
fi

# Product update reconciliation installs newly required packages without
# turning a source update into a full Arch or Termux upgrade.
reset_fixture wsl
env \
  HOME="$fixture_home" \
  XDG_STATE_HOME="$fixture_home/.local/state" \
  XDG_CONFIG_HOME="$fixture_home/.config" \
  XDG_CACHE_HOME="$fixture_home/.cache" \
  PATH="$fake_bin:$PATH" \
  J3W1ZSH_REPO_ROOT="$repo_root" \
  J3W1ZSH_TEST_MODE=1 \
  J3W1ZSH_TEST_EFFECTIVE_UID=1000 \
  J3W1ZSH_TEST_PLATFORM=wsl \
  J3W1ZSH_TEST_SYSTEM_ROOT="$system_root" \
  TEST_SYSTEM_ROOT="$system_root" \
  TEST_PACKAGE_DB="$package_db" \
  TEST_PACKAGE_LOG="$package_log" \
  TEST_PRESET="$preset" \
  bash -c '
    set -Eeuo pipefail
    source "$J3W1ZSH_REPO_ROOT/scripts/lib/core/init.sh"
    source "$J3W1ZSH_REPO_ROOT/scripts/lib/presets.sh"
    source "$J3W1ZSH_REPO_ROOT/scripts/lib/packages.sh"
    source "$J3W1ZSH_REPO_ROOT/scripts/lib/core/plan.sh"
    j3w1zsh_resolve_preset "$TEST_PRESET"
    J3W1ZSH_PACKAGE_REFRESH=0
    J3W1ZSH_PACKAGE_PLAN_DIGEST="$(printf "9%.0s" {1..64})"
    export J3W1ZSH_PACKAGE_REFRESH J3W1ZSH_PACKAGE_PLAN_DIGEST
    j3w1zsh_install_package_set pacman "$(j3w1zsh_packages_for_manager_json pacman)"
    j3w1zsh_install_package_set npm_global "$(j3w1zsh_packages_for_manager_json npm_global)"
    j3w1zsh_install_package_set pip_user "$(j3w1zsh_packages_for_manager_json pip_user)"
  '
grep -Fq 'pacman -S --needed pacman-target' "$package_log"
if grep -Eq '^pacman -S(y|u) |^pkg upgrade ' "$package_log"; then
  printf 'Product update reconciliation performed a rolling full refresh.\n' >&2
  exit 1
fi
grep -Fq 'j3w1zsh_install_command_mode update' "$repo_root/scripts/commands/update.sh"

# The exact Corepack/Pacman collision pauses before package mutation. Unknown
# path content is protected, and j3w1zsh never invokes Corepack automatically.
reset_fixture wsl
printf 'pacman:corepack\n' >>"$package_db"
printf 'corepack pnpm target\n' >"$system_root/usr/lib/node_modules/corepack/dist/pnpm.js"
printf 'corepack pnpx target\n' >"$system_root/usr/lib/node_modules/corepack/dist/pnpx.js"
ln -s ../lib/node_modules/corepack/dist/pnpm.js "$system_root/usr/bin/pnpm"
ln -s ../lib/node_modules/corepack/dist/pnpx.js "$system_root/usr/bin/pnpx"
set +e
run_fixture wsl install --preset "$collision_preset" --packages-only --force --yes --plain >"$test_root/collision.out" 2>&1
collision_result=$?
set -e
[[ $collision_result == 20 ]]
grep -q 'exact Corepack shims' "$test_root/collision.out"
[[ -L $system_root/usr/bin/pnpm && -L $system_root/usr/bin/pnpx && ! -e $phase_marker ]]
[[ -f $fixture_home/.local/state/j3w1zsh/manual/pacman-pnpm-corepack-collision.json ]]
if grep -Eq '^pacman -S(y|u)? ' "$package_log" || grep -q '^corepack ' "$package_log"; then
  printf 'Known collision invoked Pacman acquisition or Corepack automatically.\n' >&2
  exit 1
fi

rm -- "$system_root/usr/bin/pnpx"
printf 'owner-authored collision\n' >"$system_root/usr/bin/pnpx"
set +e
run_fixture wsl install --preset "$collision_preset" --packages-only --force --yes --plain >"$test_root/ambiguous.out" 2>&1
ambiguous_result=$?
set -e
[[ $ambiguous_result == 21 ]]
grep -q 'does not match the exact Corepack-owned shim contract' "$test_root/ambiguous.out"
grep -qx 'owner-authored collision' "$system_root/usr/bin/pnpx"
if grep -Eq '^pacman -S(y|u)? ' "$package_log"; then
  printf 'Ambiguous collision invoked Pacman acquisition.\n' >&2
  exit 1
fi

rm -- "$system_root/usr/bin/pnpm" "$system_root/usr/bin/pnpx"
resolved_output="$(run_fixture wsl install --preset "$collision_preset" --packages-only --force --yes --plain)"
[[ $(grep -c '^\[+\] Phase 20-packages$' <<<"$resolved_output") == 1 ]]
grep -Fxq 'pacman:pnpm' "$package_db"
[[ -f $phase_marker && ! -e $fixture_home/.local/state/j3w1zsh/manual/pacman-pnpm-corepack-collision.json ]]
if grep -q '^corepack ' "$package_log"; then
  printf 'Resolved collision invoked Corepack automatically.\n' >&2
  exit 1
fi

# A later full refresh recognizes the healthy Pacman-owned pnpm paths and does
# not mistake them for the former unowned Corepack shims.
printf 'pacman pnpm executable\n' >"$system_root/usr/bin/pnpm"
printf 'pacman pnpx executable\n' >"$system_root/usr/bin/pnpx"
healthy_refresh="$(run_fixture wsl install --preset "$collision_preset" --packages-only --yes --plain)"
[[ $(grep -c '^\[+\] Phase 20-packages$' <<<"$healthy_refresh") == 1 ]]
grep -Fq 'pacman -Sy --needed archlinux-keyring' "$package_log"
grep -Fq 'pacman -Su --needed bash coreutils git jq pnpm' "$package_log"

# Repair is explicit, dry-runnable, exact-targeted, manager-verified, evidence
# preserving, and leaves every unrelated ledger record unchanged.
reset_fixture wsl
state_packages="$fixture_home/.local/state/j3w1zsh/packages"
state_phases="$fixture_home/.local/state/j3w1zsh/phases"
mkdir -p "$state_packages" "$state_phases"
digest="$(printf 'a%.0s' {1..64})"
jq -n --arg digest "$digest" '{schema_version:1,packages:[
  {manager:"pacman",package:"pnpm",declaring_layers:["preset"],pre_existing:false,installed_by_j3w1zsh:true,first_seen_product_version:"1.0.0",last_required_plan_digest:$digest},
  {manager:"pacman",package:"stylua",declaring_layers:["preset"],pre_existing:false,installed_by_j3w1zsh:true,first_seen_product_version:"1.0.0",last_required_plan_digest:$digest},
  {manager:"pacman",package:"unrelated",declaring_layers:["user"],pre_existing:false,installed_by_j3w1zsh:true,first_seen_product_version:"1.0.0",last_required_plan_digest:$digest}
]}' >"$state_packages/provenance.json"
printf 'pacman:unrelated\n' >>"$package_db"
printf '{"phase":"20-packages","sentinel":"false-complete"}\n' >"$state_phases/20-packages.json"
unrelated_before="$(jq -S -c '.packages[] | select(.package=="unrelated")' "$state_packages/provenance.json")"
ledger_digest_before="$(sha256sum "$state_packages/provenance.json")"
marker_digest_before="$(sha256sum "$state_phases/20-packages.json")"
repair_dry="$(run_fixture wsl packages repair-provenance --manager pacman --package pnpm --package stylua --dry-run --yes --json --preset "$preset")"
jq -e '.status=="ok" and .data.dry_run==true and ([.data.candidates[].package] | sort)==["pnpm","stylua"]' <<<"$repair_dry" >/dev/null
[[ $(sha256sum "$state_packages/provenance.json") == "$ledger_digest_before" ]]
[[ $(sha256sum "$state_phases/20-packages.json") == "$marker_digest_before" ]]
[[ ! -e $state_packages/repairs ]]

repair_actual="$(run_fixture wsl packages repair-provenance --manager pacman --package pnpm --package stylua --yes --json --preset "$preset")"
jq -e '.status=="ok" and ([.data.repaired[].package] | sort)==["pnpm","stylua"] and .data.phase_invalidated=="20-packages"' <<<"$repair_actual" >/dev/null
jq -e '([.packages[].package] | sort)==["unrelated"]' "$state_packages/provenance.json" >/dev/null
[[ $(jq -S -c '.packages[] | select(.package=="unrelated")' "$state_packages/provenance.json") == "$unrelated_before" ]]
[[ ! -e $state_phases/20-packages.json ]]
repair_evidence="$(find "$state_packages/repairs" -maxdepth 1 -type f -name '*.json' -print -quit)"
jq -e '([.removed_records[].package] | sort)==["pnpm","stylua"] and .invalidated_phase_marker.sentinel=="false-complete"' "$repair_evidence" >/dev/null
grep -Fxq 'pacman:unrelated' "$package_db"

# Repair never follows a package-state directory symlink, even in dry-run.
reset_fixture wsl
outside_packages="$test_root/outside-package-state"
mkdir -p "$outside_packages" "$fixture_home/.local/state/j3w1zsh"
jq -n --arg digest "$digest" '{schema_version:1,packages:[
  {manager:"pacman",package:"pnpm",declaring_layers:["preset"],pre_existing:false,installed_by_j3w1zsh:true,first_seen_product_version:"1.0.0",last_required_plan_digest:$digest}
]}' >"$outside_packages/provenance.json"
outside_digest="$(sha256sum "$outside_packages/provenance.json")"
ln -s "$outside_packages" "$fixture_home/.local/state/j3w1zsh/packages"
set +e
run_fixture wsl packages repair-provenance --manager pacman --package pnpm --dry-run --yes --preset "$preset" >/dev/null 2>&1
symlink_repair_result=$?
set -e
[[ $symlink_repair_result == 21 ]]
[[ $(sha256sum "$outside_packages/provenance.json") == "$outside_digest" && ! -e $outside_packages/repairs ]]

printf 'Single-pass phases, manager failures, verified provenance, collision checkpoints, and bounded repair tests passed.\n'
