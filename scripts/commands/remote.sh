#!/usr/bin/env bash

j3w1zsh_remote_setting() {
  local key="$1" file="$J3W1ZSH_CONFIG_DIR/settings.zsh"
  [[ -f $file && ! -L $file ]] || return 0
  awk -v key="$key" '
    $1 == "export" && index($2,key "=") == 1 {
      value=substr($2,length(key)+2)
      if ((substr(value,1,1)=="\047" && substr(value,length(value),1)=="\047") ||
          (substr(value,1,1)=="\"" && substr(value,length(value),1)=="\"")) value=substr(value,2,length(value)-2)
      print value
      exit
    }
  ' "$file"
}

j3w1zsh_remote_validate_host() {
  [[ $1 =~ ^[A-Za-z0-9][A-Za-z0-9._:-]*$ ]] || j3w1zsh_usage_error "Remote host contains unsupported characters."
}

j3w1zsh_remote_validate_user() {
  [[ $1 =~ ^[A-Za-z_][A-Za-z0-9_-]*$ ]] || j3w1zsh_usage_error "Remote user contains unsupported characters."
}

j3w1zsh_remote_setup_host_execute() {
  j3w1zsh_warn "The host must remain powered on, awake, networked, and running for remote sessions."
  j3w1zsh_confirm "Install Tailscale and enable private Tailscale SSH on this host?" || return 0
  sudo pacman -S --needed tailscale
  sudo systemctl enable --now tailscaled
  sudo tailscale up --ssh
  local hostname address login
  hostname="$(tailscale status --self --json 2>/dev/null | jq -r '.Self.DNSName // empty' | sed 's/\.$//')"
  address="$(tailscale ip -4 2>/dev/null | head -n1)"
  login="${USER:-$(id -un)}"
  printf 'Remote host ready. Configure the Termux client with:\n'
  printf '  j3w1zsh remote configure-client --host %q --user %q\n' "${hostname:-$address}" "$login"
}

j3w1zsh_remote_setup_host() {
  (($# == 0)) || j3w1zsh_usage_error "remote setup-host accepts no arguments."
  [[ $J3W1ZSH_PLATFORM == arch || $J3W1ZSH_PLATFORM == wsl ]] || j3w1zsh_die "remote setup-host is available only on native Arch or WSL."
  j3w1zsh_plan_reset
  j3w1zsh_plan_add remote-host remote-setup-host host-adapter remote pacman "" \
    "install Tailscale and enable private Tailscale SSH" true true remote-host-approval true \
    "tailscaled is active and the private SSH endpoint is reported"
  if [[ $J3W1ZSH_TEST_MODE == 1 ]]; then
    j3w1zsh_note "Would install Tailscale only after explicit confirmation and enable private Tailscale SSH."
    return 0
  fi
  [[ $(ps -p 1 -o comm= | tr -d '[:space:]') == systemd ]] || j3w1zsh_die "systemd must be active before remote host setup."
  j3w1zsh_execute_typed_callback "${J3W1ZSH_PLAN_ACTIONS[0]}" j3w1zsh_remote_setup_host_execute
}

j3w1zsh_remote_configure_client_execute() {
  local host="$1" user="$2" attach_command="$3"
  j3w1zsh_set_zsh_setting J3W1ZSH_REMOTE_HOST "$host"
  j3w1zsh_set_zsh_setting J3W1ZSH_REMOTE_USER "$user"
  j3w1zsh_set_zsh_setting J3W1ZSH_REMOTE_ATTACH_COMMAND "$attach_command"
}

j3w1zsh_remote_configure_client() {
  local host user
  host="$(j3w1zsh_remote_setting J3W1ZSH_REMOTE_HOST)"
  user="$(j3w1zsh_remote_setting J3W1ZSH_REMOTE_USER)"
  while (($#)); do
    case "$1" in
    --host) shift; (($#)) || j3w1zsh_usage_error "--host requires a value."; host="$1" ;;
    --user) shift; (($#)) || j3w1zsh_usage_error "--user requires a value."; user="$1" ;;
    *) j3w1zsh_usage_error "Unknown configure-client option: $1" ;;
    esac
    shift
  done
  [[ $J3W1ZSH_PLATFORM == termux ]] || j3w1zsh_die "remote configure-client is the native Termux client flow."
  if [[ -z $host && -t 0 ]]; then read -r -p 'Remote j3w1zsh host: ' host; fi
  if [[ -z $user && -t 0 ]]; then read -r -p 'Remote Linux user: ' user; fi
  [[ -n $host && -n $user ]] || j3w1zsh_usage_error "Both --host and --user are required non-interactively."
  j3w1zsh_remote_validate_host "$host"
  j3w1zsh_remote_validate_user "$user"
  local attach_command="/home/$user/.local/bin/tma"
  j3w1zsh_plan_reset
  j3w1zsh_plan_add remote-client remote-configure-client file-reconciliation user "" "$J3W1ZSH_CONFIG_DIR/settings.zsh" \
    "write validated remote host tokens without copying authentication" false false "" true \
    "three strict remote settings are present"
  j3w1zsh_execute_typed_callback "${J3W1ZSH_PLAN_ACTIONS[0]}" j3w1zsh_remote_configure_client_execute "$host" "$user" "$attach_command"
  j3w1zsh_note "Remote client configured. Authentication remains in SSH/Tailscale and was not copied or logged."
}

j3w1zsh_remote_attach_execute() {
  local host="$1" user="$2" command="$3" session="$4"
  if [[ -n $session ]]; then
    exec ssh -t -- "$user@$host" "$command" "$session"
  fi
  exec ssh -t -- "$user@$host" "$command"
}

j3w1zsh_remote_attach() {
  (($# <= 1)) || j3w1zsh_usage_error "remote attach accepts at most one session."
  [[ $J3W1ZSH_PLATFORM == termux ]] || j3w1zsh_die "remote attach is available from the native Termux client."
  local host user command session="${1:-}"
  host="$(j3w1zsh_remote_setting J3W1ZSH_REMOTE_HOST)"
  user="$(j3w1zsh_remote_setting J3W1ZSH_REMOTE_USER)"
  command="$(j3w1zsh_remote_setting J3W1ZSH_REMOTE_ATTACH_COMMAND)"
  [[ -n $host && -n $user ]] || j3w1zsh_die "Remote client is not configured. Run j3w1zsh remote configure-client."
  [[ -n $command ]] || command="/home/$user/.local/bin/tma"
  j3w1zsh_remote_validate_host "$host"; j3w1zsh_remote_validate_user "$user"
  [[ $command =~ ^/[A-Za-z0-9/._-]+$ && $command != *..* ]] || j3w1zsh_die "Remote attach command is not a safe absolute token."
  [[ -z $session || $session =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] || j3w1zsh_usage_error "Invalid remote session name."
  j3w1zsh_plan_reset
  j3w1zsh_plan_add remote-attach remote-attach direct-argv-lifecycle remote "" "" \
    "execute one validated SSH argv to the configured private host" false false "" true \
    "SSH launches only the bounded remote attach command"
  j3w1zsh_execute_typed_callback "${J3W1ZSH_PLAN_ACTIONS[0]}" j3w1zsh_remote_attach_execute "$host" "$user" "$command" "$session"
}

j3w1zsh_remote_status_data() {
  local host user command configured=false
  host="$(j3w1zsh_remote_setting J3W1ZSH_REMOTE_HOST)"
  user="$(j3w1zsh_remote_setting J3W1ZSH_REMOTE_USER)"
  command="$(j3w1zsh_remote_setting J3W1ZSH_REMOTE_ATTACH_COMMAND)"
  [[ -z $host || -z $user ]] || configured=true
  jq -cn --arg platform "$J3W1ZSH_PLATFORM" --arg host "$host" --arg user "$user" --arg command "$command" --argjson configured "$configured" \
    '{platform:$platform,configured:$configured,host:(if $host=="" then null else $host end),user:(if $user=="" then null else $user end),attach_command:(if $command=="" then null else $command end)}'
}

j3w1zsh_remote_command() {
  local subcommand="${1:-help}"
  (($# == 0)) || shift
  case "$subcommand" in
  setup-host) j3w1zsh_remote_setup_host "$@" ;;
  configure-client) j3w1zsh_remote_configure_client "$@" ;;
  attach) j3w1zsh_remote_attach "$@" ;;
  status)
    (($# == 0)) || j3w1zsh_usage_error "remote status accepts no arguments."
    local data; data="$(j3w1zsh_remote_status_data)"
    [[ $J3W1ZSH_OUTPUT_MODE != json ]] || { j3w1zsh_json_envelope remote-status ok "$data"; return; }
    jq -r '"Platform: " + .platform + "\nConfigured: " + (.configured|tostring) + (if .configured then "\nHost: " + .host + "\nUser: " + .user + "\nAttach command: " + .attach_command else "" end)' <<<"$data"
    ;;
  help | -h | --help) j3w1zsh_help_remote ;;
  *) j3w1zsh_usage_error "Unknown remote command: $subcommand" ;;
  esac
}
