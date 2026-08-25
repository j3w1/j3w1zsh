#!/usr/bin/env bash

phase_40_config() {
  local settings="$J3W1ZSH_CONFIG_DIR/settings.zsh"
  if j3w1zsh_preset_has_feature shell && [[ -L $settings ]]; then
    j3w1zsh_die "User-owned settings must be a regular file, not a symlink: $settings"
  fi
  j3w1zsh_link_managed "$J3W1ZSH_REPO_ROOT/bin/j3w1zsh" "$HOME/.local/bin/j3w1zsh"
  if j3w1zsh_preset_has_feature shell; then
    j3w1zsh_link_managed "$J3W1ZSH_REPO_ROOT/dotfiles/zsh/.zshrc" "$HOME/.zshrc"
    j3w1zsh_write_if_missing "$settings" "$J3W1ZSH_REPO_ROOT/dotfiles/zsh/settings.zsh.example"
    [[ $J3W1ZSH_DRY_RUN == 1 ]] || chmod 600 "$settings"
  fi
  if j3w1zsh_preset_has_feature tmux; then
    j3w1zsh_link_managed "$J3W1ZSH_REPO_ROOT/dotfiles/tmux/.tmux.conf" "$HOME/.tmux.conf"
    j3w1zsh_link_managed "$J3W1ZSH_REPO_ROOT/dotfiles/local-bin/.local/bin/tma" "$HOME/.local/bin/tma"
  fi
  if j3w1zsh_preset_has_feature neovim; then
    j3w1zsh_link_managed "$J3W1ZSH_REPO_ROOT/dotfiles/nvim/.config/nvim" "$HOME/.config/nvim"
  fi
  if j3w1zsh_preset_has_feature tmux || j3w1zsh_preset_has_feature neovim; then
    j3w1zsh_link_managed "$J3W1ZSH_REPO_ROOT/dotfiles/local-bin/.local/bin/j3w1zsh-clipboard-copy" "$HOME/.local/bin/j3w1zsh-clipboard-copy"
  fi
}
