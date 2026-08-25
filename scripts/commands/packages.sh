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
  while (($#)); do
    case "$1" in
    --preset) shift; (($#)) || j3w1zsh_usage_error "--preset requires a name or file."; J3W1ZSH_PRESET="$1" ;;
    --dry-run) J3W1ZSH_DRY_RUN=1 ;;
    --yes) J3W1ZSH_ASSUME_YES=1 ;;
    *) j3w1zsh_usage_error "Unknown packages option: $1" ;;
    esac
    shift
  done
  export J3W1ZSH_PRESET J3W1ZSH_DRY_RUN J3W1ZSH_ASSUME_YES
  j3w1zsh_resolve_preset "$J3W1ZSH_PRESET"
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
  help | -h | --help) printf 'Usage: j3w1zsh packages plan|status|prune [--dry-run] [--json]\n' ;;
  *) j3w1zsh_usage_error "Unknown packages command: $subcommand" ;;
  esac
}
