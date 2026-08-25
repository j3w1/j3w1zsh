#!/usr/bin/env bash

j3w1zsh_backup_paths() {
  local path
  for path in \
    "$HOME/.zshrc" \
    "$HOME/.tmux.conf" \
    "$HOME/.config/nvim" \
    "$HOME/.config/j3w1zsh" \
    "$HOME/.local/bin/tma" \
    "$HOME/.local/bin/j3w1zsh-clipboard-copy" \
    "$HOME/.local/bin/j3w1zsh"; do
    [[ -e $path || -L $path ]] && printf '%s\n' "${path#"$HOME"/}"
  done
}

j3w1zsh_backup_execute() {
  local archive="$1"
  shift
  j3w1zsh_ensure_dirs
  tar -C "$HOME" -czf "$archive" -- "$@"
  chmod 600 "$archive"
}

j3w1zsh_backup_command() {
  while (($#)); do
    case "$1" in --dry-run) J3W1ZSH_DRY_RUN=1 ;; *) j3w1zsh_usage_error "Unknown backup option: $1" ;; esac
    shift
  done
  local paths=()
  mapfile -t paths < <(j3w1zsh_backup_paths)
  ((${#paths[@]})) || j3w1zsh_die "No j3w1zsh configuration is installed."
  local stamp id archive
  stamp="$(date +%Y%m%d-%H%M%S-%N)"
  id="configuration-$stamp"
  archive="$J3W1ZSH_STATE_DIR/backups/$id.tar.gz"
  j3w1zsh_plan_reset
  j3w1zsh_plan_add backup backup file-reconciliation user "" "$archive" \
    "archive selected j3w1zsh configuration paths" false false "" true "archive lists only selected managed paths"
  if [[ $J3W1ZSH_DRY_RUN == 1 ]]; then
    local data
    data="$(printf '%s\n' "${paths[@]}" | jq -Rsc --arg id "$id" --arg archive "$archive" '{backup_id:$id,archive:$archive,paths:(split("\n")|map(select(length>0))),dry_run:true}')"
    [[ $J3W1ZSH_OUTPUT_MODE != json ]] || { j3w1zsh_json_envelope backup ok "$data"; return; }
    jq -r '"Would create " + .archive, (.paths[] | "  " + .)' <<<"$data"
    return 0
  fi
  j3w1zsh_execute_typed_callback "${J3W1ZSH_PLAN_ACTIONS[0]}" j3w1zsh_backup_execute "$archive" "${paths[@]}"
  [[ $J3W1ZSH_OUTPUT_MODE != json ]] || { j3w1zsh_json_envelope backup ok "$(jq -cn --arg id "$id" --arg archive "$archive" '{backup_id:$id,archive:$archive}')"; return; }
  j3w1zsh_note "Backup ID: $id"
  j3w1zsh_note "$archive"
}

j3w1zsh_restore_manifest_backup() {
  local backup_dir="$1"
  [[ -s $backup_dir/manifest.tsv ]] || j3w1zsh_die "Backup manifest is missing: $backup_dir"
  [[ ! -e $backup_dir/.restored ]] || j3w1zsh_die "This installer backup was already restored."
  local target saved relative displaced
  while IFS=$'\t' read -r target saved; do
    [[ -n $target && -n $saved ]] || continue
    j3w1zsh_validate_home_target "$target"
    if [[ $saved != __MISSING__ ]]; then
      case "$saved" in "$backup_dir"/*) ;; *) j3w1zsh_die "Backup manifest escapes its backup root." ;; esac
      [[ -e $saved || -L $saved ]] || j3w1zsh_die "Backup entry is missing: $saved"
    fi
  done <"$backup_dir/manifest.tsv"
  j3w1zsh_confirm "Restore installer backup $(basename -- "$backup_dir")?" || return 0
  while IFS=$'\t' read -r target saved; do
    [[ -n $target && -n $saved ]] || continue
    relative="${target#"$HOME"/}"
    if [[ -e $target || -L $target ]]; then
      displaced="$backup_dir/pre-restore/$relative"
      mkdir -p "$(dirname -- "$displaced")"
      mv -- "$target" "$displaced"
    fi
    if [[ $saved != __MISSING__ ]]; then
      mkdir -p "$(dirname -- "$target")"
      mv -- "$saved" "$target"
    fi
  done <"$backup_dir/manifest.tsv"
  : >"$backup_dir/.restored"
}

j3w1zsh_restore_archive() {
  local archive="$1"
  local entries=() entry
  mapfile -t entries < <(tar -tzf "$archive")
  ((${#entries[@]})) || j3w1zsh_die "Backup archive is empty: $archive"
  for entry in "${entries[@]}"; do
    [[ -n $entry && $entry != /* ]] || j3w1zsh_die "Backup archive contains an absolute path."
    case "/$entry/" in */../* | */./*) j3w1zsh_die "Backup archive contains path traversal: $entry" ;; esac
    case "$entry" in
    .zshrc | .tmux.conf | .config/nvim | .config/nvim/* | .config/j3w1zsh | .config/j3w1zsh/* | \
      .local/bin/tma | .local/bin/j3w1zsh-clipboard-copy | .local/bin/j3w1zsh) ;;
    *) j3w1zsh_die "Backup archive contains an unmanaged path: $entry" ;;
    esac
  done
  local staging
  mkdir -p "$J3W1ZSH_STATE_DIR/backups"
  j3w1zsh_create_ephemeral_dir staging backup-restore
  tar -C "$staging" -xzhf "$archive" --no-same-owner --no-same-permissions
  local unsafe="" link link_target resolved_link resolved_home resolved_repo
  unsafe="$(find "$staging" -mindepth 1 ! -type f ! -type d ! -type l -print -quit)"
  if [[ -n $unsafe ]]; then
    j3w1zsh_cleanup_ephemeral_dir "$staging" || j3w1zsh_die "Failed to clean the guarded restore staging directory."
    j3w1zsh_die "Backup archive contains an unsupported filesystem object."
  fi
  resolved_home="$(readlink -f -- "$HOME")"
  resolved_repo="$(readlink -f -- "$J3W1ZSH_REPO_ROOT")"
  while IFS= read -r -d '' link; do
    link_target="$(readlink -- "$link")"
    if [[ $link_target == /* ]]; then
      resolved_link="$(readlink -m -- "$link_target")"
    else
      resolved_link="$(readlink -m -- "$(dirname -- "$link")/$link_target")"
    fi
    case "$resolved_link" in
    "$resolved_home" | "$resolved_home"/* | "$resolved_repo" | "$resolved_repo"/*) ;;
    *)
      j3w1zsh_cleanup_ephemeral_dir "$staging" || j3w1zsh_die "Failed to clean the guarded restore staging directory."
      j3w1zsh_die "Backup archive contains a symlink outside HOME: ${link#"$staging"/}"
      ;;
    esac
  done < <(find "$staging" -type l -print0)
  if ! j3w1zsh_confirm "Restore configuration backup $(basename -- "$archive")?"; then
    j3w1zsh_cleanup_ephemeral_dir "$staging" || j3w1zsh_die "Failed to clean the guarded restore staging directory."
    return 0
  fi
  local recovery
  recovery="$J3W1ZSH_STATE_DIR/backups/pre-restore-$(date +%Y%m%d-%H%M%S-%N)"
  mkdir -p "$recovery"
  local top target
  for top in .zshrc .tmux.conf .config/nvim .config/j3w1zsh .local/bin/tma .local/bin/j3w1zsh-clipboard-copy .local/bin/j3w1zsh; do
    target="$HOME/$top"
    if [[ -e $target || -L $target ]]; then
      mkdir -p "$recovery/$(dirname -- "$top")"
      mv -- "$target" "$recovery/$top"
    fi
  done
  for top in .zshrc .tmux.conf .config/nvim .config/j3w1zsh .local/bin/tma .local/bin/j3w1zsh-clipboard-copy .local/bin/j3w1zsh; do
    [[ -e $staging/$top || -L $staging/$top ]] || continue
    mkdir -p "$(dirname -- "$HOME/$top")"
    mv -- "$staging/$top" "$HOME/$top"
  done
  j3w1zsh_cleanup_ephemeral_dir "$staging" || j3w1zsh_die "Failed to clean the guarded restore staging directory."
  j3w1zsh_note "Displaced pre-restore paths: $recovery"
}

j3w1zsh_restore_command() {
  local id=""
  while (($#)); do
    case "$1" in --dry-run) J3W1ZSH_DRY_RUN=1 ;; --*) j3w1zsh_usage_error "Unknown restore option: $1" ;; *) [[ -z $id ]] || j3w1zsh_usage_error "restore accepts at most one BACKUP_ID."; id="$1" ;; esac
    shift
  done
  local target=""
  if [[ -n $id ]]; then
    [[ $id == "$(basename -- "$id")" && $id != *..* ]] || j3w1zsh_usage_error "Invalid backup ID."
    if [[ -d $J3W1ZSH_STATE_DIR/backups/$id ]]; then target="$J3W1ZSH_STATE_DIR/backups/$id"; else target="$J3W1ZSH_STATE_DIR/backups/$id.tar.gz"; fi
  else
    target="$(find "$J3W1ZSH_STATE_DIR/backups" -mindepth 1 -maxdepth 1 \( -type f -name 'configuration-*.tar.gz' -o -type d -name '20*' \) -print 2>/dev/null | LC_ALL=C sort -r | head -n1)"
  fi
  [[ -n $target && ( -f $target || -d $target ) ]] || j3w1zsh_die "Backup was not found."
  j3w1zsh_plan_reset
  j3w1zsh_plan_add restore restore file-reconciliation recovery "" "$HOME" \
    "restore only validated managed paths from the selected backup" false true "" true "restored paths match the preserved backup manifest"
  if [[ $J3W1ZSH_DRY_RUN == 1 ]]; then
    [[ $J3W1ZSH_OUTPUT_MODE != json ]] || { j3w1zsh_json_envelope restore ok "$(jq -cn --arg backup "$target" '{backup:$backup,dry_run:true}')"; return; }
    printf 'Would restore: %s\n' "$target"
    return 0
  fi
  if [[ -d $target ]]; then
    j3w1zsh_execute_typed_callback "${J3W1ZSH_PLAN_ACTIONS[0]}" j3w1zsh_restore_manifest_backup "$target"
  else
    j3w1zsh_execute_typed_callback "${J3W1ZSH_PLAN_ACTIONS[0]}" j3w1zsh_restore_archive "$target"
  fi
}

j3w1zsh_reset_phase_execute() {
  j3w1zsh_clear_phase "$1"
}

j3w1zsh_reset_phase_command() {
  (($# == 1)) || j3w1zsh_usage_error "reset-phase requires exactly one PHASE."
  local requested="$1" phase valid=0
  for phase in "${J3W1ZSH_PHASES[@]}"; do [[ $phase != "$requested" ]] || valid=1; done
  ((valid == 1)) || j3w1zsh_usage_error "Unknown phase: $requested"
  j3w1zsh_plan_reset
  j3w1zsh_plan_add reset-phase reset-phase file-reconciliation state "" "$(j3w1zsh_phase_marker "$requested")" \
    "remove the selected phase marker so it can be reverified" false false "" true "only the named phase marker is absent"
  j3w1zsh_execute_typed_callback "${J3W1ZSH_PLAN_ACTIONS[0]}" j3w1zsh_reset_phase_execute "$requested"
  j3w1zsh_log "Reset phase $requested."
}
