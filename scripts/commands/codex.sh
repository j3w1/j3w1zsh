#!/usr/bin/env bash

j3w1zsh_codex_status_data_json() {
  local plan display_home='~'
  plan="$(j3w1zsh_codex_config_plan_json)"
  jq -cn --arg platform "$J3W1ZSH_PLATFORM" --arg config_path "$display_home/.codex/config.toml" --arg state_path "$display_home/.local/state/j3w1zsh/codex/baseline.json" \
    --argjson plan "$plan" '
      {
        platform:$platform,
        applicable:($platform == "wsl"),
        config_path:$config_path,
        state_path:$state_path,
        portable_baseline:{
          managed:($plan.managed // 0),
          current:($plan.current // 0),
          overridden:($plan.overridden // 0),
          disabled:($plan.disabled // 0),
          pending:($plan.pending // 0),
          blocked:($plan.blocked // 0)
        },
        actions:($plan.actions | map({key,action}))
      }
    '
}

j3w1zsh_codex_status_command() {
  (($# == 0)) || j3w1zsh_usage_error 'codex status accepts no arguments.'
  local data status=ok
  if [[ $J3W1ZSH_PLATFORM != wsl ]]; then
    data="$(jq -cn --arg platform "$J3W1ZSH_PLATFORM" '{platform:$platform,applicable:false,portable_baseline:{managed:0,current:0,overridden:0,disabled:0,pending:0,blocked:0},actions:[]}')"
  else
    data="$(j3w1zsh_codex_status_data_json)"
    [[ $(jq -r '.portable_baseline.blocked' <<<"$data") == 0 ]] || status=error
  fi
  if [[ $J3W1ZSH_OUTPUT_MODE == json ]]; then
    j3w1zsh_json_envelope codex-status "$status" "$data"
  else
    jq -r '
      "Platform: " + .platform +
      "\nApplicable: " + (.applicable | tostring) +
      (if .applicable then
        "\nManaged: " + (.portable_baseline.managed | tostring) +
        "\nCurrent: " + (.portable_baseline.current | tostring) +
        "\nOverridden: " + (.portable_baseline.overridden | tostring) +
        "\nDisabled: " + (.portable_baseline.disabled | tostring) +
        "\nPending: " + (.portable_baseline.pending | tostring) +
        "\nBlocked: " + (.portable_baseline.blocked | tostring) +
        "\nActions:\n" + ([.actions[] | "  " + .action + ": " + .key] | join("\n"))
      else "" end)
    ' <<<"$data"
  fi
  [[ $status == ok ]]
}

j3w1zsh_codex_disable_command() {
  [[ $# == 1 && $1 == "$J3W1ZSH_CODEX_MANAGED_ID" ]] ||
    j3w1zsh_usage_error 'Usage: j3w1zsh codex disable openaiDeveloperDocs'
  [[ $J3W1ZSH_PLATFORM == wsl ]] || j3w1zsh_die 'Codex baseline controls are available only on WSL.'
  j3w1zsh_ensure_dirs
  local data
  data="$(j3w1zsh_codex_baseline_state_change disable)"
  [[ $J3W1ZSH_OUTPUT_MODE != json ]] || { j3w1zsh_json_envelope codex-disable ok "$data"; return; }
  j3w1zsh_note 'Disabled portable reconciliation for openaiDeveloperDocs; the existing user config was not changed.'
}

j3w1zsh_codex_reset_command() {
  [[ $# == 2 && $1 == "$J3W1ZSH_CODEX_MANAGED_ID" && $2 == '--yes' ]] ||
    j3w1zsh_usage_error 'Usage: j3w1zsh codex reset openaiDeveloperDocs --yes'
  [[ $J3W1ZSH_PLATFORM == wsl ]] || j3w1zsh_die 'Codex baseline controls are available only on WSL.'
  j3w1zsh_ensure_dirs
  local data
  data="$(j3w1zsh_codex_baseline_state_change reset)"
  [[ $J3W1ZSH_OUTPUT_MODE != json ]] || { j3w1zsh_json_envelope codex-reset ok "$data"; return; }
  j3w1zsh_note 'Reset the openaiDeveloperDocs portable URL to the tracked j3w1zsh baseline.'
}

j3w1zsh_codex_command() {
  local subcommand="${1:-help}"
  (($# == 0)) || shift
  case "$subcommand" in
  status) j3w1zsh_codex_status_command "$@" ;;
  disable) j3w1zsh_codex_disable_command "$@" ;;
  reset) j3w1zsh_codex_reset_command "$@" ;;
  help | -h | --help) j3w1zsh_help_codex ;;
  *) j3w1zsh_usage_error "Unknown codex command: $subcommand" ;;
  esac
}
