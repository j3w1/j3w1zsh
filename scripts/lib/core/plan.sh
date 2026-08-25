#!/usr/bin/env bash

declare -ag J3W1ZSH_PLAN_ACTIONS=()

j3w1zsh_plan_reset() {
  J3W1ZSH_PLAN_ACTIONS=()
}

j3w1zsh_plan_add() {
  local id="$1" phase="$2" kind="$3" layer="$4" manager="$5" destination="$6"
  local reason="$7" privilege="$8" confirmation="$9" checkpoint="${10}" mutation="${11}" verification="${12}"
  case "$kind" in
  package-operation | file-reconciliation | host-adapter | direct-argv-lifecycle | manual-checkpoint | verification) ;;
  *) j3w1zsh_die "Invalid planned action kind: $kind" ;;
  esac
  local action
  action="$(jq -cn \
    --arg id "$id" --arg phase "$phase" --arg kind "$kind" --arg platform "$J3W1ZSH_PLATFORM" \
    --arg layer "$layer" --arg manager "$manager" --arg destination "$destination" --arg reason "$reason" \
    --argjson requires_privilege "$privilege" --argjson requires_confirmation "$confirmation" \
    --arg checkpoint "$checkpoint" --argjson mutation "$mutation" --arg verification "$verification" \
    '{id:$id,phase:$phase,kind:$kind,platform:$platform,source_layer:$layer,package_manager:(if $manager=="" then null else $manager end),managed_destination:(if $destination=="" then null else $destination end),reason:$reason,requires_privilege:$requires_privilege,requires_confirmation:$requires_confirmation,user_owned_checkpoint:(if $checkpoint=="" then null else $checkpoint end),mutation:$mutation,verification_rule:$verification}')"
  J3W1ZSH_PLAN_ACTIONS+=("$action")
}

j3w1zsh_build_base_plan() {
  j3w1zsh_plan_reset
  j3w1zsh_plan_add preflight 00-preflight verification core "" "" \
    "validate the selected platform and safety boundary" false false "" false "platform and repository inputs validate"
  if [[ $J3W1ZSH_PACKAGES_ONLY == 1 ]]; then
    j3w1zsh_plan_add platform 10-platform verification "platform-$J3W1ZSH_PLATFORM" "" "" \
      "validate platform package-manager ownership without host reconciliation" false false "" false "platform package prerequisites validate"
  elif [[ $J3W1ZSH_PLATFORM == wsl ]]; then
    j3w1zsh_plan_add wsl-host 10-platform host-adapter platform-wsl "" /etc/wsl.conf \
      "reconcile the bounded WSL 2 host adapter" true true wsl-restart true "WSL 2 systemd and interop state validate"
  else
    j3w1zsh_plan_add platform 10-platform verification "platform-$J3W1ZSH_PLATFORM" "" "" \
      "validate platform-owned host behavior" false false "" false "platform adapter prerequisites validate"
  fi
  local manager manager_packages npm_packages pip_packages
  manager="$(j3w1zsh_package_manager_for_platform)"
  manager_packages="$(j3w1zsh_packages_for_manager_json "$manager")"
  npm_packages="$(j3w1zsh_packages_for_manager_json npm_global)"
  pip_packages="$(j3w1zsh_packages_for_manager_json pip_user)"
  if [[ $J3W1ZSH_NO_PACKAGES != 1 ]]; then
    (($(jq length <<<"$manager_packages") == 0)) || j3w1zsh_plan_add "$manager-packages" 20-packages package-operation preset "$manager" "" \
      "reconcile $(jq length <<<"$manager_packages") required platform packages" "$([[ $manager == pacman ]] && printf true || printf false)" true "" true "every named package is installed"
    (($(jq length <<<"$npm_packages") == 0)) || j3w1zsh_plan_add npm-packages 20-packages package-operation preset npm_global "" \
      "reconcile $(jq length <<<"$npm_packages") required npm packages" "$([[ $J3W1ZSH_PLATFORM == termux ]] && printf false || printf true)" true "" true "every named package is installed"
    (($(jq length <<<"$pip_packages") == 0)) || j3w1zsh_plan_add python-packages 20-packages package-operation preset pip_user "" \
      "reconcile $(jq length <<<"$pip_packages") required Python user packages" false false "" true "every named package is installed"
  else
    j3w1zsh_plan_add package-availability 20-packages verification preset "" "" \
      "report selected package prerequisites without acquiring them" false false "" false \
      "missing prerequisites are reported and no package manager runs"
  fi
  if [[ $J3W1ZSH_PACKAGES_ONLY != 1 ]]; then
    if j3w1zsh_preset_has_feature shell; then
      j3w1zsh_plan_add shell 30-shell file-reconciliation preset "" "$HOME/.oh-my-zsh" \
        "reconcile the pinned shell framework and login shell" "$([[ $J3W1ZSH_PLATFORM == termux ]] && printf false || printf true)" true "" true "pinned framework and login shell validate"
    fi
    j3w1zsh_plan_add config 40-config file-reconciliation core "" "$HOME" \
      "reconcile selected home configuration with conflict backups" false false "" true "all selected links resolve into the checkout"
    if j3w1zsh_preset_has_feature host-theme; then
      j3w1zsh_plan_add theme 50-theme file-reconciliation theme "" "$J3W1ZSH_CONFIG_DIR/generated/theme" \
        "render declarative theme artifacts" false false "" true "render manifest matches the source theme digest"
    fi
    if j3w1zsh_preset_has_feature neovim; then
      j3w1zsh_plan_add neovim 60-neovim file-reconciliation preset "" "$HOME/.local/state/nvim/j3w1zsh" \
        "reconcile the reviewed Neovim runtime lock and spell files" false false "" true "headless Neovim configuration validates"
    fi
    if [[ $J3W1ZSH_NO_PACKAGES != 1 ]] && j3w1zsh_preset_has_feature codex && [[ $J3W1ZSH_PLATFORM == wsl ]]; then
      j3w1zsh_plan_add codex 70-codex host-adapter preset "" "$HOME/.codex" \
        "install the pinned official Codex CLI without replacing user settings" false true codex-login true "official CLI version and user-owned login state are reported"
    fi
    if j3w1zsh_preset_has_feature github; then
      j3w1zsh_plan_add github 80-github host-adapter preset "" "$HOME/.ssh" \
        "configure user-owned Git and GitHub access interactively" false true github-login true "Git identity and GitHub authentication are reported"
    fi
    j3w1zsh_plan_add verify 90-verify verification core "" "" \
      "verify every selected action before recording completion" false false "" false "selected command, links, theme, tmux and Neovim checks pass"
  fi
}

j3w1zsh_plan_json() {
  local output='[]' action
  for action in "${J3W1ZSH_PLAN_ACTIONS[@]}"; do
    output="$(jq -cn --argjson output "$output" --argjson action "$action" '$output + [$action]')"
  done
  printf '%s\n' "$output"
}

j3w1zsh_plan_digest() {
  j3w1zsh_plan_json | sha256sum | awk '{print $1}'
}

j3w1zsh_plan_render_human() {
  local action
  printf 'Plan for %s using preset %s and theme %s\n\n' "$(j3w1zsh_platform_label)" "$J3W1ZSH_PRESET" "$J3W1ZSH_THEME"
  for action in "${J3W1ZSH_PLAN_ACTIONS[@]}"; do
    jq -r '"  " + .phase + "  " + .kind + "  " + .reason + (if .mutation then " [mutation]" else " [read-only]" end)' <<<"$action"
  done
}

j3w1zsh_execute_typed_callback() {
  local action="$1" callback="$2"
  shift 2
  jq -e --arg platform "$J3W1ZSH_PLATFORM" '
    type == "object" and .platform == $platform and (.mutation | type == "boolean") and
    (.kind == "package-operation" or .kind == "file-reconciliation" or
     .kind == "host-adapter" or .kind == "direct-argv-lifecycle" or .kind == "verification")
  ' <<<"$action" >/dev/null || j3w1zsh_die "Refusing an invalid typed action."
  declare -F "$callback" >/dev/null || j3w1zsh_die "Typed action adapter is missing: $callback"
  "$callback" "$@"
}
