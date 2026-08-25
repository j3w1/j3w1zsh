#!/usr/bin/env bash

phase_70_codex() {
  [[ $J3W1ZSH_TEST_MODE == 1 ]] && return 0
  [[ $J3W1ZSH_PLATFORM == wsl ]] || return 0
  local codex_bin="$HOME/.local/bin/codex"
  local installed_version=""
  [[ ! -x $codex_bin ]] || installed_version="$(env CODEX_HOME="$HOME/.codex" "$codex_bin" --version 2>/dev/null | awk '{print $2}')"
  if [[ $installed_version != "$CODEX_VERSION" ]]; then
    local installer="$J3W1ZSH_CACHE_DIR/codex-install.sh"
    local installer_url="https://github.com/openai/codex/releases/download/rust-v$CODEX_VERSION/install.sh"
    j3w1zsh_run curl -fsSL "$installer_url" -o "$installer"
    [[ $(sha256sum "$installer" | awk '{print $1}') == "$CODEX_INSTALLER_SHA256" ]] ||
      j3w1zsh_die "Codex installer checksum verification failed."
    sh -n "$installer"
    j3w1zsh_run env CODEX_HOME="$HOME/.codex" CODEX_NON_INTERACTIVE=true PATH="$HOME/.local/bin:$PATH" \
      sh "$installer" --release "$CODEX_VERSION"
  fi
  j3w1zsh_write_if_missing "$HOME/.codex/config.toml" "$J3W1ZSH_REPO_ROOT/templates/codex-config.toml"
  if ! env CODEX_HOME="$HOME/.codex" "$codex_bin" login status >/dev/null 2>&1; then
    j3w1zsh_warn "Codex is installed but authentication remains user-owned: run 'codex login --device-auth'."
  fi
}
