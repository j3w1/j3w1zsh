#!/usr/bin/env bash

j3w1zsh_output_init() {
  local use_color=0
  case "$J3W1ZSH_COLOR_MODE" in
  always) use_color=1 ;;
  never) use_color=0 ;;
  auto)
    if [[ -t 1 && -z ${NO_COLOR:-} && $J3W1ZSH_OUTPUT_MODE == human ]]; then
      use_color=1
    fi
    ;;
  *) printf 'invalid color mode: %s\n' "$J3W1ZSH_COLOR_MODE" >&2; return 2 ;;
  esac
  if [[ $J3W1ZSH_OUTPUT_MODE != human ]]; then
    use_color=0
  fi

  if ((use_color)); then
    J3W1ZSH_RED=$'\e[38;2;255;51;77m'
    J3W1ZSH_DIM=$'\e[38;2;223;160;160m'
    J3W1ZSH_RESET=$'\e[0m'
  else
    J3W1ZSH_RED=""
    J3W1ZSH_DIM=""
    J3W1ZSH_RESET=""
  fi
  export J3W1ZSH_RED J3W1ZSH_DIM J3W1ZSH_RESET
}

j3w1zsh_width() {
  local width="${COLUMNS:-}"
  if [[ ! $width =~ ^[0-9]+$ ]] && command -v tput >/dev/null 2>&1; then
    width="$(tput cols 2>/dev/null || true)"
  fi
  [[ $width =~ ^[0-9]+$ ]] || width=80
  printf '%s\n' "$width"
}

j3w1zsh_log() {
  [[ $J3W1ZSH_OUTPUT_MODE == json ]] && return 0
  if [[ $J3W1ZSH_OUTPUT_MODE == plain ]]; then
    printf '[+] %s\n' "$*"
  else
    printf '%s==>%s %s\n' "$J3W1ZSH_RED" "$J3W1ZSH_RESET" "$*"
  fi
}

j3w1zsh_note() {
  [[ $J3W1ZSH_OUTPUT_MODE == json ]] && return 0
  if [[ $J3W1ZSH_OUTPUT_MODE == plain ]]; then
    printf '    %s\n' "$*"
  else
    printf '%s    %s%s\n' "$J3W1ZSH_DIM" "$*" "$J3W1ZSH_RESET"
  fi
}

j3w1zsh_warn() {
  [[ $J3W1ZSH_OUTPUT_MODE == json ]] && return 0
  if [[ $J3W1ZSH_OUTPUT_MODE == plain ]]; then
    printf '[!] %s\n' "$*" >&2
  else
    printf '%sWARNING:%s %s\n' "$J3W1ZSH_RED" "$J3W1ZSH_RESET" "$*" >&2
  fi
}

j3w1zsh_json_envelope() {
  local command_name="$1"
  local status="$2"
  local data="${3-}"
  [[ -n $data ]] || data='{}'
  jq -cn \
    --argjson schema_version "$J3W1ZSH_JSON_SCHEMA_VERSION" \
    --arg command "$command_name" \
    --arg status "$status" \
    --argjson data "$data" \
    '{schema_version:$schema_version,command:$command,status:$status,data:$data}'
}

j3w1zsh_json_error() {
  local command_name="$1"
  local error_code="$2"
  local message="$3"
  jq -cn \
    --argjson schema_version "$J3W1ZSH_JSON_SCHEMA_VERSION" \
    --arg command "$command_name" \
    --arg status error \
    --arg code "$error_code" \
    --arg message "$message" \
    '{schema_version:$schema_version,command:$command,status:$status,data:{},error:{code:$code,message:$message}}'
}

j3w1zsh_die() {
  local message="$1"
  local exit_code="${2:-$J3W1ZSH_EXIT_FAILURE}"
  local error_code="${3:-runtime_failure}"
  if [[ $J3W1ZSH_OUTPUT_MODE == json ]]; then
    j3w1zsh_json_error "${J3W1ZSH_ACTIVE_COMMAND:-unknown}" "$error_code" "$message" >&2
  elif [[ $J3W1ZSH_OUTPUT_MODE == plain ]]; then
    printf '[x] %s\n' "$message" >&2
  else
    printf '%sERROR:%s %s\n' "$J3W1ZSH_RED" "$J3W1ZSH_RESET" "$message" >&2
  fi
  exit "$exit_code"
}

j3w1zsh_usage_error() {
  j3w1zsh_die "$1" "$J3W1ZSH_EXIT_USAGE" invalid_arguments
}

j3w1zsh_banner() {
  [[ $J3W1ZSH_OUTPUT_MODE == json ]] && return 0
  local width
  width="$(j3w1zsh_width)"
  if ((width < 80)); then
    printf '%sj3w1zsh%s\n' "$J3W1ZSH_RED" "$J3W1ZSH_RESET"
    printf '%sone shell. every machine. zero compromise.%s\n\n' "$J3W1ZSH_DIM" "$J3W1ZSH_RESET"
    return 0
  fi
  printf '%s' "$J3W1ZSH_RED"
  cat <<'EOF'
            ┌──────────────┐
            │  >_ j3w1zsh │
            └──────◆───────┘
EOF
  printf '%sone shell. every machine. zero compromise.%s\n\n' "$J3W1ZSH_DIM" "$J3W1ZSH_RESET"
}

j3w1zsh_quote_command() {
  printf ' %q' "$@"
  printf '\n'
}

j3w1zsh_run() {
  if [[ $J3W1ZSH_DRY_RUN == 1 ]]; then
    [[ $J3W1ZSH_OUTPUT_MODE == json ]] || printf 'DRY RUN:'
    [[ $J3W1ZSH_OUTPUT_MODE == json ]] || j3w1zsh_quote_command "$@"
    return 0
  fi
  "$@"
}

j3w1zsh_have() {
  command -v "$1" >/dev/null 2>&1
}

j3w1zsh_confirm() {
  local prompt="$1"
  if [[ $J3W1ZSH_ASSUME_YES == 1 ]]; then
    j3w1zsh_note "$prompt [automatic yes]"
    return 0
  fi
  [[ -t 0 ]] || j3w1zsh_die "$prompt Re-run interactively or pass --yes."
  local answer
  read -r -p "$prompt [y/N] " answer
  [[ $answer == [Yy] || $answer == [Yy][Ee][Ss] ]]
}

j3w1zsh_confirm_manual() {
  local prompt="$1"
  if [[ ! -t 0 ]]; then
    j3w1zsh_warn "$prompt Confirmation must be entered interactively."
    return 1
  fi
  local answer
  read -r -p "$prompt [y/N] " answer
  [[ $answer == [Yy] || $answer == [Yy][Ee][Ss] ]]
}
