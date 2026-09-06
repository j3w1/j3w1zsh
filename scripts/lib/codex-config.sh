#!/usr/bin/env bash

if [[ -n ${J3W1ZSH_CODEX_CONFIG_LOADED:-} ]]; then
  return 0
fi
readonly J3W1ZSH_CODEX_CONFIG_LOADED=1

readonly J3W1ZSH_CODEX_MANAGED_KEY='mcp_servers.openaiDeveloperDocs.url'
# shellcheck disable=SC2034 # Referenced by the separately sourced codex command module.
readonly J3W1ZSH_CODEX_MANAGED_ID='openaiDeveloperDocs'

j3w1zsh_codex_config_path() {
  printf '%s/.codex/config.toml\n' "$HOME"
}

j3w1zsh_codex_baseline_state_path() {
  printf '%s/codex/baseline.json\n' "$J3W1ZSH_STATE_DIR"
}

j3w1zsh_codex_config_helper() {
  printf '%s/scripts/codex-config.py\n' "$J3W1ZSH_REPO_ROOT"
}

j3w1zsh_codex_baseline_template() {
  printf '%s/templates/codex-config.toml\n' "$J3W1ZSH_REPO_ROOT"
}

j3w1zsh_codex_baseline_ownership() {
  printf '%s/templates/codex-baseline-ownership.json\n' "$J3W1ZSH_REPO_ROOT"
}

j3w1zsh_codex_config_validate_paths() {
  local config state helper baseline ownership
  config="$(j3w1zsh_codex_config_path)"
  state="$(j3w1zsh_codex_baseline_state_path)"
  helper="$(j3w1zsh_codex_config_helper)"
  baseline="$(j3w1zsh_codex_baseline_template)"
  ownership="$(j3w1zsh_codex_baseline_ownership)"
  j3w1zsh_validate_home_target "$config"
  j3w1zsh_validate_home_target "$state"
  [[ -f $helper && ! -L $helper && -f $baseline && ! -L $baseline && -f $ownership && ! -L $ownership ]] ||
    j3w1zsh_die 'Codex baseline artifacts are missing or unsafe.'
}

j3w1zsh_codex_config_invoke() {
  local operation="$1" config state
  j3w1zsh_codex_config_validate_paths
  config="$(j3w1zsh_codex_config_path)"
  state="$(j3w1zsh_codex_baseline_state_path)"
  command -v python3 >/dev/null 2>&1 || return 127
  python3 "$(j3w1zsh_codex_config_helper)" "$operation" \
    --config "$config" \
    --state "$state" \
    --baseline "$(j3w1zsh_codex_baseline_template)" \
    --ownership "$(j3w1zsh_codex_baseline_ownership)"
}

j3w1zsh_codex_config_plan_json() {
  local output result reason
  set +e
  output="$(j3w1zsh_codex_config_invoke plan 2>/dev/null)"
  result=$?
  set -e
  if ((result == 0)) && jq -e '.schema_version == 1 and (.actions | type == "array")' <<<"$output" >/dev/null 2>&1; then
    printf '%s\n' "$output"
    return 0
  fi
  reason='tomlkit-unavailable'
  if jq -e '.status == "blocked" and (.reason | type == "string")' <<<"$output" >/dev/null 2>&1; then
    reason="$(jq -r .reason <<<"$output")"
  fi
  jq -cn --arg key "$J3W1ZSH_CODEX_MANAGED_KEY" --arg reason "$reason" \
    '{schema_version:1,managed:1,current:0,overridden:0,disabled:0,pending:0,blocked:1,actions:[{key:$key,action:"blocked",reason:$reason}]}'
}

j3w1zsh_codex_config_reconcile() {
  local output result reason
  set +e
  output="$(j3w1zsh_codex_config_invoke reconcile)"
  result=$?
  set -e
  if ((result != 0)) || ! jq -e '.schema_version == 1 and (.actions | type == "array")' <<<"$output" >/dev/null 2>&1; then
    reason='unknown-reconciliation-failure'
    if jq -e '.status == "blocked" and (.reason | type == "string")' <<<"$output" >/dev/null 2>&1; then
      reason="$(jq -r .reason <<<"$output")"
    fi
    j3w1zsh_die "Codex configuration reconciliation stopped safely: $reason"
  fi
  jq -r '.actions[] | "Codex baseline: " + .action + " portable key: " + .key' <<<"$output" | while IFS= read -r line; do
    j3w1zsh_note "$line"
  done
}

j3w1zsh_codex_baseline_state_change() {
  local operation="$1" output result reason
  set +e
  output="$(j3w1zsh_codex_config_invoke "$operation")"
  result=$?
  set -e
  if ((result != 0)) || ! jq -e '.schema_version == 1 and .key == "mcp_servers.openaiDeveloperDocs.url"' <<<"$output" >/dev/null 2>&1; then
    reason='unknown-reconciliation-failure'
    if jq -e '.status == "blocked" and (.reason | type == "string")' <<<"$output" >/dev/null 2>&1; then
      reason="$(jq -r .reason <<<"$output")"
    fi
    j3w1zsh_die "Codex baseline $operation stopped safely: $reason"
  fi
  printf '%s\n' "$output"
}
