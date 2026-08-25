#!/usr/bin/env bash

j3w1zsh_packages_prune_execute() {
  local candidates="$1" manager package
  while IFS=$'\t' read -r manager package; do
    case "$manager" in
    pacman) sudo pacman -R -- "$package" ;;
    pkg) pkg uninstall -y -- "$package" ;;
    npm_global)
      if [[ $J3W1ZSH_PLATFORM == termux ]]; then
        npm uninstall -g -- "$package"
      else
        sudo npm uninstall -g -- "$package"
      fi
      ;;
    pip_user) python -m pip uninstall -y -- "$package" ;;
    esac
    j3w1zsh_forget_package_provenance "$manager" "$package"
  done < <(jq -r '.[] | [.manager,.package] | @tsv' <<<"$candidates")
}

j3w1zsh_packages_command() {
  local subcommand="${1:-help}"
  (($# == 0)) || shift
  J3W1ZSH_PRESET=j3w1
  local repair_manager="" repair_packages=()
  while (($#)); do
    case "$1" in
    --preset) shift; (($#)) || j3w1zsh_usage_error "--preset requires a name or file."; J3W1ZSH_PRESET="$1" ;;
    --manager) shift; (($#)) || j3w1zsh_usage_error "--manager requires an exact manager."; repair_manager="$1" ;;
    --package) shift; (($#)) || j3w1zsh_usage_error "--package requires an exact package name."; repair_packages+=("$1") ;;
    --dry-run) J3W1ZSH_DRY_RUN=1 ;;
    --yes) J3W1ZSH_ASSUME_YES=1 ;;
    *) j3w1zsh_usage_error "Unknown packages option: $1" ;;
    esac
    shift
  done
  export J3W1ZSH_PRESET J3W1ZSH_DRY_RUN J3W1ZSH_ASSUME_YES
  j3w1zsh_resolve_preset "$J3W1ZSH_PRESET"
  if [[ $subcommand != repair-provenance && (-n $repair_manager || ${#repair_packages[@]} -gt 0) ]]; then
    j3w1zsh_usage_error "--manager and --package are accepted only by packages repair-provenance."
  fi
  case "$subcommand" in
  plan | status)
    local data
    data="$(j3w1zsh_packages_status_json)"
    if [[ $J3W1ZSH_OUTPUT_MODE == json ]]; then
      j3w1zsh_json_envelope "packages-$subcommand" ok "$data"
    else
      jq -r '.[] | .manager + "\t" + .package + "\t" + (if .installed then "installed" else "missing" end)' <<<"$data"
    fi
    ;;
  prune)
    local candidates
    candidates="$(j3w1zsh_packages_prune_candidates_json)"
    j3w1zsh_plan_reset
    j3w1zsh_plan_add packages-prune packages-prune package-operation provenance "multiple" "" \
      "remove only packages proven installed by j3w1zsh and no longer declared" "$([[ $J3W1ZSH_PLATFORM == termux ]] && printf false || printf true)" true "" true \
      "every removed package exactly matches a reviewed provenance candidate"
    if [[ $J3W1ZSH_OUTPUT_MODE == json || $J3W1ZSH_DRY_RUN == 1 ]]; then
      [[ $J3W1ZSH_OUTPUT_MODE != json ]] || j3w1zsh_json_envelope packages-prune ok "$candidates"
      [[ $J3W1ZSH_OUTPUT_MODE == json ]] || jq -r '.[] | .manager + "\t" + .package + "\t" + .reason' <<<"$candidates"
      return 0
    fi
    (($(jq length <<<"$candidates") > 0)) || { j3w1zsh_note "No package is provably safe to prune."; return 0; }
    jq -r '.[] | .manager + " " + .package + ": " + .reason' <<<"$candidates"
    j3w1zsh_confirm "Remove only these named packages without recursive dependency cleanup?" || return 0
    j3w1zsh_execute_typed_callback "${J3W1ZSH_PLAN_ACTIONS[0]}" j3w1zsh_packages_prune_execute "$candidates"
    ;;
  repair-provenance)
    [[ -n ${HOME:-} && -d $HOME && $HOME != /root ]] || j3w1zsh_die "A normal user HOME is required for provenance repair."
    [[ $(j3w1zsh_effective_uid) != 0 ]] || j3w1zsh_die "Run provenance repair as a normal user, not root."
    [[ $J3W1ZSH_PLATFORM =~ ^(arch|wsl|termux)$ ]] || j3w1zsh_die "Provenance repair requires a supported platform."
    [[ -n $repair_manager && ${#repair_packages[@]} -gt 0 ]] ||
      j3w1zsh_usage_error "packages repair-provenance requires --manager and at least one --package."
    case "$J3W1ZSH_PLATFORM:$repair_manager" in
    arch:pacman | arch:npm_global | arch:pip_user | wsl:pacman | wsl:npm_global | wsl:pip_user | termux:pkg | termux:npm_global | termux:pip_user) ;;
    *) j3w1zsh_usage_error "Package manager $repair_manager is not valid for platform $J3W1ZSH_PLATFORM." ;;
    esac
    case "$repair_manager" in
    pacman) j3w1zsh_have pacman || j3w1zsh_die "pacman is required to verify provenance repair." ;;
    pkg) j3w1zsh_have dpkg-query || j3w1zsh_die "dpkg-query is required to verify provenance repair." ;;
    npm_global) j3w1zsh_have npm || j3w1zsh_die "npm is required to verify provenance repair." ;;
    pip_user) j3w1zsh_have python || j3w1zsh_die "python is required to verify provenance repair." ;;
    esac
    local package targets_json unique_count candidates data
    for package in "${repair_packages[@]}"; do
      [[ $package =~ ^[A-Za-z0-9@._+:-]+$ ]] || j3w1zsh_usage_error "Invalid package name for provenance repair: $package"
    done
    targets_json="$(printf '%s\n' "${repair_packages[@]}" | jq -Rsc 'split("\n")[:-1]')"
    unique_count="$(jq 'unique | length' <<<"$targets_json")"
    [[ $unique_count == "${#repair_packages[@]}" ]] || j3w1zsh_usage_error "Provenance repair package targets must be unique."
    candidates="$(j3w1zsh_package_repair_candidates_json "$repair_manager" "${repair_packages[@]}")"
    data="$(jq -cn --argjson candidates "$candidates" --argjson dry_run "$([[ $J3W1ZSH_DRY_RUN == 1 ]] && printf true || printf false)" \
      '{dry_run:$dry_run,candidates:$candidates,phase_to_invalidate:"20-packages"}')"
    j3w1zsh_plan_reset
    j3w1zsh_plan_add packages-provenance-repair packages-provenance-repair file-reconciliation provenance "$repair_manager" "$(j3w1zsh_package_ledger_file)" \
      "remove only exact false ownership claims after negative package-manager verification and preserve local repair evidence" false true "" true \
      "unrelated provenance is byte-semantically preserved and phase 20 is invalidated"
    if [[ $J3W1ZSH_DRY_RUN == 1 ]]; then
      if [[ $J3W1ZSH_OUTPUT_MODE == json ]]; then
        j3w1zsh_json_envelope packages-repair-provenance ok "$data"
      else
        jq -r '.candidates[] | .manager + " " + .package + ": " + .reason' <<<"$data"
        j3w1zsh_note "Dry run only; provenance, phase state, packages, and manager state were unchanged."
      fi
      return 0
    fi
    [[ $J3W1ZSH_OUTPUT_MODE == json ]] || jq -r '.candidates[] | .manager + " " + .package + ": " + .reason' <<<"$data"
    j3w1zsh_confirm "Preserve repair evidence, remove only these false ownership claims, and invalidate phase 20?" || return 0
    j3w1zsh_execute_typed_callback "${J3W1ZSH_PLAN_ACTIONS[0]}" j3w1zsh_package_repair_provenance_execute "$candidates"
    data="$(jq -cn --argjson candidates "$candidates" --arg evidence "$J3W1ZSH_PROVENANCE_REPAIR_EVIDENCE" \
      '{dry_run:false,repaired:[ $candidates[] | {manager,package} ],phase_invalidated:"20-packages",evidence:$evidence}')"
    if [[ $J3W1ZSH_OUTPUT_MODE == json ]]; then
      j3w1zsh_json_envelope packages-repair-provenance ok "$data"
    else
      j3w1zsh_note "False provenance was removed, repair evidence was preserved, and phase 20 is pending."
      j3w1zsh_note "Evidence: $J3W1ZSH_PROVENANCE_REPAIR_EVIDENCE"
    fi
    ;;
  help | -h | --help)
    printf 'Usage: j3w1zsh packages plan|status|prune [--dry-run] [--json]\n'
    printf '       j3w1zsh packages repair-provenance --manager MANAGER --package NAME [--package NAME ...] [--dry-run] [--yes] [--json]\n'
    ;;
  *) j3w1zsh_usage_error "Unknown packages command: $subcommand" ;;
  esac
}
