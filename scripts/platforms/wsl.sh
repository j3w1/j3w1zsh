#!/usr/bin/env bash

j3w1zsh_platform_configure_wsl() {
  [[ $J3W1ZSH_TEST_MODE == 1 ]] && return 0
  local init_name
  init_name="$(ps -p 1 -o comm= 2>/dev/null | tr -d '[:space:]')"
  if [[ -f $J3W1ZSH_STATE_DIR/restart-required && $init_name == systemd ]]; then
    j3w1zsh_log "The requested WSL restart was detected."
    j3w1zsh_run rm -- "$J3W1ZSH_STATE_DIR/restart-required"
  fi

  local desired current temporary
  desired=$'[boot]\nsystemd=true\n\n[user]\ndefault='"$USER"$'\n\n[interop]\nenabled=true\nappendWindowsPath=true\n'
  if [[ -e /etc/wsl.conf || -L /etc/wsl.conf ]]; then
    [[ -f /etc/wsl.conf && ! -L /etc/wsl.conf ]] || j3w1zsh_die "Refusing a non-regular or symlinked /etc/wsl.conf."
  fi
  current="$(cat /etc/wsl.conf 2>/dev/null || true)"
  if [[ "$current"$'\n' != "$desired" ]]; then
    j3w1zsh_warn "/etc/wsl.conf must be reconciled for systemd and the selected normal user."
    j3w1zsh_confirm "Back up and replace /etc/wsl.conf with the bounded j3w1zsh WSL baseline?" || return 1
    temporary="$(mktemp "${TMPDIR:-/tmp}/j3w1zsh-wsl-conf.XXXXXX")"
    printf '%s' "$desired" >"$temporary"
    if [[ -f /etc/wsl.conf ]]; then
      j3w1zsh_run sudo cp -- /etc/wsl.conf "/etc/wsl.conf.before-j3w1zsh-$(date +%Y%m%d-%H%M%S)"
    fi
    j3w1zsh_run sudo install -m 0644 "$temporary" /etc/wsl.conf
    rm -f -- "$temporary"
    printf '%s\n' "system configuration changed" >"$J3W1ZSH_STATE_DIR/restart-required"
    printf '\nFrom Windows PowerShell run:\n\n  wsl --terminate %q\n  wsl --distribution %q\n\nThen rerun ./install.sh.\n' \
      "${WSL_DISTRO_NAME:-archlinux}" "${WSL_DISTRO_NAME:-archlinux}"
    return "$J3W1ZSH_EXIT_CHECKPOINT"
  fi
  if [[ $init_name != systemd ]]; then
    printf '%s\n' "systemd is not PID 1" >"$J3W1ZSH_STATE_DIR/restart-required"
    j3w1zsh_warn "Systemd is configured but not PID 1. Terminate and reopen this WSL distribution, then rerun."
    return "$J3W1ZSH_EXIT_CHECKPOINT"
  fi
}

j3w1zsh_host_theme_wsl() {
  [[ $J3W1ZSH_TEST_MODE != 1 || ${J3W1ZSH_TEST_HOST_ADAPTERS:-0} == 1 ]] || return 0
  local checkpoint=windows-terminal-restart
  if j3w1zsh_manual_pending "$checkpoint"; then
    if j3w1zsh_confirm_manual "Have you closed every Windows Terminal window and reopened j3w1zsh?"; then
      j3w1zsh_clear_manual "$checkpoint"
      return 0
    fi
    return "$J3W1ZSH_EXIT_CHECKPOINT"
  fi
  j3w1zsh_have powershell.exe || j3w1zsh_die "powershell.exe is required for the WSL host theme adapter."
  j3w1zsh_have wslpath || j3w1zsh_die "wslpath is required for the WSL host theme adapter."
  j3w1zsh_confirm "Install or update the current-user j3w1zsh Windows Terminal fragment?" || return 1
  local script_path theme_path
  script_path="$(wslpath -w "$J3W1ZSH_REPO_ROOT/windows/apply-host-theme.ps1")"
  theme_path="$(wslpath -w "$J3W1ZSH_CONFIG_DIR/generated/theme/windows-terminal.json")"
  local arguments=(-NoLogo -NoProfile -ExecutionPolicy Bypass -File "$script_path" \
    -DistroName "${WSL_DISTRO_NAME:-archlinux}" -ThemePath "$theme_path")
  [[ $J3W1ZSH_NO_PACKAGES != 1 ]] || arguments+=(-SkipFontInstall)
  if [[ -n ${J3W1ZSH_MIGRATION_RECOVERY_ROOT:-} ]]; then
    arguments+=(-MigrationRecoveryPath "$(wslpath -w "$J3W1ZSH_MIGRATION_RECOVERY_ROOT")")
  fi
  j3w1zsh_run powershell.exe "${arguments[@]}"
  j3w1zsh_mark_manual_pending "$checkpoint" \
    "Close every Windows Terminal window, reopen the lowercase j3w1zsh profile, then rerun ./install.sh."
  return "$J3W1ZSH_EXIT_CHECKPOINT"
}
