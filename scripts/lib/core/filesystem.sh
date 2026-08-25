#!/usr/bin/env bash

if ! declare -p J3W1ZSH_EPHEMERAL_KINDS >/dev/null 2>&1; then
  declare -gA J3W1ZSH_EPHEMERAL_KINDS=()
  declare -gA J3W1ZSH_EPHEMERAL_OWNERS=()
fi

j3w1zsh_ephemeral_spec() {
  local output_parent="$1" output_prefix="$2" kind="$3" spec_parent spec_prefix
  [[ $output_parent =~ ^[A-Za-z_][A-Za-z0-9_]*$ && $output_prefix =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] ||
    j3w1zsh_die "Invalid ephemeral specification output variable."
  case "$kind" in
  update-relation)
    spec_parent="${TMPDIR:-/tmp}"
    spec_prefix='j3w1zsh-update-relation'
    ;;
  wiki-status)
    spec_parent="${TMPDIR:-/tmp}"
    spec_prefix='j3w1zsh-wiki-status'
    ;;
  wiki-context)
    spec_parent="${TMPDIR:-/tmp}"
    spec_prefix='j3w1zsh-wiki-context'
    ;;
  wiki-checkout-pinned)
    spec_parent="$J3W1ZSH_STATE_DIR/wiki/pinned"
    spec_prefix='.wiki-checkout'
    ;;
  wiki-checkout-latest)
    spec_parent="$J3W1ZSH_STATE_DIR/wiki/latest"
    spec_prefix='.wiki-checkout'
    ;;
  backup-restore)
    spec_parent="$J3W1ZSH_STATE_DIR/backups"
    spec_prefix='.restore'
    ;;
  theme-render)
    spec_parent="$J3W1ZSH_CONFIG_DIR/generated"
    spec_prefix='.theme'
    ;;
  *) j3w1zsh_die "Unknown ephemeral directory kind: $kind" ;;
  esac
  printf -v "$output_parent" '%s' "$spec_parent"
  printf -v "$output_prefix" '%s' "$spec_prefix"
}

j3w1zsh_ephemeral_basename_allowed() {
  local kind="$1" name="$2" parent prefix
  j3w1zsh_ephemeral_spec parent prefix "$kind"
  [[ $name == "$prefix".?????? ]]
}

j3w1zsh_ephemeral_install_exit_trap() {
  if [[ ${J3W1ZSH_EPHEMERAL_TRAP_OWNER:-} == "$BASHPID" ]]; then
    return 0
  fi
  [[ -z $(trap -p EXIT) ]] || j3w1zsh_die "Refusing to replace an existing EXIT trap while registering an ephemeral directory."
  J3W1ZSH_EPHEMERAL_TRAP_OWNER="$BASHPID"
  trap j3w1zsh_cleanup_ephemeral_dirs_on_exit EXIT
}

j3w1zsh_create_ephemeral_dir() {
  local output_name="$1" kind="$2" parent prefix resolved_parent created resolved_created marker owner
  [[ $output_name =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || j3w1zsh_die "Invalid ephemeral directory output variable."
  j3w1zsh_ephemeral_spec parent prefix "$kind"
  [[ $parent == /* && -d $parent ]] || j3w1zsh_die "Ephemeral directory parent is not an absolute existing directory: $parent"
  resolved_parent="$(readlink -f -- "$parent")"
  [[ -n $resolved_parent && -d $resolved_parent ]] || j3w1zsh_die "Ephemeral directory parent cannot be resolved: $parent"
  j3w1zsh_ephemeral_install_exit_trap
  created="$(mktemp -d -- "$resolved_parent/$prefix.XXXXXX")"
  resolved_created="$(readlink -m -- "$created")"
  [[ $created == "$resolved_created" && -d $created && ! -L $created ]] ||
    j3w1zsh_die "Ephemeral directory creation was not isolated: $created"
  [[ $(dirname -- "$resolved_created") == "$resolved_parent" ]] ||
    j3w1zsh_die "Ephemeral directory escaped its guarded parent: $created"
  j3w1zsh_ephemeral_basename_allowed "$kind" "$(basename -- "$resolved_created")" ||
    j3w1zsh_die "Ephemeral directory has an unexpected name: $created"
  marker="$resolved_created/.j3w1zsh-ephemeral"
  owner="$BASHPID"
  (umask 077; printf 'j3w1zsh:%s:%s\n' "$owner" "$kind" >"$marker")
  chmod 400 "$marker"
  J3W1ZSH_EPHEMERAL_KINDS["$resolved_created"]="$kind"
  J3W1ZSH_EPHEMERAL_OWNERS["$resolved_created"]="$owner"
  printf -v "$output_name" '%s' "$resolved_created"
}

j3w1zsh_validate_registered_ephemeral_dir() {
  local path="$1" kind parent prefix resolved_parent resolved_path marker marker_value
  [[ ${J3W1ZSH_EPHEMERAL_KINDS[$path]+registered} == registered ]] || {
    printf 'ERROR: Refusing to remove an unregistered ephemeral directory: %s\n' "$path" >&2
    return 1
  }
  [[ ${J3W1ZSH_EPHEMERAL_OWNERS[$path]:-} == "$BASHPID" ]] || {
    printf 'ERROR: Refusing to remove an ephemeral directory registered by another process: %s\n' "$path" >&2
    return 1
  }
  kind="${J3W1ZSH_EPHEMERAL_KINDS[$path]}"
  j3w1zsh_ephemeral_spec parent prefix "$kind"
  resolved_parent="$(readlink -f -- "$parent")"
  resolved_path="$(readlink -m -- "$path")"
  if [[ $path != "$resolved_path" || ! -d $path || -L $path || $(dirname -- "$resolved_path") != "$resolved_parent" ]] ||
    ! j3w1zsh_ephemeral_basename_allowed "$kind" "$(basename -- "$resolved_path")"; then
    printf 'ERROR: Refusing to remove an ephemeral directory outside its exact guarded shape: %s\n' "$path" >&2
    return 1
  fi
  marker="$path/.j3w1zsh-ephemeral"
  if [[ ! -f $marker || -L $marker ]]; then
    printf 'ERROR: Refusing to remove an ephemeral directory without its regular ownership marker: %s\n' "$path" >&2
    return 1
  fi
  IFS= read -r marker_value <"$marker" || return 1
  if [[ $marker_value != "j3w1zsh:$BASHPID:$kind" ]]; then
    printf 'ERROR: Refusing to remove an ephemeral directory with an invalid ownership marker: %s\n' "$path" >&2
    return 1
  fi
}

j3w1zsh_cleanup_ephemeral_dir() {
  local path="$1"
  j3w1zsh_validate_registered_ephemeral_dir "$path" || return 1
  rm -rf -- "$path"
  [[ ! -e $path && ! -L $path ]] || return 1
  unset 'J3W1ZSH_EPHEMERAL_KINDS[$path]' 'J3W1ZSH_EPHEMERAL_OWNERS[$path]'
}

j3w1zsh_ephemeral_destination_allowed() {
  local kind="$1" destination="$2" resolved_destination resolved_root relative topic commit
  resolved_destination="$(readlink -m -- "$destination")"
  [[ $destination == "$resolved_destination" ]] || return 1
  case "$kind" in
  theme-render)
    [[ $resolved_destination == "$(readlink -m -- "$J3W1ZSH_CONFIG_DIR/generated/theme")" ]]
    ;;
  wiki-checkout-pinned | wiki-checkout-latest)
    resolved_root="$(readlink -m -- "$J3W1ZSH_STATE_DIR/wiki/${kind#wiki-checkout-}")"
    [[ $(dirname -- "$resolved_destination") == "$resolved_root" && $(basename -- "$resolved_destination") =~ ^[0-9a-f]{40}$ ]]
    ;;
  wiki-context)
    resolved_root="$(readlink -m -- "$J3W1ZSH_STATE_DIR/wiki/context")"
    [[ $resolved_destination == "$resolved_root/"* ]] || return 1
    relative="${resolved_destination#"$resolved_root"/}"
    [[ $relative == */* && $relative != */*/* ]] || return 1
    topic="${relative%%/*}"
    commit="${relative#*/}"
    [[ $topic =~ ^[a-z0-9][a-z0-9-]*$ && $commit =~ ^[0-9a-f]{40}$ ]]
    ;;
  *) return 1 ;;
  esac
}

j3w1zsh_promote_ephemeral_dir() {
  local path="$1" destination="$2" kind marker
  j3w1zsh_validate_registered_ephemeral_dir "$path" || return 1
  kind="${J3W1ZSH_EPHEMERAL_KINDS[$path]}"
  j3w1zsh_ephemeral_destination_allowed "$kind" "$destination" ||
    j3w1zsh_die "Refusing to promote an ephemeral directory to an unapproved destination: $destination"
  [[ ! -e $destination && ! -L $destination ]] ||
    j3w1zsh_die "Refusing to replace an existing destination while promoting an ephemeral directory: $destination"
  mv -- "$path" "$destination"
  marker="$destination/.j3w1zsh-ephemeral"
  [[ -f $marker && ! -L $marker ]] || j3w1zsh_die "Promoted directory lost its ownership marker: $destination"
  rm -f -- "$marker"
  unset 'J3W1ZSH_EPHEMERAL_KINDS[$path]' 'J3W1ZSH_EPHEMERAL_OWNERS[$path]'
}

j3w1zsh_cleanup_ephemeral_dirs_on_exit() {
  local status=$? path cleanup_failed=0
  trap - EXIT
  for path in "${!J3W1ZSH_EPHEMERAL_KINDS[@]}"; do
    [[ ${J3W1ZSH_EPHEMERAL_OWNERS[$path]:-} == "$BASHPID" ]] || continue
    j3w1zsh_cleanup_ephemeral_dir "$path" || cleanup_failed=1
  done
  if ((status == 0 && cleanup_failed != 0)); then
    status=$J3W1ZSH_EXIT_FAILURE
  fi
  exit "$status"
}

j3w1zsh_validate_home_target() {
  local target="$1"
  case "$target" in
  "$HOME" | "$HOME"/*) ;;
  *) j3w1zsh_die "Refusing to manage a path outside HOME: $target" ;;
  esac
  [[ $target == "$HOME" ]] && return 0
  local parent resolved_parent resolved_home
  parent="$(dirname -- "$target")"
  resolved_home="$(readlink -f -- "$HOME")"
  resolved_parent="$(readlink -m -- "$parent")"
  case "$resolved_parent" in
  "$resolved_home" | "$resolved_home"/*) ;;
  *) j3w1zsh_die "Refusing a managed path through an ancestor outside HOME: $target" ;;
  esac
}

j3w1zsh_begin_backup() {
  [[ -n ${J3W1ZSH_BACKUP_DIR:-} ]] && return 0
  local stamp
  stamp="$(date +%Y%m%d-%H%M%S-%N)"
  J3W1ZSH_BACKUP_DIR="$J3W1ZSH_STATE_DIR/backups/$stamp"
  export J3W1ZSH_BACKUP_DIR
  if [[ $J3W1ZSH_DRY_RUN != 1 ]]; then
    mkdir -p "$J3W1ZSH_BACKUP_DIR"
    : >"$J3W1ZSH_BACKUP_DIR/manifest.tsv"
    chmod 700 "$J3W1ZSH_BACKUP_DIR"
    chmod 600 "$J3W1ZSH_BACKUP_DIR/manifest.tsv"
  fi
}

j3w1zsh_backup_path() {
  local target="$1"
  j3w1zsh_validate_home_target "$target"
  [[ -e $target || -L $target ]] || return 0
  j3w1zsh_begin_backup
  local relative destination
  relative="${target#"$HOME"/}"
  destination="$J3W1ZSH_BACKUP_DIR/$relative"
  j3w1zsh_log "Backing up $target"
  j3w1zsh_run mkdir -p "$(dirname -- "$destination")"
  j3w1zsh_run mv -- "$target" "$destination"
  if [[ $J3W1ZSH_DRY_RUN != 1 ]]; then
    printf '%s\t%s\n' "$target" "$destination" >>"$J3W1ZSH_BACKUP_DIR/manifest.tsv"
  fi
}

j3w1zsh_link_managed() {
  local source="$1"
  local target="$2"
  j3w1zsh_validate_home_target "$target"
  [[ -e $source || -L $source ]] || j3w1zsh_die "Managed source is missing: $source"
  if [[ -L $target ]] && [[ $(readlink -f -- "$target") == "$(readlink -f -- "$source")" ]]; then
    j3w1zsh_note "Already linked: $target"
    return 0
  fi
  if [[ -e $target || -L $target ]]; then
    j3w1zsh_backup_path "$target"
  else
    j3w1zsh_begin_backup
    if [[ $J3W1ZSH_DRY_RUN != 1 ]]; then
      printf '%s\t%s\n' "$target" __MISSING__ >>"$J3W1ZSH_BACKUP_DIR/manifest.tsv"
    fi
  fi
  j3w1zsh_log "Linking $target"
  j3w1zsh_run mkdir -p "$(dirname -- "$target")"
  j3w1zsh_run ln -s -- "$source" "$target"
}

j3w1zsh_write_if_missing() {
  local target="$1"
  local source="$2"
  j3w1zsh_validate_home_target "$target"
  if [[ -e $target || -L $target ]]; then
    j3w1zsh_note "Preserving existing file: $target"
    return 0
  fi
  j3w1zsh_run mkdir -p "$(dirname -- "$target")"
  j3w1zsh_run cp -- "$source" "$target"
}

j3w1zsh_set_zsh_setting() {
  local key="$1"
  local value="$2"
  local settings="$J3W1ZSH_CONFIG_DIR/settings.zsh"
  [[ $key =~ ^J3W1ZSH_[A-Z0-9_]+$ ]] || j3w1zsh_die "Invalid setting name: $key"
  [[ $value != *$'\n'* && $value != *"'"* ]] || j3w1zsh_die "Setting contains unsupported characters: $key"
  [[ ! -L $settings ]] || j3w1zsh_die "Refusing to update a symlinked settings file: $settings"
  if [[ $J3W1ZSH_DRY_RUN == 1 ]]; then
    j3w1zsh_note "Would set $key in $settings."
    return 0
  fi
  mkdir -p "$J3W1ZSH_CONFIG_DIR"
  local temporary
  temporary="$(mktemp "$J3W1ZSH_CONFIG_DIR/.settings.XXXXXX")"
  if [[ -f $settings ]]; then
    awk -v key="$key" '$0 !~ "^export " key "=" { print }' "$settings" >"$temporary"
  fi
  printf "export %s='%s'\n" "$key" "$value" >>"$temporary"
  chmod 600 "$temporary"
  mv -- "$temporary" "$settings"
}
