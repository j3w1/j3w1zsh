#!/usr/bin/env bash
set -Eeuo pipefail

readonly MIGRATION_EXIT_FAILURE=1
readonly MIGRATION_EXIT_USAGE=2
readonly MIGRATION_EXIT_CHECKPOINT=20
readonly MIGRATION_EXIT_PROTECTED=21
readonly MIGRATION_KNOWN_GENERATED_PATH='dotfiles/nvim/.config/nvim/lazy-lock.json'
declare -A MIGRATION_EPHEMERAL_KINDS=()

migration_usage() {
  cat <<'EOF'
Usage:
  migrate-to-j3w1zsh.sh --target-ref REF --expected-commit 40_HEX_OID [--source PATH] [--dry-run]
  migrate-to-j3w1zsh.sh --repair-tracking --expected-commit CURRENT_40_HEX_OID \
    --expected-upstream-commit UPSTREAM_40_HEX_OID [--target PATH] [--dry-run]
  migrate-to-j3w1zsh.sh --resume
  migrate-to-j3w1zsh.sh --rollback
  migrate-to-j3w1zsh.sh --status

The target ref is mandatory for a new migration and is never defaulted to main.
The resolved target must equal --expected-commit before checkout or cutover.
EOF
}

migration_die() {
  printf 'ERROR: %s\n' "$1" >&2
  exit "${2:-$MIGRATION_EXIT_FAILURE}"
}

migration_note() {
  printf '    %s\n' "$*"
}

migration_log() {
  printf '==> %s\n' "$*"
}

migration_ephemeral_parent() {
  case "$1" in
  resolve)
    printf '%s\n' "${TMPDIR:-/tmp}"
    ;;
  workspace-compare)
    [[ -n ${MIGRATION_RECOVERY_ROOT:-} ]] || return 1
    printf '%s\n' "$MIGRATION_RECOVERY_ROOT"
    ;;
  tracking-compare)
    printf '%s\n' "${TMPDIR:-/tmp}"
    ;;
  *)
    return 1
    ;;
  esac
}

migration_ephemeral_basename_allowed() {
  local kind="$1" name="$2"
  case "$kind:$name" in
  resolve:j3w1zsh-migration-resolve.?????? | workspace-compare:.workspace-compare.?????? | \
    tracking-compare:j3w1zsh-migration-tracking.??????) return 0 ;;
  *) return 1 ;;
  esac
}

migration_create_ephemeral_dir() {
  local output_name="$1" kind="$2" parent resolved_parent prefix created resolved_created marker
  parent="$(migration_ephemeral_parent "$kind")" || migration_die "Unknown ephemeral directory kind: $kind"
  [[ -d $parent ]] || migration_die "Ephemeral directory parent is not available: $parent"
  resolved_parent="$(readlink -m -- "$parent")"
  if [[ $kind == workspace-compare ]]; then
    migration_validate_home_path "$resolved_parent"
  fi
  case "$kind" in
  resolve) prefix='j3w1zsh-migration-resolve' ;;
  workspace-compare) prefix='.workspace-compare' ;;
  tracking-compare) prefix='j3w1zsh-migration-tracking' ;;
  esac
  created="$(mktemp -d -- "$resolved_parent/$prefix.XXXXXX")"
  resolved_created="$(readlink -m -- "$created")"
  [[ -d $resolved_created && ! -L $resolved_created ]] || migration_die "Ephemeral directory creation was not isolated: $created"
  [[ $(dirname -- "$resolved_created") == "$resolved_parent" ]] || migration_die "Ephemeral directory escaped its guarded parent: $created"
  migration_ephemeral_basename_allowed "$kind" "$(basename -- "$resolved_created")" ||
    migration_die "Ephemeral directory has an unexpected name: $created"
  marker="$resolved_created/.j3w1zsh-ephemeral"
  (umask 077; printf 'j3w1zsh:%s\n' "$kind" >"$marker")
  chmod 400 "$marker"
  MIGRATION_EPHEMERAL_KINDS["$resolved_created"]="$kind"
  printf -v "$output_name" '%s' "$resolved_created"
}

migration_cleanup_ephemeral_dir() {
  local path="$1" kind parent resolved_parent resolved_path marker marker_value
  if [[ ${MIGRATION_EPHEMERAL_KINDS[$path]+registered} != registered ]]; then
    printf 'ERROR: Refusing to remove an unregistered ephemeral directory: %s\n' "$path" >&2
    return 1
  fi
  kind="${MIGRATION_EPHEMERAL_KINDS[$path]}"
  parent="$(migration_ephemeral_parent "$kind")" || return 1
  resolved_parent="$(readlink -m -- "$parent")"
  resolved_path="$(readlink -m -- "$path")"
  if [[ $path != "$resolved_path" || ! -d $path || -L $path || $(dirname -- "$resolved_path") != "$resolved_parent" ]] ||
    ! migration_ephemeral_basename_allowed "$kind" "$(basename -- "$resolved_path")"; then
    printf 'ERROR: Refusing to remove an ephemeral directory outside its exact guarded shape: %s\n' "$path" >&2
    return 1
  fi
  marker="$path/.j3w1zsh-ephemeral"
  if [[ ! -f $marker || -L $marker ]]; then
    printf 'ERROR: Refusing to remove an ephemeral directory without its regular ownership marker: %s\n' "$path" >&2
    return 1
  fi
  IFS= read -r marker_value <"$marker" || return 1
  if [[ $marker_value != "j3w1zsh:$kind" ]]; then
    printf 'ERROR: Refusing to remove an ephemeral directory with an invalid ownership marker: %s\n' "$path" >&2
    return 1
  fi
  rm -rf -- "$path"
  [[ ! -e $path && ! -L $path ]] || return 1
  unset 'MIGRATION_EPHEMERAL_KINDS[$path]'
}

migration_cleanup_ephemeral_dirs_on_exit() {
  local status=$? path cleanup_failed=0
  trap - EXIT
  for path in "${!MIGRATION_EPHEMERAL_KINDS[@]}"; do
    migration_cleanup_ephemeral_dir "$path" || cleanup_failed=1
  done
  if ((status == 0 && cleanup_failed != 0)); then
    status=$MIGRATION_EXIT_FAILURE
  fi
  exit "$status"
}

trap migration_cleanup_ephemeral_dirs_on_exit EXIT

migration_validate_home_path() {
  local path="$1" resolved_home resolved_path
  resolved_home="$(readlink -m -- "$HOME")"
  resolved_path="$(readlink -m -- "$path")"
  case "$resolved_path" in
  "$resolved_home" | "$resolved_home"/*) ;;
  *) migration_die "Path escapes HOME through an ancestor or symlink: $path" ;;
  esac
}

migration_remote_main_oid() {
  local advertised count oid
  advertised="$(git ls-remote --refs "$MIGRATION_REMOTE" refs/heads/main)" ||
    migration_die "Canonical main is unreachable."
  count="$(awk 'NF == 2 { count += 1 } END { print count + 0 }' <<<"$advertised")"
  [[ $count == 1 ]] || migration_die "Canonical main did not resolve to exactly one ref."
  oid="$(awk 'NF == 2 { print $1 }' <<<"$advertised")"
  [[ $oid =~ ^[0-9a-f]{40}$ ]] || migration_die "Canonical main did not resolve to a full commit OID."
  printf '%s\n' "$oid"
}

migration_remote_contains_commit() {
  local current_oid="$1" upstream_oid="$2" comparison
  migration_create_ephemeral_dir comparison tracking-compare
  if ! git -C "$comparison" init -q ||
    ! git -C "$comparison" remote add canonical "$MIGRATION_REMOTE" ||
    ! git -C "$comparison" fetch -q --no-tags canonical "$upstream_oid:refs/j3w1zsh/upstream"; then
    migration_cleanup_ephemeral_dir "$comparison" || migration_die "Failed to clean the guarded tracking comparison directory."
    migration_die "Expected canonical-main commit is not fetchable: $upstream_oid"
  fi
  if ! git -C "$comparison" cat-file -e "$current_oid^{commit}" 2>/dev/null ||
    ! git -C "$comparison" merge-base --is-ancestor "$current_oid" refs/j3w1zsh/upstream; then
    migration_cleanup_ephemeral_dir "$comparison" || migration_die "Failed to clean the guarded tracking comparison directory."
    return 1
  fi
  migration_cleanup_ephemeral_dir "$comparison" || migration_die "Failed to clean the guarded tracking comparison directory."
}

migration_fetch_tracking_ref() {
  local target="$1" upstream_oid="$2"
  if [[ $(git -C "$target" rev-parse --is-shallow-repository) == true ]]; then
    git -C "$target" fetch --no-tags --unshallow origin "$upstream_oid:refs/remotes/origin/main"
  else
    git -C "$target" fetch --no-tags origin "$upstream_oid:refs/remotes/origin/main"
  fi
}

migration_repair_tracking() {
  [[ $MIGRATION_EXPECTED_COMMIT =~ ^[0-9a-f]{40}$ ]] ||
    migration_die "--expected-commit must be the current full 40-hex checkout OID." "$MIGRATION_EXIT_USAGE"
  [[ $MIGRATION_EXPECTED_UPSTREAM_COMMIT =~ ^[0-9a-f]{40}$ ]] ||
    migration_die "--expected-upstream-commit must be the full 40-hex canonical-main OID." "$MIGRATION_EXIT_USAGE"
  [[ -d $MIGRATION_TARGET/.git && ! -L $MIGRATION_TARGET ]] ||
    migration_die "Tracking recovery requires a regular Git checkout: $MIGRATION_TARGET"

  local head branch origin configured_remote configured_merge checkout_status existing_ref remote_main
  local config_digest_before config_digest_after upstream status_line
  head="$(git -C "$MIGRATION_TARGET" rev-parse HEAD)"
  [[ $head == "$MIGRATION_EXPECTED_COMMIT" ]] ||
    migration_die "Checkout HEAD is $head, not the expected preserved commit $MIGRATION_EXPECTED_COMMIT." "$MIGRATION_EXIT_PROTECTED"
  branch="$(git -C "$MIGRATION_TARGET" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
  [[ $branch == main ]] || migration_die "Tracking recovery requires the local main branch." "$MIGRATION_EXIT_PROTECTED"
  origin="$(git -C "$MIGRATION_TARGET" remote get-url origin 2>/dev/null || true)"
  [[ $origin == "$MIGRATION_REMOTE" ]] ||
    migration_die "Tracking recovery requires the exact canonical origin: $MIGRATION_REMOTE" "$MIGRATION_EXIT_PROTECTED"
  configured_remote="$(git -C "$MIGRATION_TARGET" config --get branch.main.remote 2>/dev/null || true)"
  configured_merge="$(git -C "$MIGRATION_TARGET" config --get branch.main.merge 2>/dev/null || true)"
  [[ $configured_remote == origin && $configured_merge == refs/heads/main ]] ||
    migration_die "Tracking recovery refuses to rewrite unexpected branch configuration." "$MIGRATION_EXIT_PROTECTED"
  checkout_status="$(git -C "$MIGRATION_TARGET" status --short --untracked-files=all)"
  [[ -z $checkout_status ]] ||
    migration_die "Tracking recovery preserves authored, staged, deleted, renamed, and untracked checkout state." "$MIGRATION_EXIT_PROTECTED"

  existing_ref="$(git -C "$MIGRATION_TARGET" rev-parse --verify refs/remotes/origin/main 2>/dev/null || true)"
  [[ -z $existing_ref || $existing_ref == "$MIGRATION_EXPECTED_UPSTREAM_COMMIT" ]] ||
    migration_die "Existing origin/main differs from the exact expected upstream commit." "$MIGRATION_EXIT_PROTECTED"
  remote_main="$(migration_remote_main_oid)"
  [[ $remote_main == "$MIGRATION_EXPECTED_UPSTREAM_COMMIT" ]] ||
    migration_die "Canonical main is $remote_main, not the expected recovery commit $MIGRATION_EXPECTED_UPSTREAM_COMMIT."
  migration_remote_contains_commit "$MIGRATION_EXPECTED_COMMIT" "$MIGRATION_EXPECTED_UPSTREAM_COMMIT" ||
    migration_die "The preserved checkout commit is not an ancestor of the expected canonical main; unique or divergent history is protected." "$MIGRATION_EXIT_PROTECTED"

  if [[ $MIGRATION_DRY_RUN == 1 ]]; then
    printf 'Tracking recovery plan\n'
    printf '  checkout: %s\n  current commit: %s\n  canonical main: %s\n' \
      "$MIGRATION_TARGET" "$MIGRATION_EXPECTED_COMMIT" "$MIGRATION_EXPECTED_UPSTREAM_COMMIT"
    printf '  origin/main: %s\n' "$([[ -n $existing_ref ]] && printf present || printf missing)"
    printf 'Dry run complete; HEAD, checkout files, branch config, local refs, recovery data, packages, and user configuration were unchanged.\n'
    return 0
  fi

  config_digest_before="$(git -C "$MIGRATION_TARGET" config --local --null --list | sha256sum | awk '{print $1}')"
  if [[ -z $existing_ref || $(git -C "$MIGRATION_TARGET" rev-parse --is-shallow-repository) == true ]]; then
    migration_fetch_tracking_ref "$MIGRATION_TARGET" "$MIGRATION_EXPECTED_UPSTREAM_COMMIT" ||
      migration_die "Tracking recovery could not fetch the exact canonical-main history."
  fi
  [[ $(git -C "$MIGRATION_TARGET" rev-parse HEAD) == "$MIGRATION_EXPECTED_COMMIT" ]] ||
    migration_die "Tracking recovery changed HEAD unexpectedly." "$MIGRATION_EXIT_PROTECTED"
  [[ $(git -C "$MIGRATION_TARGET" rev-parse --verify refs/remotes/origin/main) == "$MIGRATION_EXPECTED_UPSTREAM_COMMIT" ]] ||
    migration_die "Tracking recovery did not establish the exact canonical-main ref."
  upstream="$(git -C "$MIGRATION_TARGET" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true)"
  [[ $upstream == origin/main ]] || migration_die "Tracking recovery did not establish origin/main as the resolvable upstream."
  [[ $(git -C "$MIGRATION_TARGET" rev-parse --is-shallow-repository) == false ]] ||
    migration_die "Tracking recovery did not restore the full history required for safe relation checks."
  config_digest_after="$(git -C "$MIGRATION_TARGET" config --local --null --list | sha256sum | awk '{print $1}')"
  [[ $config_digest_after == "$config_digest_before" ]] ||
    migration_die "Tracking recovery changed branch or remote configuration unexpectedly." "$MIGRATION_EXIT_PROTECTED"
  [[ -z $(git -C "$MIGRATION_TARGET" status --short --untracked-files=all) ]] ||
    migration_die "Tracking recovery changed checkout files unexpectedly." "$MIGRATION_EXIT_PROTECTED"
  status_line="$(git -C "$MIGRATION_TARGET" status --short --branch | head -n1)"
  [[ $status_line != *'[gone]'* ]] || migration_die "Tracking recovery left the upstream unresolved."
  printf 'Tracking recovery completed without changing HEAD or checkout files.\n'
  printf '  checkout: %s\n  upstream: origin/main\n  canonical main: %s\n' \
    "$MIGRATION_TARGET" "$MIGRATION_EXPECTED_UPSTREAM_COMMIT"
}

migration_timestamp() {
  date +%Y%m%d-%H%M%S-%N
}

migration_atomic_json() {
  local target="$1" content="$2" temporary
  mkdir -p "$(dirname -- "$target")"
  temporary="$(mktemp "$(dirname -- "$target")/.json.XXXXXX")"
  printf '%s\n' "$content" >"$temporary"
  chmod 600 "$temporary"
  mv -- "$temporary" "$target"
}

migration_latest_root() {
  local base="$MIGRATION_STATE_BASE"
  [[ -d $base ]] || return 0
  find "$base" -mindepth 1 -maxdepth 1 -type d -name '20*' -print 2>/dev/null | LC_ALL=C sort -r | head -n1
}

migration_platform() {
  if [[ ${J3W1ZSH_MIGRATION_TEST_MODE:-0} == 1 && -n ${J3W1ZSH_MIGRATION_TEST_PLATFORM:-} ]]; then
    printf '%s\n' "$J3W1ZSH_MIGRATION_TEST_PLATFORM"
  elif [[ ${PREFIX:-} == /data/data/com.termux/files/usr ]]; then
    printf 'termux\n'
  elif [[ -n ${WSL_DISTRO_NAME:-} ]] || grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null; then
    grep -qi wsl2 /proc/sys/kernel/osrelease 2>/dev/null || migration_die "WSL 1 is unsupported."
    printf 'wsl\n'
  elif [[ -r /etc/os-release ]] && (source /etc/os-release; [[ ${ID:-} == arch ]]); then
    printf 'arch\n'
  else
    printf 'unsupported\n'
  fi
}

migration_discover_source() {
  if [[ -n $MIGRATION_SOURCE ]]; then
    printf '%s\n' "$MIGRATION_SOURCE"
    return 0
  fi
  local candidate
  for candidate in "$HOME/bloody-writer" "$HOME/projects/bloody-writer" "$HOME/.local/share/bloody-writer"; do
    [[ -d $candidate/.git ]] && { printf '%s\n' "$candidate"; return 0; }
  done
  return 1
}

migration_inventory_json() {
  local status="$1" staged="$2" unstaged="$3" untracked="$4" unique="$5" generated_only="$6"
  jq -cn \
    --argjson schema_version 1 \
    --arg platform "$MIGRATION_PLATFORM" \
    --arg source "$MIGRATION_SOURCE" \
    --arg target "$MIGRATION_TARGET" \
    --arg target_ref "$MIGRATION_TARGET_REF" \
    --arg expected_commit "$MIGRATION_EXPECTED_COMMIT" \
    --arg classification "$status" \
    --arg installation_state "$MIGRATION_INSTALLATION_STATE" \
    --arg source_commit "$MIGRATION_SOURCE_COMMIT" \
    --argjson plausible_sources "$(migration_plausible_sources_json)" \
    --argjson staged "$staged" --argjson unstaged "$unstaged" --argjson untracked "$untracked" \
    --argjson unique_commits "$unique" --argjson generated_only "$generated_only" \
    --arg discovered_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{schema_version:$schema_version,platform:$platform,source:$source,target:$target,target_ref:$target_ref,expected_commit:$expected_commit,classification:$classification,installation_state:$installation_state,plausible_sources:$plausible_sources,git:{source_commit:$source_commit,staged:$staged,unstaged:$unstaged,untracked:$untracked,unique_commits:$unique_commits,generated_only:$generated_only},discovered_at:$discovered_at}'
}

migration_plausible_sources_json() {
  local candidates='[]' candidate resolved has_git=false origin="" head=""
  for candidate in "$MIGRATION_SOURCE" "$HOME/bloody-writer" "$HOME/projects/bloody-writer" "$HOME/.local/share/bloody-writer"; do
    resolved="$(readlink -m -- "$candidate")"
    if jq -e --arg candidate "$resolved" 'index($candidate)' <<<"$candidates" >/dev/null; then
      continue
    fi
    has_git=false; origin=""; head=""
    if [[ -d $resolved/.git ]]; then
      has_git=true
      origin="$(git -C "$resolved" remote get-url origin 2>/dev/null || true)"
      head="$(git -C "$resolved" rev-parse HEAD 2>/dev/null || true)"
    fi
    candidates="$(jq -cn --argjson candidates "$candidates" --arg path "$resolved" --argjson has_git "$has_git" --arg origin "$origin" --arg head "$head" '$candidates + [{path:$path,git_checkout:$has_git,origin:(if $origin=="" then null else $origin end),head:(if $head=="" then null else $head end)}]')"
  done
  printf '%s\n' "$candidates"
}

migration_classify_installation() {
  local old_config="${XDG_CONFIG_HOME:-$HOME/.config}/bloody-writer"
  local old_state="${XDG_STATE_HOME:-$HOME/.local/state}/bloody-writer"
  local present=0 path
  for path in "$HOME/.local/bin/bloody-writer" "$HOME/.zshrc" "$HOME/.tmux.conf" "$HOME/.config/nvim" "$old_config" "$old_state"; do
    [[ ! -e $path && ! -L $path ]] || ((present += 1))
  done
  if ((present == 0)); then
    printf 'absent\n'
  elif ((present == 6)); then
    printf 'complete\n'
  else
    printf 'partial\n'
  fi
}

migration_source_origin_allowed() {
  local origin="$1"
  case "$origin" in
  git@github.com:j3w1/bloody-writer.git | https://github.com/j3w1/bloody-writer | https://github.com/j3w1/bloody-writer.git | \
    git@github.com:j3w1/j3w1zsh.git | https://github.com/j3w1/j3w1zsh | https://github.com/j3w1/j3w1zsh.git)
    return 0
    ;;
  esac
  [[ ${J3W1ZSH_MIGRATION_TEST_MODE:-0} == 1 && -n ${J3W1ZSH_MIGRATION_TEST_FORMER_REMOTE:-} &&
    $origin == "$J3W1ZSH_MIGRATION_TEST_FORMER_REMOTE" ]]
}

migration_classify() {
  [[ -d $MIGRATION_SOURCE/.git ]] || migration_die "Source is not a Git checkout: $MIGRATION_SOURCE"
  migration_validate_home_path "$MIGRATION_SOURCE"
  [[ ! -e $MIGRATION_TARGET && ! -L $MIGRATION_TARGET ]] || migration_die "Target path is occupied: $MIGRATION_TARGET"
  local origin
  origin="$(git -C "$MIGRATION_SOURCE" remote get-url origin 2>/dev/null || true)"
  migration_source_origin_allowed "$origin" ||
    migration_die "Source origin is neither the former nor renamed canonical repository."

  local staged=false unstaged=false untracked=false unique=false divergent=false generated_only=false classification=exact-known
  MIGRATION_SOURCE_COMMIT="$(git -C "$MIGRATION_SOURCE" rev-parse HEAD)"
  MIGRATION_INSTALLATION_STATE="$(migration_classify_installation)"
  git -C "$MIGRATION_SOURCE" diff --cached --quiet -- || staged=true
  git -C "$MIGRATION_SOURCE" diff --quiet -- || unstaged=true
  [[ -z $(git -C "$MIGRATION_SOURCE" ls-files --others --exclude-standard) ]] || untracked=true
  if git -C "$MIGRATION_SOURCE" rev-parse --verify origin/main >/dev/null 2>&1; then
    [[ -z $(git -C "$MIGRATION_SOURCE" log --format=%H origin/main..HEAD) ]] || unique=true
    git -C "$MIGRATION_SOURCE" merge-base --is-ancestor HEAD origin/main >/dev/null 2>&1 ||
      git -C "$MIGRATION_SOURCE" merge-base --is-ancestor origin/main HEAD >/dev/null 2>&1 || divergent=true
  fi
  if [[ $unstaged == true && $staged == false && $untracked == false && $unique == false && $divergent == false ]]; then
    local changed
    changed="$(git -C "$MIGRATION_SOURCE" diff --name-only --diff-filter=M)"
    if [[ $changed == "$MIGRATION_KNOWN_GENERATED_PATH" ]]; then
      generated_only=true
      classification=generated-drift
    else
      classification=authored-dirty
    fi
  fi
  if [[ $divergent == true ]]; then classification=divergent
  elif [[ $unique == true ]]; then classification=local-commit
  elif [[ $staged == true ]]; then classification=staged
  elif [[ $untracked == true ]]; then classification=untracked
  fi
  MIGRATION_CLASSIFICATION="$classification"
  MIGRATION_STAGED="$staged"
  MIGRATION_UNSTAGED="$unstaged"
  MIGRATION_UNTRACKED="$untracked"
  MIGRATION_UNIQUE="$unique"
  MIGRATION_GENERATED_ONLY="$generated_only"
}

migration_preserve_path_snapshot() {
  local path="$1" label="$2"
  local destination="$MIGRATION_RECOVERY_ROOT/pre-cutover/$label"
  migration_validate_home_path "$path"
  mkdir -p "$(dirname -- "$destination")"
  if [[ -e $path || -L $path ]]; then
    cp -a --no-dereference -- "$path" "$destination"
    printf '%s\tpresent\t%s\n' "$path" "$destination" >>"$MIGRATION_RECOVERY_ROOT/path-manifest.tsv"
  else
    printf '%s\tabsent\t%s\n' "$path" "$destination" >>"$MIGRATION_RECOVERY_ROOT/path-manifest.tsv"
  fi
}

migration_preserve() {
  mkdir -p "$MIGRATION_RECOVERY_ROOT"
  chmod 700 "$MIGRATION_RECOVERY_ROOT"
  : >"$MIGRATION_RECOVERY_ROOT/path-manifest.tsv"
  chmod 600 "$MIGRATION_RECOVERY_ROOT/path-manifest.tsv"
  migration_atomic_json "$MIGRATION_RECOVERY_ROOT/inventory.json" \
    "$(migration_inventory_json "$MIGRATION_CLASSIFICATION" "$MIGRATION_STAGED" "$MIGRATION_UNSTAGED" "$MIGRATION_UNTRACKED" "$MIGRATION_UNIQUE" "$MIGRATION_GENERATED_ONLY")"

  git -C "$MIGRATION_SOURCE" diff --binary -- >"$MIGRATION_RECOVERY_ROOT/tracked-worktree.patch"
  git -C "$MIGRATION_SOURCE" diff --cached --binary -- >"$MIGRATION_RECOVERY_ROOT/tracked-index.patch"
  chmod 600 "$MIGRATION_RECOVERY_ROOT"/*.patch
  local untracked relative
  while IFS= read -r -d '' untracked; do
    [[ -n $untracked ]] || continue
    relative="untracked/$untracked"
    mkdir -p "$MIGRATION_RECOVERY_ROOT/$(dirname -- "$relative")"
    cp -a --no-dereference -- "$MIGRATION_SOURCE/$untracked" "$MIGRATION_RECOVERY_ROOT/$relative"
  done < <(git -C "$MIGRATION_SOURCE" ls-files --others --exclude-standard -z)
  if [[ $MIGRATION_UNIQUE == true ]]; then
    git -C "$MIGRATION_SOURCE" bundle create "$MIGRATION_RECOVERY_ROOT/unique-refs.bundle" --all
    git bundle verify "$MIGRATION_RECOVERY_ROOT/unique-refs.bundle" >/dev/null
  fi

  local old_config="${XDG_CONFIG_HOME:-$HOME/.config}/bloody-writer"
  local old_state="${XDG_STATE_HOME:-$HOME/.local/state}/bloody-writer"
  local old_cache="${XDG_CACHE_HOME:-$HOME/.cache}/bloody-writer"
  migration_preserve_path_snapshot "$HOME/.zshrc" zshrc
  migration_preserve_path_snapshot "$HOME/.tmux.conf" tmux.conf
  migration_preserve_path_snapshot "$HOME/.config/nvim" nvim
  migration_preserve_path_snapshot "$HOME/.local/bin/tma" tma
  migration_preserve_path_snapshot "$HOME/.local/bin/bw-clipboard-copy" clipboard-helper
  migration_preserve_path_snapshot "$HOME/.local/bin/bloody-writer" old-command
  migration_preserve_path_snapshot "$old_config" old-config
  migration_preserve_path_snapshot "$old_state" old-state
  migration_preserve_path_snapshot "$old_cache" old-cache
}

migration_write_journal() {
  local phase="$1" status="$2"
  migration_atomic_json "$MIGRATION_RECOVERY_ROOT/journal.json" "$(jq -cn \
    --argjson schema_version 1 --arg phase "$phase" --arg status "$status" \
    --arg source "$MIGRATION_SOURCE" --arg target "$MIGRATION_TARGET" --arg platform "$MIGRATION_PLATFORM" \
    --arg target_ref "$MIGRATION_TARGET_REF" --arg expected_commit "$MIGRATION_EXPECTED_COMMIT" \
    --arg updated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{schema_version:$schema_version,phase:$phase,status:$status,source:$source,target:$target,platform:$platform,target_ref:$target_ref,expected_commit:$expected_commit,updated_at:$updated_at}')"
}

migration_resolve_dry_run() {
  local temporary resolved
  migration_create_ephemeral_dir temporary resolve
  git -C "$temporary" init -q
  git -C "$temporary" remote add origin "$MIGRATION_REMOTE"
  if ! git -C "$temporary" fetch -q --depth=1 origin "$MIGRATION_TARGET_REF"; then
    migration_cleanup_ephemeral_dir "$temporary" || migration_die "Failed to clean the guarded dry-run resolver directory."
    migration_die "Target ref is not reachable: $MIGRATION_TARGET_REF"
  fi
  resolved="$(git -C "$temporary" rev-parse FETCH_HEAD)"
  migration_cleanup_ephemeral_dir "$temporary" || migration_die "Failed to clean the guarded dry-run resolver directory."
  [[ -n $resolved ]] || migration_die "Target ref is not reachable: $MIGRATION_TARGET_REF"
  [[ $resolved == "$MIGRATION_EXPECTED_COMMIT" ]] || migration_die "Target ref resolves to $resolved, not $MIGRATION_EXPECTED_COMMIT."
}

migration_acquire() {
  migration_log "Acquiring exact j3w1zsh commit $MIGRATION_EXPECTED_COMMIT."
  local available_kib canonical_main upstream status_line
  available_kib="$(df -Pk "$HOME" | awk 'NR==2 {print $4}')"
  [[ $available_kib =~ ^[0-9]+$ && $available_kib -ge 20480 ]] || migration_die "At least 20 MiB of free home storage is required."
  mkdir -p "$MIGRATION_TARGET"
  git -C "$MIGRATION_TARGET" init -q
  local existing_origin
  existing_origin="$(git -C "$MIGRATION_TARGET" remote get-url origin 2>/dev/null || true)"
  if [[ -n $existing_origin ]]; then
    [[ $existing_origin == "$MIGRATION_REMOTE" ]] || migration_die "Partial target has an unexpected origin: $existing_origin"
  else
    git -C "$MIGRATION_TARGET" remote add origin "$MIGRATION_REMOTE"
  fi
  git -C "$MIGRATION_TARGET" fetch --no-tags origin "$MIGRATION_TARGET_REF"
  local resolved
  resolved="$(git -C "$MIGRATION_TARGET" rev-parse FETCH_HEAD)"
  [[ $resolved == "$MIGRATION_EXPECTED_COMMIT" ]] || migration_die "Fetched target resolved to $resolved, not $MIGRATION_EXPECTED_COMMIT."
  canonical_main="$(migration_remote_main_oid)"
  git -C "$MIGRATION_TARGET" fetch --no-tags origin "$canonical_main:refs/remotes/origin/main"
  [[ $(git -C "$MIGRATION_TARGET" rev-parse --verify refs/remotes/origin/main) == "$canonical_main" ]] ||
    migration_die "Acquisition did not materialize the exact observed canonical-main ref."
  git -C "$MIGRATION_TARGET" merge-base --is-ancestor "$resolved" "$canonical_main" ||
    migration_die "The exact migration target is not an ancestor of canonical main; acquisition stopped before checkout." "$MIGRATION_EXIT_PROTECTED"
  git -C "$MIGRATION_TARGET" checkout -q -B main "$resolved"
  git -C "$MIGRATION_TARGET" config branch.main.remote origin
  git -C "$MIGRATION_TARGET" config branch.main.merge refs/heads/main
  upstream="$(git -C "$MIGRATION_TARGET" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true)"
  [[ $upstream == origin/main ]] || migration_die "Acquired main does not resolve its exact origin/main upstream."
  [[ $(git -C "$MIGRATION_TARGET" rev-parse --is-shallow-repository) == false ]] ||
    migration_die "Acquisition left a shallow checkout that cannot safely classify future updates."
  status_line="$(git -C "$MIGRATION_TARGET" status --short --branch | head -n1)"
  [[ $status_line != *'[gone]'* ]] || migration_die "Acquired main reports an unresolved upstream."
  [[ -z $(git -C "$MIGRATION_TARGET" status --short) ]] || migration_die "Acquired checkout is not clean."
  migration_write_journal acquire complete
}

migration_unquote_setting() {
  local value="$1"
  if [[ $value == "'"*"'" || $value == '"'*'"' ]]; then
    value="${value:1:${#value}-2}"
  fi
  [[ $value != *$'\n'* && $value != *$'\r'* ]] || migration_die "Legacy setting contains control characters."
  printf '%s\n' "$value"
}

migration_translate_settings() {
  local old_settings="${XDG_CONFIG_HOME:-$HOME/.config}/bloody-writer/settings.zsh"
  local new_config="$HOME/.config/j3w1zsh"
  local new_settings="$new_config/settings.zsh"
  [[ -f $old_settings && ! -L $old_settings ]] || { migration_write_journal translate complete; return 0; }
  mkdir -p "$new_config"
  local temporary unknown="$MIGRATION_RECOVERY_ROOT/unknown-settings.txt"
  temporary="$(mktemp "$new_config/.settings.XXXXXX")"
  : >"$unknown"
  chmod 600 "$unknown"
  local line key value new_key
  while IFS= read -r line || [[ -n $line ]]; do
    [[ $line =~ ^[[:space:]]*$ || $line =~ ^[[:space:]]*# ]] && continue
    if [[ $line =~ ^export[[:space:]]+([A-Z0-9_]+)=(.*)$ ]]; then
      key="${BASH_REMATCH[1]}"; value="$(migration_unquote_setting "${BASH_REMATCH[2]}")"
      case "$key" in
      BLOODY_WRITER_DOCUMENTS) new_key=J3W1ZSH_EDIT_ROOT ;;
      BLOODY_WRITER_GITHUB_KEY) new_key=J3W1ZSH_GITHUB_KEY ;;
      BLOODY_WRITER_WSL_HOST) new_key=J3W1ZSH_REMOTE_HOST ;;
      BLOODY_WRITER_WSL_USER) new_key=J3W1ZSH_REMOTE_USER ;;
      BLOODY_WRITER_WSL_TMA) new_key=J3W1ZSH_REMOTE_ATTACH_COMMAND ;;
      *) printf '%s\n' "$line" >>"$unknown"; continue ;;
      esac
      [[ $value != *"'"* ]] || { printf '%s\n' "$line" >>"$unknown"; continue; }
      printf "export %s='%s'\n" "$new_key" "$value" >>"$temporary"
    else
      printf '%s\n' "$line" >>"$unknown"
    fi
  done <"$old_settings"
  chmod 600 "$temporary"
  if [[ -e $new_settings ]]; then
    cp -a -- "$new_settings" "$MIGRATION_RECOVERY_ROOT/preexisting-new-settings.zsh"
    # The normal installer owns preservation; migration never silently overwrites an existing file.
    if [[ -s $temporary ]]; then
      cat "$temporary" >>"$MIGRATION_RECOVERY_ROOT/translated-settings-review.zsh"
      rm -- "$temporary"
      migration_write_journal translate checkpoint
      migration_die "New settings already exist; translated values require manual review at $MIGRATION_RECOVERY_ROOT/translated-settings-review.zsh" "$MIGRATION_EXIT_CHECKPOINT"
    fi
  else
    mv -- "$temporary" "$new_settings"
  fi
  if [[ -s $unknown ]]; then
    migration_write_journal translate checkpoint
    migration_die "Unknown legacy settings were preserved for manual review: $unknown" "$MIGRATION_EXIT_CHECKPOINT"
  fi
  migration_write_journal translate complete
}

migration_workspace_candidate() {
  local old_active="${XDG_STATE_HOME:-$HOME/.local/state}/bloody-writer/workspaces/active.json"
  [[ -f $old_active ]] || { migration_write_journal workspace complete; return 0; }
  local manifest
  manifest="$(jq -r '.manifest // ""' "$old_active" 2>/dev/null || true)"
  [[ -n $manifest && -f $manifest && ! -L $manifest ]] || { migration_write_journal workspace complete; return 0; }
  local output="$MIGRATION_RECOVERY_ROOT/workspace/j3w1zsh.workspace.json"
  mkdir -p "$(dirname -- "$output")"
  if [[ -e $output || -L $output ]]; then
    [[ -f $output && ! -L $output ]] || migration_die "Interrupted workspace candidate is not a regular file."
    local comparison
    migration_create_ephemeral_dir comparison workspace-compare
    "$MIGRATION_TARGET/bin/j3w1zsh" workspace migrate "$manifest" --output "$comparison/j3w1zsh.workspace.json" >/dev/null
    if ! cmp -s -- "$output" "$comparison/j3w1zsh.workspace.json"; then
      migration_cleanup_ephemeral_dir "$comparison" || migration_die "Failed to clean the guarded workspace comparison directory."
      migration_write_journal workspace checkpoint
      migration_die "Interrupted workspace candidate differs from a fresh exact conversion; owner review is required." "$MIGRATION_EXIT_CHECKPOINT"
    fi
    if [[ -e $output.migration-report.json ]]; then
      if ! cmp -s -- "$output.migration-report.json" "$comparison/j3w1zsh.workspace.json.migration-report.json"; then
        migration_cleanup_ephemeral_dir "$comparison" || migration_die "Failed to clean the guarded workspace comparison directory."
        migration_write_journal workspace checkpoint
        migration_die "Interrupted workspace migration report differs from a fresh exact conversion; owner review is required." "$MIGRATION_EXIT_CHECKPOINT"
      fi
    else
      mv -- "$comparison/j3w1zsh.workspace.json.migration-report.json" "$output.migration-report.json"
    fi
    migration_cleanup_ephemeral_dir "$comparison" || migration_die "Failed to clean the guarded workspace comparison directory."
    migration_write_journal workspace complete
    return 0
  fi
  "$MIGRATION_TARGET/bin/j3w1zsh" workspace migrate "$manifest" --output "$output"
  migration_write_journal workspace complete
}

migration_reconcile() {
  migration_log "Reconciling the new platform through the normal j3w1zsh adapters."
  local environment=(
    "J3W1ZSH_MIGRATION_ACTIVE=1"
    "J3W1ZSH_MIGRATION_RECOVERY_ROOT=$MIGRATION_RECOVERY_ROOT"
  )
  if [[ ${J3W1ZSH_MIGRATION_TEST_MODE:-0} == 1 ]]; then
    environment+=("J3W1ZSH_TEST_MODE=1" "J3W1ZSH_TEST_PLATFORM=$MIGRATION_PLATFORM")
  fi
  local result
  if env "${environment[@]}" "$MIGRATION_TARGET/bin/j3w1zsh" install --no-packages --yes; then
    migration_write_journal reconcile complete
  else
    result=$?
    migration_write_journal reconcile checkpoint
    return "$result"
  fi
}

migration_verify() {
  local environment=()
  if [[ ${J3W1ZSH_MIGRATION_TEST_MODE:-0} == 1 ]]; then
    environment+=("J3W1ZSH_TEST_MODE=1" "J3W1ZSH_TEST_PLATFORM=$MIGRATION_PLATFORM")
  fi
  env "${environment[@]}" "$MIGRATION_TARGET/bin/j3w1zsh" platform --json | jq -e --arg platform "$MIGRATION_PLATFORM" '.status == "ok" and .data.id == $platform' >/dev/null
  env "${environment[@]}" "$MIGRATION_TARGET/bin/j3w1zsh" status --json | jq -e '.status == "ok"' >/dev/null
  env "${environment[@]}" "$MIGRATION_TARGET/bin/j3w1zsh" doctor --json | jq -e '.status == "ok"' >/dev/null
  env "${environment[@]}" "$MIGRATION_TARGET/bin/j3w1zsh" theme current --json | jq -e '.status == "ok" and .data.id == "j3w1zsh"' >/dev/null
  local target expected
  while IFS=$'\t' read -r target expected; do
    [[ -L $target ]] || migration_die "Selected managed link is missing: $target"
    [[ $(readlink -f -- "$target") == "$(readlink -f -- "$expected")" ]] ||
      migration_die "Selected managed link does not resolve into the exact new checkout: $target"
  done <<EOF
$HOME/.local/bin/j3w1zsh	$MIGRATION_TARGET/bin/j3w1zsh
$HOME/.zshrc	$MIGRATION_TARGET/dotfiles/zsh/.zshrc
$HOME/.tmux.conf	$MIGRATION_TARGET/dotfiles/tmux/.tmux.conf
$HOME/.config/nvim	$MIGRATION_TARGET/dotfiles/nvim/.config/nvim
$HOME/.local/bin/tma	$MIGRATION_TARGET/dotfiles/local-bin/.local/bin/tma
$HOME/.local/bin/j3w1zsh-clipboard-copy	$MIGRATION_TARGET/dotfiles/local-bin/.local/bin/j3w1zsh-clipboard-copy
EOF
  migration_write_journal verify complete
}

migration_verify_source_still_safe() {
  local expected_head current_head status late_root untracked source_check="$MIGRATION_SOURCE"
  if [[ ! -d $source_check/.git && -d $MIGRATION_RECOVERY_ROOT/legacy-active/checkout/.git ]]; then
    source_check="$MIGRATION_RECOVERY_ROOT/legacy-active/checkout"
  fi
  if [[ ! -d $source_check/.git ]]; then
    migration_write_journal verify-source protected-stop
    migration_die "The former checkout disappeared after preservation; cutover stopped for owner review." "$MIGRATION_EXIT_PROTECTED"
  fi
  expected_head="$(jq -r '.git.source_commit' "$MIGRATION_RECOVERY_ROOT/inventory.json")"
  current_head="$(git -C "$source_check" rev-parse HEAD 2>/dev/null || true)"
  status="$(git -C "$source_check" status --short --untracked-files=all 2>/dev/null || true)"
  [[ $current_head == "$expected_head" && -z $status ]] && return 0
  late_root="$MIGRATION_RECOVERY_ROOT/late-source-state-$(migration_timestamp)"
  mkdir -p "$late_root/untracked"
  chmod 700 "$late_root"
  git -C "$source_check" diff --binary -- >"$late_root/tracked-worktree.patch"
  git -C "$source_check" diff --cached --binary -- >"$late_root/tracked-index.patch"
  chmod 600 "$late_root"/*.patch
  while IFS= read -r -d '' untracked; do
    mkdir -p "$late_root/untracked/$(dirname -- "$untracked")"
    cp -a --no-dereference -- "$source_check/$untracked" "$late_root/untracked/$untracked"
  done < <(git -C "$source_check" ls-files --others --exclude-standard -z)
  git -C "$source_check" bundle create "$late_root/refs.bundle" --all
  git bundle verify "$late_root/refs.bundle" >/dev/null
  migration_write_journal verify-source protected-stop
  migration_die "The former checkout changed after preservation; late bytes and refs were preserved at $late_root and cutover stopped." "$MIGRATION_EXIT_PROTECTED"
}

migration_deactivate() {
  local old_config="${XDG_CONFIG_HOME:-$HOME/.config}/bloody-writer"
  local old_state="${XDG_STATE_HOME:-$HOME/.local/state}/bloody-writer"
  local old_cache="${XDG_CACHE_HOME:-$HOME/.cache}/bloody-writer"
  local legacy_root="$MIGRATION_RECOVERY_ROOT/legacy-active"
  mkdir -p "$legacy_root"
  local path label
  while IFS=$'\t' read -r path label; do
    migration_validate_home_path "$path"
    if [[ -e $path || -L $path ]]; then
      mkdir -p "$legacy_root/$(dirname -- "$label")"
      mv -- "$path" "$legacy_root/$label"
    fi
  done <<EOF
$HOME/.local/bin/bloody-writer	command
$HOME/.local/bin/bw-clipboard-copy	clipboard-helper
$old_config	config
$old_state	state
$old_cache	cache
EOF
  if [[ -d $MIGRATION_SOURCE ]]; then
    mv -- "$MIGRATION_SOURCE" "$legacy_root/checkout"
  fi
  migration_write_journal deactivate complete
}

migration_finalize() {
  migration_write_journal finalize complete
  printf '\nj3w1zsh migration completed.\n\n'
  printf 'New checkout: %s\n' "$MIGRATION_TARGET"
  printf 'Recovery manifest: %s\n' "$MIGRATION_RECOVERY_ROOT/inventory.json"
  printf 'Rollback: %s --rollback\n' "$MIGRATION_TARGET/scripts/legacy/migrate-to-j3w1zsh.sh"
  [[ ! -d $MIGRATION_RECOVERY_ROOT/workspace ]] || printf 'Workspace review: %s/workspace\n' "$MIGRATION_RECOVERY_ROOT"
  printf '\nEvidence commands:\n'
  printf '  command -v j3w1zsh\n  command -v bloody-writer || true\n'
  printf '  j3w1zsh platform --json\n  j3w1zsh status --json\n  j3w1zsh doctor --json\n'
}

migration_restore_snapshot() {
  local target="$1" state="$2" saved="$3"
  migration_validate_home_path "$target"
  if [[ -e $target || -L $target ]]; then
    local displaced="$MIGRATION_ROLLBACK_DISPLACED_ROOT/${target#"$HOME"/}"
    mkdir -p "$(dirname -- "$displaced")"
    mv -- "$target" "$displaced"
  fi
  if [[ $state == present ]]; then
    mkdir -p "$(dirname -- "$target")"
    cp -a --no-dereference -- "$saved" "$target"
  fi
}

migration_rollback() {
  MIGRATION_RECOVERY_ROOT="$(migration_latest_root)"
  [[ -n $MIGRATION_RECOVERY_ROOT && -f $MIGRATION_RECOVERY_ROOT/journal.json ]] || migration_die "No migration journal is available for rollback."
  if [[ -f $MIGRATION_RECOVERY_ROOT/rollback.json ]] &&
    jq -e '.status == "complete"' "$MIGRATION_RECOVERY_ROOT/rollback.json" >/dev/null 2>&1; then
    migration_note "Rollback is already complete: $MIGRATION_RECOVERY_ROOT"
    return 0
  fi
  local journal="$MIGRATION_RECOVERY_ROOT/journal.json"
  MIGRATION_SOURCE="$(jq -r .source "$journal")"
  MIGRATION_TARGET="$(jq -r .target "$journal")"
  migration_validate_home_path "$MIGRATION_SOURCE"
  migration_validate_home_path "$MIGRATION_TARGET"
  local legacy="$MIGRATION_RECOVERY_ROOT/legacy-active"
  MIGRATION_ROLLBACK_DISPLACED_ROOT="$MIGRATION_RECOVERY_ROOT/rollback-displaced/$(migration_timestamp)"
  if [[ -d $legacy/checkout && ! -e $MIGRATION_SOURCE ]]; then
    mkdir -p "$(dirname -- "$MIGRATION_SOURCE")"
    mv -- "$legacy/checkout" "$MIGRATION_SOURCE"
  fi
  local path state saved
  while IFS=$'\t' read -r path state saved; do
    [[ -n $path ]] || continue
    migration_restore_snapshot "$path" "$state" "$saved"
  done <"$MIGRATION_RECOVERY_ROOT/path-manifest.tsv"
  migration_atomic_json "$MIGRATION_RECOVERY_ROOT/rollback.json" "$(jq -cn --arg restored_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg new_checkout "$MIGRATION_TARGET" '{schema_version:1,status:"complete",restored_at:$restored_at,new_checkout_preserved:$new_checkout}')"
  printf 'Rollback completed. The new checkout was preserved at: %s\n' "$MIGRATION_TARGET"
}

migration_status_command() {
  MIGRATION_RECOVERY_ROOT="$(migration_latest_root)"
  [[ -n $MIGRATION_RECOVERY_ROOT ]] || { printf 'No j3w1zsh migration journal exists.\n'; return 0; }
  if [[ -f $MIGRATION_RECOVERY_ROOT/journal.json ]]; then
    jq . "$MIGRATION_RECOVERY_ROOT/journal.json"
  else
    printf 'Recovery root exists without a journal: %s\n' "$MIGRATION_RECOVERY_ROOT"
  fi
}

migration_completed_invocation() {
  local recovery journal recorded_source recorded_target recorded_ref recorded_commit phase status
  recovery="$(migration_latest_root)"
  [[ -n $recovery && -f $recovery/journal.json ]] || return 1
  journal="$recovery/journal.json"
  recorded_source="$(jq -r .source "$journal")"
  recorded_target="$(jq -r .target "$journal")"
  recorded_ref="$(jq -r .target_ref "$journal")"
  recorded_commit="$(jq -r .expected_commit "$journal")"
  phase="$(jq -r .phase "$journal")"
  status="$(jq -r .status "$journal")"
  [[ $phase == finalize && $status == complete ]] || return 1
  [[ $recorded_source == "$MIGRATION_SOURCE" && $recorded_target == "$MIGRATION_TARGET" ]] || return 1
  [[ $recorded_ref == "$MIGRATION_TARGET_REF" && $recorded_commit == "$MIGRATION_EXPECTED_COMMIT" ]] || return 1
  [[ -d $MIGRATION_TARGET/.git ]] || return 1
  [[ $(git -C "$MIGRATION_TARGET" rev-parse HEAD 2>/dev/null) == "$MIGRATION_EXPECTED_COMMIT" ]] || return 1
  [[ -z $(git -C "$MIGRATION_TARGET" status --short) ]] || return 1
  migration_note "Migration is already complete: $recovery"
}

migration_run() {
  migration_classify
  if [[ $MIGRATION_DRY_RUN == 1 ]]; then
    migration_resolve_dry_run
    printf 'Migration plan\n'
    printf '  platform: %s\n  source: %s\n  target: %s\n  target ref: %s\n  expected commit: %s\n  classification: %s\n' \
      "$MIGRATION_PLATFORM" "$MIGRATION_SOURCE" "$MIGRATION_TARGET" "$MIGRATION_TARGET_REF" "$MIGRATION_EXPECTED_COMMIT" "$MIGRATION_CLASSIFICATION"
    printf '  actions: discover, classify, preserve, acquire, translate, reconcile, workspace, host cutover, verify, deactivate, finalize\n'
    printf 'Dry run complete; no state, checkout, trust record, package, Git ref, or host configuration was changed.\n'
    return 0
  fi

  mkdir -p "$MIGRATION_STATE_BASE"
  chmod 700 "$MIGRATION_STATE_BASE"
  migration_preserve
  migration_write_journal preserve complete
  case "$MIGRATION_CLASSIFICATION" in
  staged | untracked | local-commit | divergent | authored-dirty)
    migration_write_journal preserve protected-stop
    migration_die "Protected source state was preserved at $MIGRATION_RECOVERY_ROOT; owner review is required before cutover." "$MIGRATION_EXIT_PROTECTED"
    ;;
  generated-drift)
    git -C "$MIGRATION_SOURCE" restore --worktree -- "$MIGRATION_KNOWN_GENERATED_PATH"
    ;;
  exact-known) ;;
  *) migration_die "Unsupported migration classification: $MIGRATION_CLASSIFICATION" ;;
  esac
  migration_acquire
  migration_translate_settings
  migration_reconcile
  migration_workspace_candidate
  migration_verify
  migration_verify_source_still_safe
  migration_deactivate
  migration_finalize
}

migration_phase_rank() {
  case "$1" in
  preserve) printf '1\n' ;; acquire) printf '2\n' ;; translate) printf '3\n' ;; reconcile) printf '4\n' ;;
  workspace) printf '5\n' ;; verify) printf '6\n' ;; deactivate) printf '7\n' ;; finalize) printf '8\n' ;;
  *) printf '0\n' ;;
  esac
}

migration_resume() {
  MIGRATION_RECOVERY_ROOT="$(migration_latest_root)"
  [[ -n $MIGRATION_RECOVERY_ROOT && -f $MIGRATION_RECOVERY_ROOT/journal.json ]] || migration_die "No migration journal is available to resume."
  local journal="$MIGRATION_RECOVERY_ROOT/journal.json" phase status rank
  MIGRATION_SOURCE="$(jq -r .source "$journal")"
  MIGRATION_TARGET="$(jq -r .target "$journal")"
  MIGRATION_PLATFORM="$(jq -r .platform "$journal")"
  MIGRATION_TARGET_REF="$(jq -r .target_ref "$journal")"
  MIGRATION_EXPECTED_COMMIT="$(jq -r .expected_commit "$journal")"
  phase="$(jq -r .phase "$journal")"
  status="$(jq -r .status "$journal")"
  rank="$(migration_phase_rank "$phase")"
  if [[ $status == protected-stop ]]; then
    migration_die "This migration stopped on protected source state. Start a fresh migration only after owner resolution; do not resume cutover." "$MIGRATION_EXIT_PROTECTED"
  fi
  if ((rank >= 8)) && [[ $status == complete ]]; then
    migration_note "Migration is already complete: $MIGRATION_RECOVERY_ROOT"
    return 0
  fi
  if ((rank < 2)); then migration_acquire; rank=2; fi
  if ((rank < 3)); then
    migration_translate_settings
    rank=3
  elif [[ $phase == translate && $status == checkpoint ]]; then
    if [[ ! -e $MIGRATION_RECOVERY_ROOT/translation-approved ]]; then
      migration_die "Review the preserved unknown/translated settings, apply the intended values to the new settings file, then create $MIGRATION_RECOVERY_ROOT/translation-approved and rerun --resume." "$MIGRATION_EXIT_CHECKPOINT"
    fi
    migration_write_journal translate complete
  fi
  if ((rank < 4)) || [[ $phase == reconcile && $status == checkpoint ]]; then migration_reconcile; rank=4; fi
  if ((rank < 5)); then migration_workspace_candidate; rank=5; fi
  if ((rank < 6)); then migration_verify; rank=6; fi
  if ((rank < 7)); then
    migration_verify_source_still_safe
    migration_deactivate
    rank=7
  fi
  migration_finalize
}

MIGRATION_TARGET_REF=""
MIGRATION_EXPECTED_COMMIT=""
MIGRATION_EXPECTED_UPSTREAM_COMMIT=""
MIGRATION_SOURCE=""
MIGRATION_TARGET_ARGUMENT=""
MIGRATION_DRY_RUN=0
MIGRATION_MODE=run
while (($#)); do
  case "$1" in
  --target-ref) shift; (($#)) || migration_die "--target-ref requires a value." "$MIGRATION_EXIT_USAGE"; MIGRATION_TARGET_REF="$1" ;;
  --expected-commit) shift; (($#)) || migration_die "--expected-commit requires a value." "$MIGRATION_EXIT_USAGE"; MIGRATION_EXPECTED_COMMIT="${1,,}" ;;
  --expected-upstream-commit) shift; (($#)) || migration_die "--expected-upstream-commit requires a value." "$MIGRATION_EXIT_USAGE"; MIGRATION_EXPECTED_UPSTREAM_COMMIT="${1,,}" ;;
  --source) shift; (($#)) || migration_die "--source requires a path." "$MIGRATION_EXIT_USAGE"; MIGRATION_SOURCE="$1" ;;
  --target) shift; (($#)) || migration_die "--target requires a path." "$MIGRATION_EXIT_USAGE"; MIGRATION_TARGET_ARGUMENT="$1" ;;
  --dry-run) MIGRATION_DRY_RUN=1 ;;
  --repair-tracking) MIGRATION_MODE=repair-tracking ;;
  --resume) MIGRATION_MODE=resume ;;
  --rollback) MIGRATION_MODE=rollback ;;
  --status) MIGRATION_MODE=status ;;
  -h | --help) migration_usage; exit 0 ;;
  *) migration_die "Unknown option: $1" "$MIGRATION_EXIT_USAGE" ;;
  esac
  shift
done

[[ -n ${HOME:-} && -d $HOME ]] || migration_die "HOME is not usable."
((EUID != 0)) || migration_die "Run migration as the normal user, not root."
MIGRATION_STATE_BASE="$HOME/.local/state/j3w1zsh/migrations"
MIGRATION_TARGET="${MIGRATION_TARGET_ARGUMENT:-${J3W1ZSH_MIGRATION_TARGET:-$HOME/j3w1zsh}}"
MIGRATION_REMOTE="https://github.com/j3w1/j3w1zsh.git"
if [[ ${J3W1ZSH_MIGRATION_TEST_MODE:-0} == 1 ]]; then
  MIGRATION_REMOTE="${J3W1ZSH_MIGRATION_REMOTE:-$MIGRATION_REMOTE}"
fi
migration_validate_home_path "$MIGRATION_TARGET"

case "$MIGRATION_MODE" in
status) migration_status_command ;;
rollback) migration_rollback ;;
resume) migration_resume ;;
repair-tracking)
  [[ -z $MIGRATION_SOURCE && -z $MIGRATION_TARGET_REF ]] ||
    migration_die "--repair-tracking does not accept --source or --target-ref." "$MIGRATION_EXIT_USAGE"
  migration_repair_tracking
  ;;
run)
  [[ -z $MIGRATION_EXPECTED_UPSTREAM_COMMIT && -z $MIGRATION_TARGET_ARGUMENT ]] ||
    migration_die "--expected-upstream-commit and --target are reserved for --repair-tracking." "$MIGRATION_EXIT_USAGE"
  [[ $MIGRATION_EXPECTED_COMMIT =~ ^[0-9a-f]{40}$ ]] || migration_die "--expected-commit must be a full 40-hex OID." "$MIGRATION_EXIT_USAGE"
  [[ -n $MIGRATION_TARGET_REF && $MIGRATION_TARGET_REF != -* && $MIGRATION_TARGET_REF != *$'\n'* ]] || migration_die "A safe explicit --target-ref is required." "$MIGRATION_EXIT_USAGE"
  [[ -n $MIGRATION_SOURCE ]] || MIGRATION_SOURCE="$(migration_discover_source)" || migration_die "No former checkout was discovered; pass --source PATH."
  if [[ $MIGRATION_DRY_RUN != 1 ]] && migration_completed_invocation; then
    exit 0
  fi
  MIGRATION_SOURCE="$(readlink -f -- "$MIGRATION_SOURCE")"
  MIGRATION_PLATFORM="$(migration_platform)"
  [[ $MIGRATION_PLATFORM =~ ^(arch|wsl|termux)$ ]] || migration_die "Unsupported migration platform: $MIGRATION_PLATFORM"
  if [[ $MIGRATION_DRY_RUN == 1 ]]; then
    MIGRATION_RECOVERY_ROOT=""
  else
    MIGRATION_RECOVERY_ROOT="$MIGRATION_STATE_BASE/$(migration_timestamp)"
  fi
  migration_run
  ;;
esac
