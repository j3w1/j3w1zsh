#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
test_root="$(mktemp -d)"
trap 'rm -rf -- "$test_root"' EXIT

mkdir -p "$test_root/home/.oh-my-zsh" "$test_root/home/.local/bin"
: >"$test_root/home/.oh-my-zsh/oh-my-zsh.sh"
ln -s "$repo_root/bin/j3w1zsh" "$test_root/home/.local/bin/j3w1zsh"

HOME="$test_root/home" USER="inherited-user-does-not-match" \
  J3W1ZSH_ZSHRC="$repo_root/dotfiles/zsh/.zshrc" \
  zsh -dfc '
    source "$J3W1ZSH_ZSHRC"
    [[ $path[1] == "$HOME/.local/bin" ]]
    [[ ${path[(I)$HOME/.local/bin]} -eq 1 ]]
    [[ $(command -v j3w1zsh) == "$HOME/.local/bin/j3w1zsh" ]]
    [[ -n "$USERNAME" ]]
    [[ "$USER" != "$USERNAME" ]]
    [[ "$DEFAULT_USER" == "$USERNAME" ]]
    [[ -z "$ZSH_THEME" ]]
    [[ "$PROMPT" == *J3W1ZSH_COLOR_BRIGHT_RED* ]]
  '

printf 'Zsh command path and local-user prompt suppression tests passed.\n'
