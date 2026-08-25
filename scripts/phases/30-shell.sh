#!/usr/bin/env bash

phase_30_shell() {
  [[ $J3W1ZSH_TEST_MODE == 1 ]] && return 0
  local omz="$HOME/.oh-my-zsh"
  local current_commit=""
  [[ ! -d $omz/.git ]] || current_commit="$(git -C "$omz" rev-parse HEAD 2>/dev/null || true)"
  if [[ $J3W1ZSH_NO_PACKAGES == 1 && $current_commit != "$OH_MY_ZSH_COMMIT" ]]; then
    j3w1zsh_warn "Pinned Oh My Zsh prerequisites are missing or differ; package-free mode did not acquire or update them."
  elif [[ $J3W1ZSH_NO_PACKAGES == 1 ]]; then
    j3w1zsh_note "Pinned Oh My Zsh is already available; package-free mode made no acquisition."
  elif [[ $current_commit == "$OH_MY_ZSH_COMMIT" ]] && [[ -z $(git -C "$omz" status --porcelain 2>/dev/null) ]]; then
    j3w1zsh_note "Oh My Zsh is already at the tracked commit."
  else
    if [[ -e $omz || -L $omz ]]; then
      j3w1zsh_confirm "Back up the existing Oh My Zsh tree and install the tracked commit?" || return 1
      j3w1zsh_backup_path "$omz"
    fi
    j3w1zsh_run git clone --filter=blob:none https://github.com/ohmyzsh/ohmyzsh.git "$omz"
    j3w1zsh_run git -C "$omz" checkout --detach "$OH_MY_ZSH_COMMIT"
  fi

  local zsh_path current_shell
  zsh_path="$(command -v zsh)"
  if [[ $J3W1ZSH_PLATFORM == termux ]]; then
    current_shell="${SHELL:-}"
    [[ $current_shell == "$zsh_path" ]] || j3w1zsh_run chsh -s "$zsh_path"
  else
    current_shell="$(getent passwd "${USER:-$(id -un)}" | cut -d: -f7)"
    [[ $current_shell == "$zsh_path" ]] || j3w1zsh_run sudo usermod --shell "$zsh_path" "${USER:-$(id -un)}"
  fi
}
