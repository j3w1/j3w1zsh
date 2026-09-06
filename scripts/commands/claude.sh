#!/usr/bin/env bash

readonly J3W1ZSH_CLAUDE_NPM_PACKAGE='@anthropic-ai/claude-code'

j3w1zsh_claude_npm_version() {
  command -v npm >/dev/null 2>&1 || return 0

  local metadata version
  metadata="$(npm list --global --depth=0 --json -- "$J3W1ZSH_CLAUDE_NPM_PACKAGE" 2>/dev/null || true)"
  version="$(jq -r --arg package "$J3W1ZSH_CLAUDE_NPM_PACKAGE" '.dependencies[$package].version // empty' <<<"$metadata" 2>/dev/null || true)"
  [[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$ ]] || return 0
  printf '%s\n' "$version"
}

j3w1zsh_claude_status_data_json() {
  local applicable=false available=false version=""
  case "$J3W1ZSH_PLATFORM" in
  arch | wsl)
    applicable=true
    if j3w1zsh_have claude; then
      available=true
      version="$(j3w1zsh_claude_npm_version)"
    fi
    ;;
  esac
  jq -cn \
    --arg platform "$J3W1ZSH_PLATFORM" \
    --arg package "$J3W1ZSH_CLAUDE_NPM_PACKAGE" \
    --arg version "$version" \
    --argjson applicable "$applicable" \
    --argjson available "$available" \
    '{platform:$platform,applicable:$applicable,available:$available,package:{name:$package,version:(if $version == "" then null else $version end)},configuration_managed:false}'
}

j3w1zsh_claude_status_command() {
  (($# == 0)) || j3w1zsh_usage_error 'claude status accepts no arguments.'
  local data status=ok
  data="$(j3w1zsh_claude_status_data_json)"
  if [[ $(jq -r '.applicable and .available' <<<"$data") != true ]]; then
    [[ $(jq -r '.applicable' <<<"$data") != true ]] || status=error
  fi
  if [[ $J3W1ZSH_OUTPUT_MODE == json ]]; then
    j3w1zsh_json_envelope claude-status "$status" "$data"
  else
    jq -r '
      "Platform: " + .platform,
      "Applicable: " + (if .applicable then "yes" else "no" end),
      "Available: " + (if .available then "yes" else "no" end),
      "npm package: " + .package.name,
      "Version: " + (.package.version // "unavailable"),
      "Configuration: user-owned and not inspected"
    ' <<<"$data"
  fi
  [[ $status == ok ]]
}

j3w1zsh_claude_command() {
  local subcommand="${1:-help}"
  (($# == 0)) || shift
  case "$subcommand" in
  status) j3w1zsh_claude_status_command "$@" ;;
  help | -h | --help) j3w1zsh_help_claude ;;
  *) j3w1zsh_usage_error "Unknown claude command: $subcommand" ;;
  esac
}
