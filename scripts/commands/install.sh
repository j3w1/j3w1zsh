#!/usr/bin/env bash

readonly J3W1ZSH_PHASES=(
  00-preflight
  10-platform
  20-packages
  30-shell
  40-config
  50-theme
  60-neovim
  70-codex
  80-github
  90-verify
)

j3w1zsh_phase_function() {
  printf 'phase_%s\n' "${1//-/_}"
}

j3w1zsh_load_phases() {
  local phase
  for phase in "${J3W1ZSH_PHASES[@]}"; do
    # shellcheck source=/dev/null
    source "$J3W1ZSH_REPO_ROOT/scripts/phases/$phase.sh"
  done
}

j3w1zsh_prepare_selection() {
  local require_trusted_workspace="${1:-1}"
  j3w1zsh_platform_preflight
  j3w1zsh_resolve_preset "$J3W1ZSH_PRESET"
  [[ -z ${J3W1ZSH_THEME_OVERRIDE:-} ]] || J3W1ZSH_THEME="$J3W1ZSH_THEME_OVERRIDE"
  j3w1zsh_resolve_theme "$J3W1ZSH_THEME"
  j3w1zsh_build_base_plan
  if [[ -n $J3W1ZSH_SELECTED_WORKSPACE ]]; then
    j3w1zsh_workspace_bind "$J3W1ZSH_SELECTED_WORKSPACE" "$require_trusted_workspace"
    if [[ $require_trusted_workspace == 1 ]]; then
      [[ $(jq -r '.workspace.review_state' "$J3W1ZSH_WORKSPACE_FILE") == approved ]] ||
        j3w1zsh_die "install --workspace requires an approved, tracked, committed-clean profile."
    fi
    local workspace_actions workspace_action
    workspace_actions="$(j3w1zsh_workspace_plan_json "$J3W1ZSH_SELECTED_WORKSPACE")"
    while IFS= read -r workspace_action; do
      if [[ $J3W1ZSH_PACKAGES_ONLY == 1 ]] && [[ $(jq -r .kind <<<"$workspace_action") != package-operation ]]; then
        continue
      fi
      J3W1ZSH_PLAN_ACTIONS+=("$workspace_action")
    done < <(jq -c '.[]' <<<"$workspace_actions")
  fi
}

j3w1zsh_action_selected() {
  local phase="$1"
  local from_phase="$2"
  local only_phase="$3"
  [[ -z $only_phase || $phase == "$only_phase" ]] || return 1
  if [[ -n $from_phase ]]; then
    local candidate seen=0
    for candidate in "${J3W1ZSH_PHASES[@]}"; do
      [[ $candidate != "$from_phase" ]] || seen=1
      if [[ $candidate == "$phase" ]]; then
        ((seen == 1))
        return
      fi
    done
    return 1
  fi
  return 0
}

j3w1zsh_execute_action() {
  local action="$1"
  local from_phase="$2"
  local only_phase="$3"
  local phase kind function
  phase="$(jq -r .phase <<<"$action")"
  kind="$(jq -r .kind <<<"$action")"
  case "$kind" in
  package-operation | file-reconciliation | host-adapter | verification) ;;
  direct-argv-lifecycle | manual-checkpoint)
    j3w1zsh_die "Base installation cannot execute action kind $kind."
    ;;
  *) j3w1zsh_die "Unrecognized typed action: $kind" ;;
  esac
  j3w1zsh_action_selected "$phase" "$from_phase" "$only_phase" || return 0
  if [[ $J3W1ZSH_FORCE != 1 ]] && j3w1zsh_phase_done "$phase"; then
    j3w1zsh_note "Skipping completed phase: $phase"
    return 0
  fi
  function="$(j3w1zsh_phase_function "$phase")"
  declare -F "$function" >/dev/null || j3w1zsh_die "Phase function is missing: $function"
  j3w1zsh_log "Phase $phase"
  if "$function"; then
    j3w1zsh_mark_phase "$phase"
  else
    local result=$?
    if ((result == J3W1ZSH_EXIT_CHECKPOINT)); then
      j3w1zsh_warn "Installation paused at a user-owned checkpoint. Complete the displayed action, then rerun."
    fi
    return "$result"
  fi
}

j3w1zsh_install_command() {
  local from_phase="" only_phase=""
  J3W1ZSH_PRESET=j3w1
  J3W1ZSH_THEME_OVERRIDE=""
  J3W1ZSH_SELECTED_WORKSPACE=""
  J3W1ZSH_NO_PACKAGES=0
  J3W1ZSH_PACKAGES_ONLY=0
  J3W1ZSH_DRY_RUN=0
  J3W1ZSH_ASSUME_YES=0
  J3W1ZSH_FORCE=0
  while (($#)); do
    case "$1" in
    --preset) shift; (($#)) || j3w1zsh_usage_error "--preset requires a name or file."; J3W1ZSH_PRESET="$1" ;;
    --theme) shift; (($#)) || j3w1zsh_usage_error "--theme requires a name."; J3W1ZSH_THEME_OVERRIDE="$1" ;;
    --workspace) shift; (($#)) || j3w1zsh_usage_error "--workspace requires a file."; J3W1ZSH_SELECTED_WORKSPACE="$1" ;;
    --no-packages | --do-not-install-anything | -dnia) J3W1ZSH_NO_PACKAGES=1 ;;
    --packages-only) J3W1ZSH_PACKAGES_ONLY=1 ;;
    --dry-run) J3W1ZSH_DRY_RUN=1 ;;
    --yes) J3W1ZSH_ASSUME_YES=1 ;;
    --force) J3W1ZSH_FORCE=1 ;;
    --from) shift; (($#)) || j3w1zsh_usage_error "--from requires a phase."; from_phase="$1" ;;
    --only) shift; (($#)) || j3w1zsh_usage_error "--only requires a phase."; only_phase="$1" ;;
    -h | --help) j3w1zsh_help_install; return 0 ;;
    *) j3w1zsh_usage_error "Unknown install option: $1" ;;
    esac
    shift
  done
  export J3W1ZSH_PRESET J3W1ZSH_SELECTED_WORKSPACE J3W1ZSH_NO_PACKAGES J3W1ZSH_PACKAGES_ONLY
  export J3W1ZSH_DRY_RUN J3W1ZSH_ASSUME_YES J3W1ZSH_FORCE
  if [[ $J3W1ZSH_NO_PACKAGES == 1 && $J3W1ZSH_PACKAGES_ONLY == 1 ]]; then
    j3w1zsh_usage_error "--no-packages is incompatible with --packages-only."
  fi
  if [[ $J3W1ZSH_NO_PACKAGES == 1 && -n $J3W1ZSH_SELECTED_WORKSPACE ]]; then
    j3w1zsh_usage_error "--no-packages is incompatible with --workspace."
  fi
  local requested valid=false phase
  for requested in "$from_phase" "$only_phase"; do
    [[ -z $requested ]] && continue
    valid=false
    for phase in "${J3W1ZSH_PHASES[@]}"; do [[ $phase != "$requested" ]] || valid=true; done
    [[ $valid == true ]] || j3w1zsh_usage_error "Unknown phase: $requested"
  done

  if [[ $(j3w1zsh_effective_uid) == 0 ]]; then
    [[ $J3W1ZSH_TEST_MODE != 1 ]] || j3w1zsh_die "Test-mode root simulation was rejected before mutation."
    [[ $J3W1ZSH_PLATFORM == wsl ]] ||
      j3w1zsh_die "Root installation is supported only for the one-time official Arch WSL 2 bootstrap."
    [[ $J3W1ZSH_NO_PACKAGES == 0 && $J3W1ZSH_PACKAGES_ONLY == 0 && -z $J3W1ZSH_SELECTED_WORKSPACE && -z $from_phase && -z $only_phase ]] ||
      j3w1zsh_usage_error "The one-time WSL root bootstrap accepts only --dry-run."
    j3w1zsh_plan_reset
    j3w1zsh_plan_add wsl-root-bootstrap 10-platform host-adapter platform-wsl "pacman" /etc/wsl.conf \
      "create a normal user and reconcile the bounded official Arch WSL 2 bootstrap" true true wsl-restart true \
      "normal user, password-protected sudo, WSL 2 systemd configuration, and isolated checkout validate"
    if [[ $J3W1ZSH_DRY_RUN == 1 ]]; then
      if [[ $J3W1ZSH_OUTPUT_MODE == json ]]; then
        j3w1zsh_json_envelope install ok "$(jq -cn --argjson actions "$(j3w1zsh_plan_json)" '{dry_run:true,root_bootstrap:true,actions:$actions}')"
      else
        printf 'One-time root bootstrap plan for official Arch Linux under WSL 2\n\n'
        jq -r '.[] | "  " + .phase + "  " + .kind + "  " + .reason + " [mutation]"' <<<"$(j3w1zsh_plan_json)"
        j3w1zsh_log "Preview complete; no user, package, sudo, WSL, checkout, or state mutation occurred."
      fi
      return 0
    fi
    [[ $J3W1ZSH_OUTPUT_MODE != json ]] || j3w1zsh_usage_error "The one-time WSL root bootstrap is interactive and does not support JSON execution."
    exec "$J3W1ZSH_REPO_ROOT/scripts/bootstrap-root.sh"
  fi

  j3w1zsh_prepare_selection 1
  if [[ $J3W1ZSH_DRY_RUN == 1 ]]; then
    if [[ $J3W1ZSH_OUTPUT_MODE == json ]]; then
      j3w1zsh_json_envelope install ok "$(jq -cn --arg platform "$J3W1ZSH_PLATFORM" --arg preset "$J3W1ZSH_PRESET" --arg theme "$J3W1ZSH_THEME" --arg digest "$(j3w1zsh_plan_digest)" --argjson actions "$(j3w1zsh_plan_json)" '{dry_run:true,platform:$platform,preset:$preset,theme:$theme,plan_digest:$digest,actions:$actions}')"
    else
      j3w1zsh_plan_render_human
      j3w1zsh_log "Preview complete; no state, trust, Git, package, or host configuration was changed."
    fi
    return 0
  fi

  j3w1zsh_ensure_dirs
  j3w1zsh_banner
  j3w1zsh_note "Detected: $(j3w1zsh_platform_label)"
  j3w1zsh_note "State: $J3W1ZSH_STATE_DIR"
  j3w1zsh_load_phases
  local action
  for action in "${J3W1ZSH_PLAN_ACTIONS[@]}"; do
    [[ $(jq -r .phase <<<"$action") != workspace-* ]] || continue
    j3w1zsh_execute_action "$action" "$from_phase" "$only_phase"
  done
  if [[ -n $J3W1ZSH_SELECTED_WORKSPACE ]]; then
    if [[ $J3W1ZSH_PACKAGES_ONLY == 1 ]]; then
      j3w1zsh_workspace_bind "$J3W1ZSH_SELECTED_WORKSPACE" 1
      j3w1zsh_workspace_packages_phase
    else
      local workspace_arguments=("$J3W1ZSH_SELECTED_WORKSPACE")
      [[ $J3W1ZSH_ASSUME_YES != 1 ]] || workspace_arguments+=(--yes)
      [[ $J3W1ZSH_FORCE != 1 ]] || workspace_arguments+=(--force)
      j3w1zsh_workspace_apply_command "${workspace_arguments[@]}"
    fi
  fi
  if [[ $J3W1ZSH_OUTPUT_MODE == json ]]; then
    j3w1zsh_json_envelope install ok "$(jq -cn --arg platform "$J3W1ZSH_PLATFORM" --arg preset "$J3W1ZSH_PRESET" --arg theme "$J3W1ZSH_THEME" '{platform:$platform,preset:$preset,theme:$theme}')"
  elif [[ -n ${J3W1ZSH_BACKUP_DIR:-} ]]; then
    j3w1zsh_note "Pre-existing paths were preserved in: $J3W1ZSH_BACKUP_DIR"
  fi
}
