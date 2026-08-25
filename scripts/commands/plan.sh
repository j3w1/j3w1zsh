#!/usr/bin/env bash

j3w1zsh_discover_workspace_file() {
  local root candidate
  root="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || true)"
  [[ -n $root ]] || root="$PWD"
  candidate="$root/j3w1zsh.workspace.json"
  if [[ -f $candidate ]]; then
    printf '%s\n' "$candidate"
  fi
  return 0
}

j3w1zsh_plan_command() {
  local file="" preset=j3w1 theme=""
  while (($#)); do
    case "$1" in
    --preset) shift; (($#)) || j3w1zsh_usage_error "--preset requires a name or file."; preset="$1" ;;
    --theme) shift; (($#)) || j3w1zsh_usage_error "--theme requires a name."; theme="$1" ;;
    --dry-run) ;;
    -h | --help) j3w1zsh_help_plan; return 0 ;;
    --*) j3w1zsh_usage_error "Unknown plan option: $1" ;;
    *) [[ -z $file ]] || j3w1zsh_usage_error "plan accepts at most one workspace file."; file="$1" ;;
    esac
    shift
  done
  [[ -n $file ]] || file="$(j3w1zsh_discover_workspace_file)"
  if [[ -n $file ]]; then
    [[ -f $file && ! -L $file ]] || j3w1zsh_die "Workspace profile is not a regular file: $file"
    J3W1ZSH_SELECTED_WORKSPACE="$(readlink -f -- "$file")"
  fi
  J3W1ZSH_PRESET="$preset"
  J3W1ZSH_THEME_OVERRIDE="$theme"
  export J3W1ZSH_SELECTED_WORKSPACE J3W1ZSH_PRESET J3W1ZSH_THEME_OVERRIDE
  j3w1zsh_prepare_selection 0
  if [[ $J3W1ZSH_OUTPUT_MODE == json ]]; then
    j3w1zsh_json_envelope plan ok "$(jq -cn --arg platform "$J3W1ZSH_PLATFORM" --arg preset "$J3W1ZSH_PRESET" --arg theme "$J3W1ZSH_THEME" --arg workspace "$J3W1ZSH_SELECTED_WORKSPACE" --arg digest "$(j3w1zsh_plan_digest)" --argjson actions "$(j3w1zsh_plan_json)" '{platform:$platform,preset:$preset,theme:$theme,workspace:(if $workspace=="" then null else $workspace end),plan_digest:$digest,actions:$actions}')"
  else
    j3w1zsh_plan_render_human
  fi
}
