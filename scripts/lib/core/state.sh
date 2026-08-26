#!/usr/bin/env bash

j3w1zsh_ensure_dirs() {
  [[ $J3W1ZSH_DRY_RUN == 1 ]] && return 0
  mkdir -p \
    "$J3W1ZSH_STATE_DIR/phases" \
    "$J3W1ZSH_STATE_DIR/manual" \
    "$J3W1ZSH_STATE_DIR/backups" \
    "$J3W1ZSH_STATE_DIR/update-recovery" \
    "$J3W1ZSH_STATE_DIR/migrations" \
    "$J3W1ZSH_STATE_DIR/packages" \
    "$J3W1ZSH_STATE_DIR/workspaces" \
    "$J3W1ZSH_STATE_DIR/wiki" \
    "$J3W1ZSH_CONFIG_DIR" \
    "$J3W1ZSH_CACHE_DIR"
  chmod 700 "$J3W1ZSH_STATE_DIR" "$J3W1ZSH_CONFIG_DIR" "$J3W1ZSH_CACHE_DIR"
}

j3w1zsh_repo_commit() {
  git -C "$J3W1ZSH_REPO_ROOT" rev-parse HEAD 2>/dev/null || printf 'uncommitted\n'
}

j3w1zsh_input_digest() {
  local phase="$1"
  local preset_path="${J3W1ZSH_RESOLVED_PRESET_PATH:-$J3W1ZSH_PRESET}"
  local theme_path="${J3W1ZSH_RESOLVED_THEME_PATH:-$J3W1ZSH_THEME}"
  local package_overrides
  package_overrides="$J3W1ZSH_CONFIG_DIR/packages.json"
  {
    printf '%s\0' "$J3W1ZSH_VERSION" "$J3W1ZSH_PLATFORM" "$phase" "$preset_path" "$theme_path" \
      "$J3W1ZSH_NO_PACKAGES" "$J3W1ZSH_PACKAGES_ONLY" "$(j3w1zsh_repo_commit)"
    [[ -f $preset_path ]] && sha256sum "$preset_path"
    [[ -f $theme_path ]] && sha256sum "$theme_path"
    case "$phase" in
    20-packages | 90-verify)
      [[ -f $package_overrides && ! -L $package_overrides ]] && sha256sum "$package_overrides"
      ;;
    esac
    case "$phase" in
    60-neovim | 90-verify)
      sha256sum "$(j3w1zsh_neovim_tracked_lock_path)"
      ;;
    esac
    [[ -n $J3W1ZSH_SELECTED_WORKSPACE && -f $J3W1ZSH_SELECTED_WORKSPACE ]] && sha256sum "$J3W1ZSH_SELECTED_WORKSPACE"
  } | sha256sum | awk '{print $1}'
}

j3w1zsh_phase_marker() {
  printf '%s/phases/%s.json\n' "$J3W1ZSH_STATE_DIR" "$1"
}

j3w1zsh_phase_done() {
  local phase="$1"
  local marker digest
  marker="$(j3w1zsh_phase_marker "$phase")"
  [[ -f $marker ]] || return 1
  digest="$(j3w1zsh_input_digest "$phase")"
  jq -e \
    --arg phase "$phase" \
    --arg platform "$J3W1ZSH_PLATFORM" \
    --arg digest "$digest" \
    '.state_schema_version == 1 and .phase == $phase and .platform == $platform and .input_digest == $digest and (.verified_commit | type == "string")' \
    "$marker" >/dev/null 2>&1
}

j3w1zsh_mark_phase() {
  local phase="$1"
  if [[ $J3W1ZSH_DRY_RUN == 1 ]]; then
    j3w1zsh_note "Would mark phase $phase complete after verification."
    return 0
  fi
  j3w1zsh_ensure_dirs
  local marker temporary
  marker="$(j3w1zsh_phase_marker "$phase")"
  temporary="$(mktemp "$J3W1ZSH_STATE_DIR/phases/.${phase}.XXXXXX")"
  jq -cn \
    --argjson state_schema_version "$J3W1ZSH_STATE_SCHEMA_VERSION" \
    --arg product_version "$J3W1ZSH_VERSION" \
    --arg phase "$phase" \
    --arg platform "$J3W1ZSH_PLATFORM" \
    --arg preset "$J3W1ZSH_PRESET" \
    --arg theme "$J3W1ZSH_THEME" \
    --arg preset_source "${J3W1ZSH_RESOLVED_PRESET_PATH:-}" \
    --arg theme_source "${J3W1ZSH_RESOLVED_THEME_PATH:-}" \
    --arg workspace_source "${J3W1ZSH_SELECTED_WORKSPACE:-}" \
    --argjson no_packages "$([[ $J3W1ZSH_NO_PACKAGES == 1 ]] && printf true || printf false)" \
    --argjson packages_only "$([[ $J3W1ZSH_PACKAGES_ONLY == 1 ]] && printf true || printf false)" \
    --arg input_digest "$(j3w1zsh_input_digest "$phase")" \
    --arg completed_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg verified_commit "$(j3w1zsh_repo_commit)" \
    '{state_schema_version:$state_schema_version,product_version:$product_version,phase:$phase,platform:$platform,preset:$preset,theme:$theme,preset_source:$preset_source,theme_source:$theme_source,workspace_source:$workspace_source,no_packages:$no_packages,packages_only:$packages_only,input_digest:$input_digest,completed_at:$completed_at,verified_commit:$verified_commit}' \
    >"$temporary"
  chmod 600 "$temporary"
  mv -- "$temporary" "$marker"
}

j3w1zsh_clear_phase() {
  local marker
  marker="$(j3w1zsh_phase_marker "$1")"
  [[ -e $marker ]] || return 0
  j3w1zsh_run rm -- "$marker"
}

j3w1zsh_manual_marker() {
  [[ $1 =~ ^[a-z0-9][a-z0-9-]*$ ]] || j3w1zsh_die "Invalid checkpoint: $1"
  printf '%s/manual/%s.json\n' "$J3W1ZSH_STATE_DIR" "$1"
}

j3w1zsh_manual_pending() {
  [[ -f $(j3w1zsh_manual_marker "$1") ]]
}

j3w1zsh_mark_manual_pending() {
  local checkpoint="$1"
  local message="$2"
  if [[ $J3W1ZSH_DRY_RUN == 1 ]]; then
    j3w1zsh_note "Would pause at manual checkpoint: $checkpoint"
    return 0
  fi
  j3w1zsh_ensure_dirs
  local marker temporary
  marker="$(j3w1zsh_manual_marker "$checkpoint")"
  temporary="$(mktemp "$J3W1ZSH_STATE_DIR/manual/.${checkpoint}.XXXXXX")"
  jq -cn --arg checkpoint "$checkpoint" --arg message "$message" \
    --arg created_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{checkpoint:$checkpoint,message:$message,created_at:$created_at}' >"$temporary"
  chmod 600 "$temporary"
  mv -- "$temporary" "$marker"
}

j3w1zsh_clear_manual() {
  local marker
  marker="$(j3w1zsh_manual_marker "$1")"
  [[ -e $marker ]] || return 0
  j3w1zsh_run rm -- "$marker"
}
