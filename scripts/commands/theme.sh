#!/usr/bin/env bash

j3w1zsh_theme_command() {
  local subcommand="${1:-help}"
  (($# == 0)) || shift
  case "$subcommand" in
  list)
    (($# == 0)) || j3w1zsh_usage_error "theme list accepts no arguments."
    local themes
    themes="$(j3w1zsh_theme_list_json)"
    [[ $J3W1ZSH_OUTPUT_MODE != json ]] || { j3w1zsh_json_envelope theme-list ok "$themes"; return; }
    jq -r '.[] | .id + "\t" + .display_name' <<<"$themes"
    ;;
  show)
    (($# <= 1)) || j3w1zsh_usage_error "theme show accepts at most one name."
    j3w1zsh_resolve_theme "${1:-j3w1zsh}"
    local data
    data="$(jq -c . "$J3W1ZSH_RESOLVED_THEME_PATH")"
    [[ $J3W1ZSH_OUTPUT_MODE != json ]] || { j3w1zsh_json_envelope theme-show ok "$data"; return; }
    jq . <<<"$data"
    ;;
  current)
    (($# == 0)) || j3w1zsh_usage_error "theme current accepts no arguments."
    local manifest="$J3W1ZSH_CONFIG_DIR/generated/theme/manifest.json" data
    data='null'; [[ ! -f $manifest ]] || data="$(cat "$manifest")"
    [[ $J3W1ZSH_OUTPUT_MODE != json ]] || { j3w1zsh_json_envelope theme-current ok "$data"; return; }
    if [[ $data == null ]]; then
      printf 'no applied theme\n'
    else
      jq -r .id <<<"$data"
    fi
    ;;
  apply)
    (($# >= 1)) || j3w1zsh_usage_error "theme apply requires a name."
    local name="$1"; shift
    while (($#)); do
      case "$1" in --dry-run) J3W1ZSH_DRY_RUN=1 ;; *) j3w1zsh_usage_error "Unknown theme apply option: $1" ;; esac
      shift
    done
    j3w1zsh_resolve_theme "$name"
    j3w1zsh_plan_reset
    j3w1zsh_plan_add theme-apply theme-apply file-reconciliation theme "" "$J3W1ZSH_CONFIG_DIR/generated/theme" \
      "render the selected declarative theme" false false "" true "render manifest matches the selected theme digest"
    if [[ $J3W1ZSH_DRY_RUN == 1 ]]; then
      j3w1zsh_render_theme
    else
      j3w1zsh_execute_typed_callback "${J3W1ZSH_PLAN_ACTIONS[0]}" j3w1zsh_render_theme
    fi
    [[ $J3W1ZSH_OUTPUT_MODE != json ]] || j3w1zsh_json_envelope theme-apply ok "$(jq -cn --arg id "$J3W1ZSH_THEME" --argjson dry_run "$([[ $J3W1ZSH_DRY_RUN == 1 ]] && printf true || printf false)" '{id:$id,dry_run:$dry_run}')"
    ;;
  help | -h | --help) printf 'Usage: j3w1zsh theme list|show [NAME]|current|apply NAME [--dry-run] [--json]\n' ;;
  *) j3w1zsh_usage_error "Unknown theme command: $subcommand" ;;
  esac
}
