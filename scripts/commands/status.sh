#!/usr/bin/env bash

j3w1zsh_status_phase_selection() {
  local phase="$1" no_packages="$2" packages_only="$3"
  [[ $packages_only != true || $phase =~ ^(00-preflight|10-platform|20-packages)$ ]] || { printf 'unselected\n'; return; }
  case "$phase" in
  30-shell) j3w1zsh_preset_has_feature shell || { printf 'unselected\n'; return; } ;;
  50-theme) j3w1zsh_preset_has_feature host-theme || { printf 'unselected\n'; return; } ;;
  60-neovim) j3w1zsh_preset_has_feature neovim || { printf 'unselected\n'; return; } ;;
  70-codex)
    [[ $no_packages != true ]] || { printf 'unselected\n'; return; }
    [[ $J3W1ZSH_PLATFORM == wsl ]] || { printf 'inapplicable\n'; return; }
    j3w1zsh_preset_has_feature codex || { printf 'unselected\n'; return; }
    ;;
  80-github) j3w1zsh_preset_has_feature github || { printf 'unselected\n'; return; } ;;
  esac
  printf 'selected\n'
}

j3w1zsh_status_data_json() {
  local selection_marker="$J3W1ZSH_STATE_DIR/phases/00-preflight.json"
  local no_packages=false packages_only=false
  [[ ! -f $selection_marker ]] || {
    no_packages="$(jq -r '.no_packages // false' "$selection_marker")"
    packages_only="$(jq -r '.packages_only // false' "$selection_marker")"
  }
  local phases='[]' phase state marker selection
  for phase in "${J3W1ZSH_PHASES[@]}"; do
    selection="$(j3w1zsh_status_phase_selection "$phase" "$no_packages" "$packages_only")"
    state=pending
    [[ $selection == selected ]] || state="$selection"
    [[ $selection != selected ]] || { j3w1zsh_phase_done "$phase" && state=complete; }
    marker="$(j3w1zsh_phase_marker "$phase")"
    phases="$(jq -cn --argjson phases "$phases" --arg phase "$phase" --arg state "$state" --arg marker "$marker" '$phases + [{phase:$phase,state:$state,marker:$marker}]')"
  done
  jq -cn --arg version "$J3W1ZSH_VERSION" --arg commit "$(j3w1zsh_repo_commit)" \
    --arg platform "$J3W1ZSH_PLATFORM" --arg state_dir "$J3W1ZSH_STATE_DIR" --argjson phases "$phases" \
    '{version:$version,commit:$commit,platform:$platform,state_dir:$state_dir,phases:$phases}'
}

j3w1zsh_status_command() {
  (($# == 0)) || j3w1zsh_usage_error "status accepts no arguments."
  local marker="$J3W1ZSH_STATE_DIR/phases/00-preflight.json" preset_source=j3w1 theme_source=j3w1zsh workspace_source=""
  if [[ -f $marker ]]; then
    preset_source="$(jq -r '.preset_source // .preset // "j3w1"' "$marker")"
    theme_source="$(jq -r '.theme_source // .theme // "j3w1zsh"' "$marker")"
    workspace_source="$(jq -r '.workspace_source // ""' "$marker")"
    J3W1ZSH_NO_PACKAGES="$([[ $(jq -r '.no_packages // false' "$marker") == true ]] && printf 1 || printf 0)"
    J3W1ZSH_PACKAGES_ONLY="$([[ $(jq -r '.packages_only // false' "$marker") == true ]] && printf 1 || printf 0)"
  fi
  J3W1ZSH_SELECTED_WORKSPACE="$workspace_source"
  export J3W1ZSH_NO_PACKAGES J3W1ZSH_PACKAGES_ONLY J3W1ZSH_SELECTED_WORKSPACE
  j3w1zsh_resolve_preset "$preset_source"
  j3w1zsh_resolve_theme "$theme_source"
  local data
  data="$(j3w1zsh_status_data_json)"
  if [[ $J3W1ZSH_OUTPUT_MODE == json ]]; then
    j3w1zsh_json_envelope status ok "$data"
  else
    jq -r '"j3w1zsh " + .version + " (" + .commit[0:12] + ")\nPlatform: " + .platform + "\n\n" + ([.phases[] | (.phase + "\t" + .state)] | join("\n"))' <<<"$data"
  fi
}

j3w1zsh_platform_command() {
  (($# == 0)) || j3w1zsh_usage_error "platform accepts no arguments."
  if [[ $J3W1ZSH_OUTPUT_MODE == json ]]; then
    j3w1zsh_json_envelope platform ok "$(j3w1zsh_platform_json)"
  else
    j3w1zsh_platform_label
  fi
}

j3w1zsh_doctor_command() {
  (($# == 0)) || j3w1zsh_usage_error "doctor accepts no arguments."
  local marker="$J3W1ZSH_STATE_DIR/phases/00-preflight.json" preset_source=j3w1 no_packages=false
  if [[ -f $marker ]]; then
    preset_source="$(jq -r '.preset_source // .preset // "j3w1"' "$marker")"
    no_packages="$(jq -r '.no_packages // false' "$marker")"
  fi
  j3w1zsh_resolve_preset "$preset_source"
  local required=(bash git jq) checks='[]' command_name ok overall=ok
  j3w1zsh_preset_has_feature shell && required+=(zsh)
  j3w1zsh_preset_has_feature tmux && required+=(tmux)
  j3w1zsh_preset_has_feature neovim && required+=(nvim)
  j3w1zsh_preset_has_feature github && required+=(gh)
  j3w1zsh_preset_has_feature remote && required+=(ssh)
  if [[ $no_packages != true && $J3W1ZSH_PLATFORM == wsl ]] && j3w1zsh_preset_has_feature codex; then
    required+=(codex)
  fi
  for command_name in "${required[@]}"; do
    ok=false
    j3w1zsh_have "$command_name" && ok=true
    [[ $ok == true ]] || overall=error
    checks="$(jq -cn --argjson checks "$checks" --arg name "$command_name" --argjson ok "$ok" '$checks + [{name:$name,ok:$ok}]')"
  done
  if [[ $J3W1ZSH_PLATFORM == wsl ]]; then
    ok=false
    j3w1zsh_wsl_interop_healthy && ok=true
    [[ $ok == true ]] || overall=error
    checks="$(jq -cn --argjson checks "$checks" --argjson ok "$ok" '$checks + [{name:"wsl-interop",ok:$ok}]')"
  fi
  ok=false
  if git -C "$J3W1ZSH_REPO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1 &&
    git -C "$J3W1ZSH_REPO_ROOT" rev-parse --verify '@{upstream}^{commit}' >/dev/null 2>&1; then
    ok=true
  else
    overall=error
  fi
  checks="$(jq -cn --argjson checks "$checks" --argjson ok "$ok" '$checks + [{name:"git-upstream",ok:$ok}]')"
  local data
  data="$(jq -cn --arg platform "$J3W1ZSH_PLATFORM" --argjson checks "$checks" '{platform:$platform,checks:$checks}')"
  if [[ $J3W1ZSH_OUTPUT_MODE == json ]]; then
    j3w1zsh_json_envelope doctor "$overall" "$data"
  else
    jq -r '.checks[] | (if .ok then "[ok] " else "[missing] " end) + .name' <<<"$data"
  fi
  [[ $overall == ok ]]
}
