#!/usr/bin/env bash

j3w1zsh_platform_configure_termux() {
  j3w1zsh_note "Android owns init and host policy; j3w1zsh changes no system or privileged path in Termux."
}

j3w1zsh_host_theme_termux() {
  [[ $J3W1ZSH_TEST_MODE != 1 || ${J3W1ZSH_TEST_HOST_ADAPTERS:-0} == 1 ]] || return 0
  local storage_checkpoint=termux-storage-permission
  if [[ ! -d $HOME/storage/shared ]]; then
    j3w1zsh_log "Opening Android's Termux storage permission flow."
    j3w1zsh_run termux-setup-storage
    if [[ ! -d $HOME/storage/shared ]]; then
      j3w1zsh_mark_manual_pending "$storage_checkpoint" \
        "Grant Termux file access in Android, return to Termux, and rerun ./install.sh."
      return "$J3W1ZSH_EXIT_CHECKPOINT"
    fi
  fi
  j3w1zsh_clear_manual "$storage_checkpoint"

  local api_checkpoint=termux-api-app
  if ! timeout 5 termux-clipboard-get >/dev/null 2>&1; then
    j3w1zsh_mark_manual_pending "$api_checkpoint" \
      "Install the matching-source Termux:API Android app, then rerun ./install.sh."
    return "$J3W1ZSH_EXIT_CHECKPOINT"
  fi
  j3w1zsh_clear_manual "$api_checkpoint"

  local termux_dir="$HOME/.termux"
  local font="$termux_dir/font.ttf" font_checksum=""
  j3w1zsh_validate_home_target "$font"
  j3w1zsh_validate_home_target "$termux_dir/colors.properties"
  j3w1zsh_run mkdir -p "$termux_dir"
  [[ ! -f $font ]] || font_checksum="$(sha256sum "$font" | awk '{print $1}')"
  if [[ $font_checksum != "$NERD_FONT_SHA256" ]]; then
    if [[ $J3W1ZSH_NO_PACKAGES == 1 ]]; then
      j3w1zsh_warn "The pinned Termux font is missing or differs; package-free mode did not acquire it."
    else
      local font_download="$J3W1ZSH_CACHE_DIR/JetBrainsMonoNerdFontMono-Regular.ttf"
      local font_url="https://raw.githubusercontent.com/ryanoasis/nerd-fonts/v$NERD_FONT_VERSION/patched-fonts/JetBrainsMono/Ligatures/Regular/JetBrainsMonoNerdFontMono-Regular.ttf"
      j3w1zsh_run curl -fsSL "$font_url" -o "$font_download"
      [[ $(sha256sum "$font_download" | awk '{print $1}') == "$NERD_FONT_SHA256" ]] || j3w1zsh_die "Termux font checksum verification failed."
      [[ ! -e $font && ! -L $font ]] || j3w1zsh_backup_path "$font"
      j3w1zsh_run install -m 0644 "$font_download" "$font"
    fi
  fi
  j3w1zsh_link_managed "$J3W1ZSH_CONFIG_DIR/generated/theme/termux-colors.properties" "$termux_dir/colors.properties"
  j3w1zsh_run termux-reload-settings
  j3w1zsh_run mkdir -p "$HOME/storage/shared/Documents"
  j3w1zsh_set_zsh_setting J3W1ZSH_EDIT_ROOT "$HOME/storage/shared/Documents"
  j3w1zsh_note "Termux colors, Android clipboard, and shared Documents access are ready."
}
