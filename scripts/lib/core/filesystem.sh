#!/usr/bin/env bash

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
