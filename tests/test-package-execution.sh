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
  "$TEST_SYSTEM_ROOT/usr/lib/node_modules/corepack/dist/pnpm.js" | "$TEST_SYSTEM_ROOT/usr/lib/node_modules/corepack/dist/pnpx.js")
    grep -Fxq 'pacman:corepack' "$TEST_PACKAGE_DB" || exit 1
    printf 'corepack\n'
    ;;
  *) exit 1 ;;
  esac
  ;;
-S | -Syu)
  [[ ${TEST_FAIL_MANAGER:-} != pacman ]] || exit 42
  if [[ ${TEST_NO_INSTALL_MANAGER:-} != pacman ]]; then
    for package in "$@"; do
      case "$package" in -S | -Syu | --needed) continue ;; esac
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
      case "$package" in -m | pip | install | --user | --) continue ;; esac
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

# One aggregate phase reconciles all three typed package actions exactly once.
reset_fixture wsl
success_output="$(run_fixture wsl install --preset "$preset" --packages-only --force --yes --plain)"
[[ $(grep -c '^\[+\] Phase 20-packages$' <<<"$success_output") == 1 ]]
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
log_before="$(sha256sum "$package_log")"
rerun_output="$(run_fixture wsl install --preset "$preset" --packages-only --yes --plain)"
grep -q 'Skipping completed phase: 20-packages' <<<"$rerun_output"
[[ $(sha256sum "$ledger") == "$ledger_before" && $(sha256sum "$package_log") == "$log_before" ]]

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
if grep -Eq '^pacman -(S|Syu) ' "$package_log" || grep -q '^corepack ' "$package_log"; then
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
if grep -Eq '^pacman -(S|Syu) ' "$package_log"; then
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
