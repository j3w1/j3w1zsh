#!/usr/bin/env bash

phase_90_verify() {
  [[ $J3W1ZSH_TEST_MODE != 1 || ${J3W1ZSH_TEST_VERIFY_ADAPTERS:-0} == 1 ]] || return 0
  local required=(bash git jq)
  j3w1zsh_preset_has_feature shell && required+=(zsh)
  j3w1zsh_preset_has_feature tmux && required+=(tmux)
  j3w1zsh_preset_has_feature neovim && required+=(nvim)
  j3w1zsh_preset_has_feature github && required+=(gh)
  j3w1zsh_preset_has_feature remote && required+=(ssh)
  if [[ $J3W1ZSH_NO_PACKAGES != 1 && $J3W1ZSH_PLATFORM == wsl ]] && j3w1zsh_preset_has_feature codex; then
    required+=(codex)
  fi
  local missing=() command_name
  for command_name in "${required[@]}"; do
    j3w1zsh_have "$command_name" || missing+=("$command_name")
  done
  ((${#missing[@]} == 0)) || j3w1zsh_die "Required commands are missing: ${missing[*]}"
  if j3w1zsh_preset_has_feature shell; then
    [[ -d $HOME/.oh-my-zsh/.git ]] || j3w1zsh_die "Pinned Oh My Zsh is missing."
    [[ $(git -C "$HOME/.oh-my-zsh" rev-parse HEAD 2>/dev/null || true) == "$OH_MY_ZSH_COMMIT" ]] ||
      j3w1zsh_die "Oh My Zsh does not match the tracked commit."
  fi
  [[ -x $HOME/.local/bin/j3w1zsh ]] || j3w1zsh_die "The j3w1zsh command is missing."
  if j3w1zsh_preset_has_feature shell; then
    [[ -L $HOME/.zshrc ]] || j3w1zsh_die "$HOME/.zshrc is not managed by j3w1zsh."
    zsh -n "$HOME/.zshrc"
  fi
  if j3w1zsh_preset_has_feature tmux; then
    [[ -L $HOME/.tmux.conf ]] || j3w1zsh_die "$HOME/.tmux.conf is not managed by j3w1zsh."
    [[ -x $HOME/.local/bin/tma ]] || j3w1zsh_die "The tmux picker is missing."
    local tmux_socket="j3w1zsh-verify-$$"
    tmux -f "$HOME/.tmux.conf" -L "$tmux_socket" new-session -d -s verify
    tmux -L "$tmux_socket" kill-server
  fi
  if j3w1zsh_preset_has_feature neovim; then
    [[ -L $HOME/.config/nvim ]] || j3w1zsh_die "$HOME/.config/nvim is not managed by j3w1zsh."
    env XDG_CONFIG_HOME="$HOME/.config" nvim --headless "+lua require('j3w1zsh.theme').setup()" +qa
  fi
  if j3w1zsh_preset_has_feature tmux || j3w1zsh_preset_has_feature neovim; then
    [[ -x $HOME/.local/bin/j3w1zsh-clipboard-copy ]] || j3w1zsh_die "The clipboard adapter is missing."
  fi
  if [[ $J3W1ZSH_PLATFORM == wsl ]]; then
    j3w1zsh_require_wsl_interop
  fi
}
