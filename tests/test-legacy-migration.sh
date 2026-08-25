#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
test_root="$(mktemp -d)"
trap 'rm -rf -- "$test_root"' EXIT
migration="$repo_root/scripts/legacy/migrate-to-j3w1zsh.sh"
fixture_bin="$test_root/bin"
mkdir -p "$fixture_bin"
[[ $(grep -Ec "^[[:space:]]*rm -rf -- \"\\\$path\"$" "$migration") == 1 ]]
[[ $(grep -Ec '^[[:space:]]*rm -r[[:space:]]' "$migration") == 0 ]]
for fixture_command in gh nvim tmux; do
  cat >"$fixture_bin/$fixture_command" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$fixture_bin/$fixture_command"
done

# Build an immutable local stand-in for the exact post-rename repository candidate.
new_seed="$test_root/new-seed"
new_remote="$test_root/j3w1zsh.git"
mkdir -p "$new_seed"
(
  cd "$repo_root"
  tar --exclude=.git -cf - .
) | tar -C "$new_seed" -xf -
git -C "$new_seed" init -q -b main
git -C "$new_seed" config user.name 'Migration Tests'
git -C "$new_seed" config user.email 'tests@example.invalid'
git -C "$new_seed" add .
git -C "$new_seed" commit -q -m 'fixture: exact j3w1zsh candidate'
new_oid="$(git -C "$new_seed" rev-parse HEAD)"
git clone -q --bare "$new_seed" "$new_remote"

# Build the former canonical fixture with a tracked generated-lock path and remote main.
old_seed="$test_root/old-seed"
old_remote="$test_root/former.git"
mkdir -p "$old_seed/bin" "$old_seed/dotfiles/nvim/.config/nvim"
printf '# former fixture\n' >"$old_seed/README.md"
printf '{}\n' >"$old_seed/dotfiles/nvim/.config/nvim/lazy-lock.json"
printf '#!/usr/bin/env bash\nprintf "former command\\n"\n' >"$old_seed/bin/bloody-writer"
chmod +x "$old_seed/bin/bloody-writer"
git -C "$old_seed" init -q -b main
git -C "$old_seed" config user.name 'Migration Tests'
git -C "$old_seed" config user.email 'tests@example.invalid'
git -C "$old_seed" add .
git -C "$old_seed" commit -q -m 'fixture: former checkout'
git clone -q --bare "$old_seed" "$old_remote"

create_old_home() {
  local fixture_home="$1"
  mkdir -p "$fixture_home/projects" "$fixture_home/.local/bin" "$fixture_home/.config/nvim"
  git clone -q "$old_remote" "$fixture_home/projects/bloody-writer"
  ln -s "$fixture_home/projects/bloody-writer/bin/bloody-writer" "$fixture_home/.local/bin/bloody-writer"
  printf '# regular partial zshrc\n' >"$fixture_home/.zshrc"
  printf '# regular partial tmux\n' >"$fixture_home/.tmux.conf"
  printf 'regular partial nvim\n' >"$fixture_home/.config/nvim/init.lua"
}

write_legacy_workspace() {
  local output="$1"
  jq -n '{
    "$schema":"https://example.invalid/workspace-v1.json",schema_version:1,
    profile:{id:"legacy-project",display_name:"Legacy project",minimum_bloody_writer_version:"0.3.0",review_state:"approved"},
    platform:{distribution:"arch",environment:"wsl",wsl_version:2},
    packages:{pacman:[],npm_global:[]},
    versions:{php:{source:".php-version",requirement:"8.5"},node:{source:".node-version",requirement:"24.0.0"},pnpm:{source:"package.json",requirement:"11.0.0"}},
    requirements:{binaries:[],php_extensions:[]},system_files:[],
    environment_guard:{app_env:"local",app_url_scope:"loopback",db_connection:"sqlite",sqlite_backup:true},
    lifecycle:{setup:[],verify:[],development:{argv:["node","dev"]}},ports:[],capabilities:{bloody_writer_base:true}
  }' >"$output"
}

run_migration() {
  local fixture_home="$1"; shift
  env \
    HOME="$fixture_home" \
    XDG_CONFIG_HOME="$fixture_home/.config" \
    XDG_STATE_HOME="$fixture_home/.local/state" \
    XDG_CACHE_HOME="$fixture_home/.cache" \
    J3W1ZSH_MIGRATION_TEST_MODE=1 \
    J3W1ZSH_MIGRATION_TEST_PLATFORM=wsl \
    J3W1ZSH_MIGRATION_REMOTE="$new_remote" \
    J3W1ZSH_MIGRATION_TEST_FORMER_REMOTE="$old_remote" \
    PATH="$fixture_bin:$PATH" \
    "$migration" "$@"
}

run_termux_migration() {
  local fixture_home="$1"; shift
  env \
    HOME="$fixture_home" \
    XDG_CONFIG_HOME="$fixture_home/.config" \
    XDG_STATE_HOME="$fixture_home/.local/state" \
    XDG_CACHE_HOME="$fixture_home/.cache" \
    J3W1ZSH_MIGRATION_TEST_MODE=1 \
    J3W1ZSH_MIGRATION_TEST_PLATFORM=termux \
    J3W1ZSH_MIGRATION_REMOTE="$new_remote" \
    J3W1ZSH_MIGRATION_TEST_FORMER_REMOTE="$old_remote" \
    PATH="$fixture_bin:$PATH" \
    "$migration" "$@"
}

# Force fetched Git objects to be write-protected after a successful fetch, matching real Git
# pack/object permissions while leaving all other fixture Git commands untouched.
instrumented_bin="$test_root/instrumented-bin"
mkdir -p "$instrumented_bin"
cat >"$instrumented_bin/git" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

: "${J3W1ZSH_TEST_REAL_GIT:?}"
set +e
"$J3W1ZSH_TEST_REAL_GIT" "$@"
result=$?
set -e
if ((result == 0)) && [[ ${J3W1ZSH_TEST_WRITE_PROTECT_FETCH:-0} == 1 && ${1:-} == -C && ${3:-} == fetch ]]; then
  object_root="$2/.git/objects"
  count=0
  pack_seen=0
  while IFS= read -r -d '' object; do
    chmod a-w -- "$object"
    ((count += 1))
    [[ $object == *.pack ]] && pack_seen=1
  done < <(find "$object_root" -type f -print0)
  printf '%s %s\n' "$count" "$pack_seen" >>"$J3W1ZSH_TEST_WRITE_PROTECT_LOG"
  ((count > 0 && pack_seen == 1))
fi
exit "$result"
EOF
chmod +x "$instrumented_bin/git"

# Doctor's repository-health check is deliberately local-only. Any accidental network Git
# operation fails this fixture and leaves a durable call log for diagnosis.
doctor_git_bin="$test_root/doctor-git-bin"
doctor_network_log="$test_root/doctor-network.log"
mkdir -p "$doctor_git_bin"
cat >"$doctor_git_bin/git" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

: "${J3W1ZSH_TEST_REAL_GIT:?}"
for argument in "$@"; do
  case "$argument" in
  fetch | ls-remote | pull | push)
    printf '%s\n' "$*" >>"$J3W1ZSH_TEST_DOCTOR_NETWORK_LOG"
    exit 97
    ;;
  esac
done
exec "$J3W1ZSH_TEST_REAL_GIT" "$@"
EOF
chmod +x "$doctor_git_bin/git"

# Dry-run resolves the exact OID through a disposable temp Git repository and creates no state.
# It must clean fetched mode-0444 pack/object files without prompting or reading confirmation,
# both without a terminal and with a pseudo-terminal attached to stdin.
dry_home="$test_root/dry-home"
create_old_home "$dry_home"
dry_tmp="$test_root/dry-tmp"
dry_protect_log="$test_root/dry-write-protected.log"
dry_non_tty_output="$test_root/dry-non-tty.out"
dry_tty_output="$test_root/dry-tty.out"
mkdir -p "$dry_tmp"
real_git="$(command -v git)"
dry_command=(
  env
  "HOME=$dry_home"
  "XDG_CONFIG_HOME=$dry_home/.config"
  "XDG_STATE_HOME=$dry_home/.local/state"
  "XDG_CACHE_HOME=$dry_home/.cache"
  "TMPDIR=$dry_tmp"
  J3W1ZSH_MIGRATION_TEST_MODE=1
  J3W1ZSH_MIGRATION_TEST_PLATFORM=wsl
  "J3W1ZSH_MIGRATION_REMOTE=$new_remote"
  "J3W1ZSH_MIGRATION_TEST_FORMER_REMOTE=$old_remote"
  "J3W1ZSH_TEST_REAL_GIT=$real_git"
  J3W1ZSH_TEST_WRITE_PROTECT_FETCH=1
  "J3W1ZSH_TEST_WRITE_PROTECT_LOG=$dry_protect_log"
  "PATH=$instrumented_bin:$fixture_bin:$PATH"
  "$migration"
  --target-ref "$new_oid"
  --expected-commit "$new_oid"
  --source "$dry_home/projects/bloody-writer"
  --dry-run
)
timeout 20s "${dry_command[@]}" </dev/null >"$dry_non_tty_output"
command -v script >/dev/null || { printf 'The pseudo-terminal regression requires util-linux script.\n' >&2; exit 1; }
printf -v dry_tty_command '%q ' "${dry_command[@]}"
timeout 20s script -qefc "$dry_tty_command" "$dry_tty_output" </dev/null >/dev/null
dry_output="$(<"$dry_non_tty_output")"
grep -q 'classification: exact-known' <<<"$dry_output"
grep -q 'no state, checkout, trust record, package, Git ref, or host configuration was changed' <<<"$dry_output"
grep -q 'Dry run complete' "$dry_tty_output"
if grep -q 'remove write-protected' "$dry_non_tty_output" "$dry_tty_output"; then
  printf 'Dry-run cleanup prompted for write-protected Git objects.\n' >&2
  exit 1
fi
awk 'NF != 2 || $1 < 1 || $2 != 1 { exit 1 } END { if (NR != 2) exit 1 }' "$dry_protect_log"
[[ -z $(find "$dry_tmp" -mindepth 1 -maxdepth 1 -name 'j3w1zsh-migration-resolve.*' -print -quit) ]]
[[ ! -e $dry_home/j3w1zsh ]]
[[ ! -e $dry_home/.local/state/j3w1zsh ]]

# Canonical main may advance after an exact migration target is published. Acquisition must
# preserve the exact requested checkout while materializing the observed full-history upstream.
printf 'canonical main advanced after candidate publication\n' >"$new_seed/tracking-advanced-marker.txt"
git -C "$new_seed" add tracking-advanced-marker.txt
git -C "$new_seed" commit -q -m 'fixture: advance canonical main'
new_main_oid="$(git -C "$new_seed" rev-parse HEAD)"
git -C "$new_seed" push -q "$new_remote" main

# An unrelated source origin fails closed before target or state mutation.
wrong_origin_home="$test_root/wrong-origin-home"
create_old_home "$wrong_origin_home"
git -C "$wrong_origin_home/projects/bloody-writer" remote set-url origin https://example.invalid/unrelated.git
set +e
wrong_origin_output="$(run_migration "$wrong_origin_home" --target-ref "$new_oid" --expected-commit "$new_oid" \
  --source "$wrong_origin_home/projects/bloody-writer" --dry-run 2>&1)"
wrong_origin_result=$?
set -e
[[ $wrong_origin_result == 1 ]]
grep -q 'neither the former nor renamed canonical repository' <<<"$wrong_origin_output"
[[ ! -e $wrong_origin_home/j3w1zsh && ! -e $wrong_origin_home/.local/state/j3w1zsh ]]

# Required post-rename partial state: renamed origin; only the former CLI link; regular dotfiles; no markers, helper, or host fragment.
partial_home="$test_root/partial-home"
create_old_home "$partial_home"
git -C "$partial_home/projects/bloody-writer" remote set-url origin https://github.com/j3w1/j3w1zsh.git
run_migration "$partial_home" --target-ref "$new_oid" --expected-commit "$new_oid" --source "$partial_home/projects/bloody-writer" >/dev/null
[[ -x $partial_home/.local/bin/j3w1zsh ]]
[[ ! -e $partial_home/.local/bin/bloody-writer && ! -L $partial_home/.local/bin/bloody-writer ]]
[[ -L $partial_home/.zshrc && -L $partial_home/.tmux.conf && -L $partial_home/.config/nvim ]]
[[ -d $partial_home/j3w1zsh/.git ]]
[[ ! -e $partial_home/projects/bloody-writer ]]
partial_status="$(git -C "$partial_home/j3w1zsh" status --short --branch | head -n1)"
[[ $partial_status != *'[gone]'* ]]
[[ $(git -C "$partial_home/j3w1zsh" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}') == origin/main ]]
[[ $(git -C "$partial_home/j3w1zsh" rev-parse '@{upstream}') == "$new_main_oid" ]]
[[ $(git -C "$partial_home/j3w1zsh" rev-parse --verify refs/remotes/origin/main) == "$new_main_oid" ]]
[[ $(git -C "$partial_home/j3w1zsh" rev-parse --is-shallow-repository) == false ]]
partial_refs_before="$(git -C "$partial_home/j3w1zsh" show-ref)"
partial_update_json="$(env HOME="$partial_home" XDG_CONFIG_HOME="$partial_home/.config" XDG_STATE_HOME="$partial_home/.local/state" \
  XDG_CACHE_HOME="$partial_home/.cache" J3W1ZSH_TEST_MODE=1 J3W1ZSH_TEST_PLATFORM=wsl \
  J3W1ZSH_TEST_CANONICAL_URL="$new_remote" "$partial_home/j3w1zsh/bin/j3w1zsh" update --dry-run --json)"
jq -e --arg current "$new_oid" --arg upstream "$new_main_oid" \
  '.status == "ok" and .data.dry_run == true and .data.local_refs_changed == false and
   .data.repository.tracking_ref == "origin/main" and .data.tracking_relation.local_oid == $current and
   .data.tracking_relation.remote_oid == $upstream and .data.tracking_relation.ahead == 0 and .data.tracking_relation.behind == 1' \
  <<<"$partial_update_json" >/dev/null
[[ $(git -C "$partial_home/j3w1zsh" show-ref) == "$partial_refs_before" ]]
recovery="$(find "$partial_home/.local/state/j3w1zsh/migrations" -mindepth 1 -maxdepth 1 -type d | head -n1)"
jq -e '.phase == "finalize" and .status == "complete"' "$recovery/journal.json" >/dev/null
jq -e '.classification == "exact-known" and .installation_state == "partial" and .git.staged == false and .git.untracked == false and (.git.source_commit | length == 40) and any(.plausible_sources[]; .path == $source and .git_checkout == true)' \
  --arg source "$partial_home/projects/bloody-writer" "$recovery/inventory.json" >/dev/null
[[ -f $recovery/pre-cutover/zshrc && -f $recovery/pre-cutover/tmux.conf ]]
[[ ! -e $recovery/pre-cutover/clipboard-helper ]]
env HOME="$partial_home" XDG_STATE_HOME="$partial_home/.local/state" "$partial_home/j3w1zsh/scripts/legacy/migrate-to-j3w1zsh.sh" --status | jq -e '.status == "complete"' >/dev/null

# Rollback is rerunnable-safe, restores old locations, and deliberately preserves the new checkout.
env HOME="$partial_home" XDG_STATE_HOME="$partial_home/.local/state" "$partial_home/j3w1zsh/scripts/legacy/migrate-to-j3w1zsh.sh" --rollback >/dev/null
[[ -d $partial_home/projects/bloody-writer/.git ]]
[[ -L $partial_home/.local/bin/bloody-writer ]]
[[ -f $partial_home/.zshrc && ! -L $partial_home/.zshrc ]]
[[ -d $partial_home/j3w1zsh/.git ]]
jq -e '.status == "complete"' "$recovery/rollback.json" >/dev/null
rm -- "$recovery/rollback.json"
env HOME="$partial_home" XDG_STATE_HOME="$partial_home/.local/state" "$partial_home/j3w1zsh/scripts/legacy/migrate-to-j3w1zsh.sh" --rollback >/dev/null
[[ -d $partial_home/projects/bloody-writer/.git && -f $partial_home/.zshrc && ! -L $partial_home/.zshrc ]]
env HOME="$partial_home" XDG_STATE_HOME="$partial_home/.local/state" "$partial_home/j3w1zsh/scripts/legacy/migrate-to-j3w1zsh.sh" --rollback |
  grep -q 'Rollback is already complete'

# A complete former installation preserves XDG state and produces an unapproved v2 workspace candidate.
complete_home="$test_root/complete-home"
create_old_home "$complete_home"
complete_source="$complete_home/projects/bloody-writer"
rm -- "$complete_home/.zshrc" "$complete_home/.tmux.conf"
rm -r -- "$complete_home/.config/nvim"
ln -s "$complete_source/README.md" "$complete_home/.zshrc"
ln -s "$complete_source/README.md" "$complete_home/.tmux.conf"
ln -s "$complete_source/dotfiles/nvim/.config/nvim" "$complete_home/.config/nvim"
ln -s "$complete_source/bin/bloody-writer" "$complete_home/.local/bin/bw-clipboard-copy"
mkdir -p "$complete_home/.config/bloody-writer" "$complete_home/.local/state/bloody-writer/phases" \
  "$complete_home/.local/state/bloody-writer/workspaces" "$complete_home/.cache/bloody-writer"
printf "export BLOODY_WRITER_DOCUMENTS='%s/Documents'\n" "$complete_home" >"$complete_home/.config/bloody-writer/settings.zsh"
printf '{"complete":true}\n' >"$complete_home/.local/state/bloody-writer/phases/40-dotfiles.json"
printf 'legacy cache bytes\n' >"$complete_home/.cache/bloody-writer/cache.txt"
legacy_workspace="$complete_home/legacy-workspace.json"
write_legacy_workspace "$legacy_workspace"
jq -n --arg manifest "$legacy_workspace" '{manifest:$manifest}' >"$complete_home/.local/state/bloody-writer/workspaces/active.json"
run_migration "$complete_home" --target-ref "$new_oid" --expected-commit "$new_oid" --source "$complete_source" >/dev/null
complete_recovery="$(find "$complete_home/.local/state/j3w1zsh/migrations" -mindepth 1 -maxdepth 1 -type d | head -n1)"
jq -e '.installation_state == "complete"' "$complete_recovery/inventory.json" >/dev/null
[[ -f $complete_recovery/pre-cutover/old-state/phases/40-dotfiles.json ]]
[[ -f $complete_recovery/pre-cutover/old-cache/cache.txt ]]
jq -e '.schema_version == 2 and .workspace.review_state == "candidate" and (.targets | keys == ["wsl"])' \
  "$complete_recovery/workspace/j3w1zsh.workspace.json" >/dev/null
[[ -f $complete_recovery/workspace/j3w1zsh.workspace.json.migration-report.json ]]

# Unknown settings stop after acquisition, remain inert, and resume only after explicit approval.
resume_home="$test_root/resume-home"
create_old_home "$resume_home"
mkdir -p "$resume_home/.config/bloody-writer"
mkdir -p "$resume_home/.local/state/bloody-writer/workspaces"
resume_legacy_workspace="$resume_home/legacy-workspace.json"
write_legacy_workspace "$resume_legacy_workspace"
jq -n --arg manifest "$resume_legacy_workspace" '{manifest:$manifest}' >"$resume_home/.local/state/bloody-writer/workspaces/active.json"
cat >"$resume_home/.config/bloody-writer/settings.zsh" <<'EOF'
export BLOODY_WRITER_DOCUMENTS='/tmp/example-documents'
export UNKNOWN_FORMER_SETTING='preserve but never source me'
EOF
set +e
run_migration "$resume_home" --target-ref "$new_oid" --expected-commit "$new_oid" --source "$resume_home/projects/bloody-writer" >/dev/null 2>&1
resume_result=$?
set -e
[[ $resume_result == 20 ]]
resume_recovery="$(find "$resume_home/.local/state/j3w1zsh/migrations" -mindepth 1 -maxdepth 1 -type d | head -n1)"
jq -e '.phase == "translate" and .status == "checkpoint"' "$resume_recovery/journal.json" >/dev/null
grep -q UNKNOWN_FORMER_SETTING "$resume_recovery/unknown-settings.txt"
[[ -d $resume_home/j3w1zsh/.git && -d $resume_home/projects/bloody-writer/.git ]]
mkdir -p "$resume_recovery/workspace"
env HOME="$resume_home" XDG_STATE_HOME="$resume_home/.local/state" J3W1ZSH_TEST_MODE=1 J3W1ZSH_TEST_PLATFORM=wsl \
  "$resume_home/j3w1zsh/bin/j3w1zsh" workspace migrate "$resume_legacy_workspace" \
  --output "$resume_recovery/workspace/j3w1zsh.workspace.json" >/dev/null

# The interrupted-workspace comparison directory is the other script-created temporary directory.
# Make its generated comparison files write-protected and prove guarded cleanup removes only it.
workspace_instrumented_bin="$test_root/workspace-instrumented-bin"
workspace_protect_log="$test_root/workspace-write-protected.log"
mkdir -p "$workspace_instrumented_bin"
cat >"$workspace_instrumented_bin/mv" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

: "${J3W1ZSH_TEST_REAL_MV:?}"
set +e
"$J3W1ZSH_TEST_REAL_MV" "$@"
result=$?
set -e
destination=''
for argument in "$@"; do
  destination="$argument"
done
if ((result == 0)) && [[ $destination == */.workspace-compare.??????/* && -f $destination ]]; then
  chmod a-w -- "$destination"
  printf '%s\n' "$destination" >>"$J3W1ZSH_TEST_WRITE_PROTECT_LOG"
fi
exit "$result"
EOF
chmod +x "$workspace_instrumented_bin/mv"
touch "$resume_recovery/translation-approved"
J3W1ZSH_TEST_REAL_MV="$(command -v mv)" J3W1ZSH_TEST_WRITE_PROTECT_LOG="$workspace_protect_log" \
  PATH="$workspace_instrumented_bin:$PATH" run_migration "$resume_home" --resume >/dev/null
jq -e '.phase == "finalize" and .status == "complete"' "$resume_recovery/journal.json" >/dev/null
[[ ! -e $resume_home/projects/bloody-writer ]]
[[ $(wc -l <"$workspace_protect_log") == 2 ]]
[[ -z $(find "$resume_recovery" -mindepth 1 -maxdepth 1 -name '.workspace-compare.*' -print -quit) ]]

# Repeating the exact completed invocation is a no-op and creates no new recovery generation.
recovery_count_before="$(find "$resume_home/.local/state/j3w1zsh/migrations" -mindepth 1 -maxdepth 1 -type d | wc -l)"
run_migration "$resume_home" --target-ref "$new_oid" --expected-commit "$new_oid" --source "$resume_home/projects/bloody-writer" |
  grep -q 'Migration is already complete'
recovery_count_after="$(find "$resume_home/.local/state/j3w1zsh/migrations" -mindepth 1 -maxdepth 1 -type d | wc -l)"
[[ $recovery_count_before == "$recovery_count_after" ]]
run_migration "$resume_home" --resume | grep -q 'Migration is already complete'

# Native Termux migration translates only known settings and never requires privilege.
termux_home="$test_root/termux-home"
create_old_home "$termux_home"
mkdir -p "$termux_home/.config/bloody-writer"
cat >"$termux_home/.config/bloody-writer/settings.zsh" <<'EOF'
export BLOODY_WRITER_DOCUMENTS='/data/data/com.termux/files/home/storage/shared/Documents'
export BLOODY_WRITER_WSL_HOST='100.64.0.2'
export BLOODY_WRITER_WSL_USER='legacy-user'
export BLOODY_WRITER_WSL_TMA='/home/legacy-user/.local/bin/tma'
EOF
run_termux_migration "$termux_home" --target-ref "$new_oid" --expected-commit "$new_oid" --source "$termux_home/projects/bloody-writer" >/dev/null
grep -q '^export J3W1ZSH_EDIT_ROOT=' "$termux_home/.config/j3w1zsh/settings.zsh"
grep -q '^export J3W1ZSH_REMOTE_HOST=' "$termux_home/.config/j3w1zsh/settings.zsh"
grep -q '^export J3W1ZSH_REMOTE_USER=' "$termux_home/.config/j3w1zsh/settings.zsh"
grep -q '^export J3W1ZSH_REMOTE_ATTACH_COMMAND=' "$termux_home/.config/j3w1zsh/settings.zsh"
env HOME="$termux_home" XDG_CONFIG_HOME="$termux_home/.config" XDG_STATE_HOME="$termux_home/.local/state" \
  J3W1ZSH_TEST_MODE=1 J3W1ZSH_TEST_PLATFORM=termux "$termux_home/j3w1zsh/bin/j3w1zsh" platform --json |
  jq -e '.data.id == "termux"' >/dev/null
[[ $(git -C "$termux_home/j3w1zsh" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}') == origin/main ]]
[[ $(git -C "$termux_home/j3w1zsh" rev-parse --verify refs/remotes/origin/main) == "$new_main_oid" ]]
[[ $(git -C "$termux_home/j3w1zsh" rev-parse --is-shallow-repository) == false ]]

# Reproduce the first real WSL result exactly: clean local main at the exact candidate, branch
# configuration pointing to origin/main, a shallow object store, and no remote-tracking ref.
tracking_home="$test_root/tracking-home"
tracking_target="$tracking_home/j3w1zsh"
tracking_tmp="$test_root/tracking-tmp"
mkdir -p "$tracking_target" "$tracking_tmp" "$tracking_home/.config/j3w1zsh" \
  "$tracking_home/.local/state/j3w1zsh/phases" "$tracking_home/.local/state/j3w1zsh/packages" \
  "$tracking_home/.local/state/j3w1zsh/migrations/recovery-one" \
  "$tracking_home/.local/state/j3w1zsh/migrations/recovery-two"
git -C "$tracking_target" init -q
git -C "$tracking_target" remote add origin "$new_remote"
git -C "$tracking_target" fetch -q --depth=1 origin "$new_oid"
git -C "$tracking_target" checkout -q -B main FETCH_HEAD
git -C "$tracking_target" config branch.main.remote origin
git -C "$tracking_target" config branch.main.merge refs/heads/main
printf '{"schema_version":1,"additions":{},"exclusions":{}}\n' >"$tracking_home/.config/j3w1zsh/packages.json"
printf '{"fixture":"package-ledger"}\n' >"$tracking_home/.local/state/j3w1zsh/packages/ledger.json"
printf 'preserve first recovery\n' >"$tracking_home/.local/state/j3w1zsh/migrations/recovery-one/sentinel"
printf 'preserve completed recovery\n' >"$tracking_home/.local/state/j3w1zsh/migrations/recovery-two/sentinel"
jq -n '{preset:"j3w1",preset_source:"j3w1",theme:"j3w1zsh",theme_source:"j3w1zsh",no_packages:true,packages_only:false}' \
  >"$tracking_home/.local/state/j3w1zsh/phases/00-preflight.json"
[[ $(git -C "$tracking_target" rev-parse HEAD) == "$new_oid" ]]
[[ $(git -C "$tracking_target" rev-parse --is-shallow-repository) == true ]]
[[ -z $(git -C "$tracking_target" rev-parse --verify refs/remotes/origin/main 2>/dev/null || true) ]]
grep -q '\[gone\]' < <(git -C "$tracking_target" status --short --branch)

tracking_head_before="$(git -C "$tracking_target" rev-parse HEAD)"
tracking_tree_before="$(git -C "$tracking_target" rev-parse 'HEAD^{tree}')"
tracking_config_before="$(git -C "$tracking_target" config --local --null --list | sha256sum | awk '{print $1}')"
tracking_refs_before="$(git -C "$tracking_target" for-each-ref --format='%(refname) %(objectname)')"
tracking_user_state_before="$(find "$tracking_home/.config/j3w1zsh" "$tracking_home/.local/state/j3w1zsh" -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum | awk '{print $1}')"

set +e
tracking_update_before="$(env HOME="$tracking_home" XDG_CONFIG_HOME="$tracking_home/.config" XDG_STATE_HOME="$tracking_home/.local/state" \
  XDG_CACHE_HOME="$tracking_home/.cache" J3W1ZSH_TEST_MODE=1 J3W1ZSH_TEST_PLATFORM=wsl \
  J3W1ZSH_TEST_CANONICAL_URL="$new_remote" PATH="$fixture_bin:$PATH" "$tracking_target/bin/j3w1zsh" update --dry-run --json 2>&1)"
tracking_update_before_result=$?
set -e
[[ $tracking_update_before_result == 21 ]]
jq -e '.status == "error" and .error.code == "missing_upstream"' <<<"$tracking_update_before" >/dev/null
[[ $(git -C "$tracking_target" for-each-ref --format='%(refname) %(objectname)') == "$tracking_refs_before" ]]

set +e
tracking_doctor_before="$(env HOME="$tracking_home" XDG_CONFIG_HOME="$tracking_home/.config" XDG_STATE_HOME="$tracking_home/.local/state" \
  XDG_CACHE_HOME="$tracking_home/.cache" J3W1ZSH_TEST_MODE=1 J3W1ZSH_TEST_PLATFORM=wsl \
  J3W1ZSH_TEST_REAL_GIT="$real_git" J3W1ZSH_TEST_DOCTOR_NETWORK_LOG="$doctor_network_log" PATH="$doctor_git_bin:$fixture_bin:$PATH" \
  "$tracking_target/bin/j3w1zsh" doctor --json)"
tracking_doctor_before_result=$?
set -e
[[ $tracking_doctor_before_result == 1 ]]
jq -e '.status == "error" and any(.data.checks[]; .name == "git-upstream" and .ok == false)' <<<"$tracking_doctor_before" >/dev/null
[[ ! -e $doctor_network_log ]]

tracking_protect_log="$test_root/tracking-write-protected.log"
tracking_dry_output="$test_root/tracking-repair-dry.out"
timeout 20s env HOME="$tracking_home" XDG_CONFIG_HOME="$tracking_home/.config" XDG_STATE_HOME="$tracking_home/.local/state" \
  XDG_CACHE_HOME="$tracking_home/.cache" TMPDIR="$tracking_tmp" J3W1ZSH_MIGRATION_TEST_MODE=1 \
  J3W1ZSH_MIGRATION_REMOTE="$new_remote" J3W1ZSH_TEST_REAL_GIT="$real_git" J3W1ZSH_TEST_WRITE_PROTECT_FETCH=1 \
  J3W1ZSH_TEST_WRITE_PROTECT_LOG="$tracking_protect_log" PATH="$instrumented_bin:$fixture_bin:$PATH" \
  "$tracking_target/scripts/legacy/migrate-to-j3w1zsh.sh" --repair-tracking --target "$tracking_target" \
  --expected-commit "$new_oid" --expected-upstream-commit "$new_main_oid" --dry-run </dev/null >"$tracking_dry_output"
grep -q 'origin/main: missing' "$tracking_dry_output"
grep -q 'local refs, recovery data, packages, and user configuration were unchanged' "$tracking_dry_output"
if grep -q 'remove write-protected' "$tracking_dry_output"; then
  printf 'Tracking-repair cleanup prompted for write-protected Git objects.\n' >&2
  exit 1
fi
awk 'NF != 2 || $1 < 1 { exit 1 } END { if (NR != 1) exit 1 }' "$tracking_protect_log"
[[ -z $(find "$tracking_tmp" -mindepth 1 -maxdepth 1 -name 'j3w1zsh-migration-tracking.*' -print -quit) ]]
[[ $(git -C "$tracking_target" rev-parse HEAD) == "$tracking_head_before" ]]
[[ $(git -C "$tracking_target" rev-parse 'HEAD^{tree}') == "$tracking_tree_before" ]]
[[ $(git -C "$tracking_target" config --local --null --list | sha256sum | awk '{print $1}') == "$tracking_config_before" ]]
[[ $(git -C "$tracking_target" for-each-ref --format='%(refname) %(objectname)') == "$tracking_refs_before" ]]
[[ $(find "$tracking_home/.config/j3w1zsh" "$tracking_home/.local/state/j3w1zsh" -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum | awk '{print $1}') == "$tracking_user_state_before" ]]

env HOME="$tracking_home" XDG_CONFIG_HOME="$tracking_home/.config" XDG_STATE_HOME="$tracking_home/.local/state" \
  XDG_CACHE_HOME="$tracking_home/.cache" J3W1ZSH_MIGRATION_TEST_MODE=1 J3W1ZSH_MIGRATION_REMOTE="$new_remote" \
  PATH="$fixture_bin:$PATH" "$tracking_target/scripts/legacy/migrate-to-j3w1zsh.sh" --repair-tracking \
  --target "$tracking_target" --expected-commit "$new_oid" --expected-upstream-commit "$new_main_oid" >/dev/null
[[ $(git -C "$tracking_target" rev-parse HEAD) == "$tracking_head_before" ]]
[[ $(git -C "$tracking_target" rev-parse 'HEAD^{tree}') == "$tracking_tree_before" ]]
[[ $(git -C "$tracking_target" config --local --null --list | sha256sum | awk '{print $1}') == "$tracking_config_before" ]]
[[ $(find "$tracking_home/.config/j3w1zsh" "$tracking_home/.local/state/j3w1zsh" -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum | awk '{print $1}') == "$tracking_user_state_before" ]]
[[ $(git -C "$tracking_target" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}') == origin/main ]]
[[ $(git -C "$tracking_target" rev-parse '@{upstream}') == "$new_main_oid" ]]
[[ $(git -C "$tracking_target" rev-parse --verify refs/remotes/origin/main) == "$new_main_oid" ]]
[[ $(git -C "$tracking_target" rev-parse --is-shallow-repository) == false ]]
if git -C "$tracking_target" status --short --branch | grep -q '\[gone\]'; then
  printf 'Tracking repair left origin/main unresolved.\n' >&2
  exit 1
fi

tracking_refs_repaired="$(git -C "$tracking_target" show-ref)"
tracking_state_repaired="$(find "$tracking_home/.config/j3w1zsh" "$tracking_home/.local/state/j3w1zsh" -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum | awk '{print $1}')"
tracking_update_human="$(env HOME="$tracking_home" XDG_CONFIG_HOME="$tracking_home/.config" XDG_STATE_HOME="$tracking_home/.local/state" \
  XDG_CACHE_HOME="$tracking_home/.cache" J3W1ZSH_TEST_MODE=1 J3W1ZSH_TEST_PLATFORM=wsl \
  J3W1ZSH_TEST_CANONICAL_URL="$new_remote" PATH="$fixture_bin:$PATH" "$tracking_target/bin/j3w1zsh" update --dry-run)"
grep -q 'Branch/upstream: main -> origin/main' <<<"$tracking_update_human"
[[ $(git -C "$tracking_target" show-ref) == "$tracking_refs_repaired" ]]
tracking_update_json="$(env HOME="$tracking_home" XDG_CONFIG_HOME="$tracking_home/.config" XDG_STATE_HOME="$tracking_home/.local/state" \
  XDG_CACHE_HOME="$tracking_home/.cache" J3W1ZSH_TEST_MODE=1 J3W1ZSH_TEST_PLATFORM=wsl \
  J3W1ZSH_TEST_CANONICAL_URL="$new_remote" PATH="$fixture_bin:$PATH" "$tracking_target/bin/j3w1zsh" update --dry-run --json)"
jq -e --arg current "$new_oid" --arg upstream "$new_main_oid" \
  '.status == "ok" and .data.dry_run == true and .data.local_refs_changed == false and
   .data.tracking_relation.local_oid == $current and .data.tracking_relation.remote_oid == $upstream and
   .data.tracking_relation.ahead == 0 and .data.tracking_relation.behind == 1' <<<"$tracking_update_json" >/dev/null
[[ $(git -C "$tracking_target" show-ref) == "$tracking_refs_repaired" ]]
[[ $(find "$tracking_home/.config/j3w1zsh" "$tracking_home/.local/state/j3w1zsh" -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum | awk '{print $1}') == "$tracking_state_repaired" ]]

env HOME="$tracking_home" XDG_CONFIG_HOME="$tracking_home/.config" XDG_STATE_HOME="$tracking_home/.local/state" \
  XDG_CACHE_HOME="$tracking_home/.cache" J3W1ZSH_TEST_MODE=1 J3W1ZSH_TEST_PLATFORM=wsl \
  J3W1ZSH_TEST_CANONICAL_URL="$new_remote" PATH="$fixture_bin:$PATH" "$tracking_target/bin/j3w1zsh" update --yes >/dev/null
[[ $(git -C "$tracking_target" rev-parse HEAD) == "$new_main_oid" ]]
[[ -f $tracking_target/tracking-advanced-marker.txt ]]
if git -C "$tracking_target" status --short --branch | grep -q '\[gone\]'; then
  printf 'Normal fast-forward update left origin/main unresolved.\n' >&2
  exit 1
fi
env HOME="$tracking_home" XDG_CONFIG_HOME="$tracking_home/.config" XDG_STATE_HOME="$tracking_home/.local/state" \
  XDG_CACHE_HOME="$tracking_home/.cache" J3W1ZSH_TEST_MODE=1 J3W1ZSH_TEST_PLATFORM=wsl \
  J3W1ZSH_TEST_REAL_GIT="$real_git" J3W1ZSH_TEST_DOCTOR_NETWORK_LOG="$doctor_network_log" PATH="$doctor_git_bin:$fixture_bin:$PATH" \
  "$tracking_target/bin/j3w1zsh" doctor --json | jq -e '.status == "ok" and any(.data.checks[]; .name == "git-upstream" and .ok == true)' >/dev/null
[[ ! -e $doctor_network_log ]]

# A clean unique/divergent local commit is never converted into canonical tracking history.
protected_tracking="$tracking_home/protected-tracking"
mkdir -p "$protected_tracking"
git -C "$protected_tracking" init -q
git -C "$protected_tracking" remote add origin "$new_remote"
git -C "$protected_tracking" fetch -q --depth=1 origin "$new_oid"
git -C "$protected_tracking" checkout -q -B main FETCH_HEAD
git -C "$protected_tracking" config branch.main.remote origin
git -C "$protected_tracking" config branch.main.merge refs/heads/main
git -C "$protected_tracking" config user.name 'Migration Tests'
git -C "$protected_tracking" config user.email 'tests@example.invalid'
printf 'unique local history\n' >"$protected_tracking/unique.txt"
git -C "$protected_tracking" add unique.txt
git -C "$protected_tracking" commit -q -m 'fixture: unique tracking history'
protected_tracking_head="$(git -C "$protected_tracking" rev-parse HEAD)"
protected_tracking_refs="$(git -C "$protected_tracking" show-ref)"
set +e
env HOME="$tracking_home" J3W1ZSH_MIGRATION_TEST_MODE=1 J3W1ZSH_MIGRATION_REMOTE="$new_remote" \
  "$protected_tracking/scripts/legacy/migrate-to-j3w1zsh.sh" --repair-tracking --target "$protected_tracking" \
  --expected-commit "$protected_tracking_head" --expected-upstream-commit "$new_main_oid" >/dev/null 2>&1
protected_tracking_result=$?
set -e
[[ $protected_tracking_result == 21 ]]
[[ $(git -C "$protected_tracking" rev-parse HEAD) == "$protected_tracking_head" ]]
[[ $(git -C "$protected_tracking" show-ref) == "$protected_tracking_refs" ]]
[[ -z $(git -C "$protected_tracking" rev-parse --verify refs/remotes/origin/main 2>/dev/null || true) ]]

assert_protected() {
  local kind="$1"
  local fixture_home="$test_root/protected-$kind"
  create_old_home "$fixture_home"
  local source="$fixture_home/projects/bloody-writer"
  case "$kind" in
  dirty) printf 'authored dirty\n' >>"$source/README.md" ;;
  staged) printf 'staged bytes\n' >>"$source/README.md"; git -C "$source" add README.md ;;
  untracked) mkdir -p "$source/private"; printf 'untracked recovery bytes\n' >"$source/private/local.txt" ;;
  unique)
    printf 'unique commit\n' >"$source/unique.txt"
    git -C "$source" add unique.txt
    git -C "$source" -c user.name='Migration Tests' -c user.email='tests@example.invalid' commit -q -m 'fixture: unique local commit'
    ;;
  esac
  set +e
  run_migration "$fixture_home" --target-ref "$new_oid" --expected-commit "$new_oid" --source "$source" >/dev/null 2>&1
  result=$?
  set -e
  [[ $result == 21 ]] || { printf 'Protected fixture %s exited %s instead of 21.\n' "$kind" "$result" >&2; exit 1; }
  [[ ! -e $fixture_home/j3w1zsh ]]
  local protected_recovery
  protected_recovery="$(find "$fixture_home/.local/state/j3w1zsh/migrations" -mindepth 1 -maxdepth 1 -type d | head -n1)"
  jq -e --arg classification "$(case "$kind" in dirty) printf authored-dirty ;; staged) printf staged ;; untracked) printf untracked ;; unique) printf local-commit ;; esac)" '.classification == $classification' "$protected_recovery/inventory.json" >/dev/null
  jq -e '.status == "protected-stop"' "$protected_recovery/journal.json" >/dev/null
  case "$kind" in
  dirty) [[ -s $protected_recovery/tracked-worktree.patch ]] ;;
  staged) [[ -s $protected_recovery/tracked-index.patch ]] ;;
  untracked) cmp -s "$source/private/local.txt" "$protected_recovery/untracked/private/local.txt" ;;
  unique) git bundle verify "$protected_recovery/unique-refs.bundle" >/dev/null ;;
  esac
}

assert_protected dirty
assert_protected staged
assert_protected untracked
assert_protected unique

# Diverged local and remote histories remain classified as divergent, not merely local-commit.
divergent_remote="$test_root/divergent-former.git"
git clone -q --bare "$old_seed" "$divergent_remote"
divergent_home="$test_root/protected-divergent"
mkdir -p "$divergent_home/projects" "$divergent_home/.local/bin" "$divergent_home/.config/nvim"
git clone -q "$divergent_remote" "$divergent_home/projects/bloody-writer"
divergent_source="$divergent_home/projects/bloody-writer"
ln -s "$divergent_source/bin/bloody-writer" "$divergent_home/.local/bin/bloody-writer"
printf '# regular zshrc\n' >"$divergent_home/.zshrc"
printf '# regular tmux\n' >"$divergent_home/.tmux.conf"
printf 'regular nvim\n' >"$divergent_home/.config/nvim/init.lua"
divergent_peer="$test_root/divergent-peer"
git clone -q "$divergent_remote" "$divergent_peer"
printf 'remote side\n' >"$divergent_peer/remote.txt"
git -C "$divergent_peer" add remote.txt
git -C "$divergent_peer" -c user.name='Migration Tests' -c user.email='tests@example.invalid' commit -q -m 'fixture: remote side'
git -C "$divergent_peer" push -q origin main
printf 'local side\n' >"$divergent_source/local.txt"
git -C "$divergent_source" add local.txt
git -C "$divergent_source" -c user.name='Migration Tests' -c user.email='tests@example.invalid' commit -q -m 'fixture: local side'
git -C "$divergent_source" fetch -q origin
printf 'combined divergent and untracked bytes\n' >"$divergent_source/untracked.txt"
set +e
env HOME="$divergent_home" XDG_CONFIG_HOME="$divergent_home/.config" XDG_STATE_HOME="$divergent_home/.local/state" \
  XDG_CACHE_HOME="$divergent_home/.cache" J3W1ZSH_MIGRATION_TEST_MODE=1 J3W1ZSH_MIGRATION_TEST_PLATFORM=wsl \
  J3W1ZSH_MIGRATION_REMOTE="$new_remote" J3W1ZSH_MIGRATION_TEST_FORMER_REMOTE="$divergent_remote" \
  PATH="$fixture_bin:$PATH" "$migration" --target-ref "$new_oid" --expected-commit "$new_oid" \
  --source "$divergent_source" >/dev/null 2>&1
divergent_result=$?
set -e
[[ $divergent_result == 21 ]]
divergent_recovery="$(find "$divergent_home/.local/state/j3w1zsh/migrations" -mindepth 1 -maxdepth 1 -type d | head -n1)"
jq -e '.classification == "divergent" and .git.unique_commits == true' "$divergent_recovery/inventory.json" >/dev/null
grep -q 'combined divergent' "$divergent_recovery/untracked/untracked.txt"
git bundle verify "$divergent_recovery/unique-refs.bundle" >/dev/null

# Exact allowlisted generated lock drift is byte-preserved and may continue.
generated_home="$test_root/generated-home"
create_old_home "$generated_home"
printf '{"generated":true}\n' >"$generated_home/projects/bloody-writer/dotfiles/nvim/.config/nvim/lazy-lock.json"
run_migration "$generated_home" --target-ref "$new_oid" --expected-commit "$new_oid" --source "$generated_home/projects/bloody-writer" >/dev/null
generated_recovery="$(find "$generated_home/.local/state/j3w1zsh/migrations" -mindepth 1 -maxdepth 1 -type d | head -n1)"
jq -e '.classification == "generated-drift" and .git.generated_only == true' "$generated_recovery/inventory.json" >/dev/null
grep -q generated "$generated_recovery/tracked-worktree.patch"

printf 'Legacy dry-run, complete/partial migration, resume/rerun, protected recovery, generated repair, and rollback tests passed.\n'
