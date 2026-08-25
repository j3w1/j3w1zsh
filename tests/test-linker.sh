#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
test_root="$(mktemp -d)"
trap 'rm -rf -- "$test_root"' EXIT

export HOME="$test_root/home"
export XDG_STATE_HOME="$test_root/state"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_CACHE_HOME="$test_root/cache"
export J3W1ZSH_REPO_ROOT="$repo_root"
export J3W1ZSH_STATE_DIR="$XDG_STATE_HOME/j3w1zsh"
export J3W1ZSH_CONFIG_DIR="$XDG_CONFIG_HOME/j3w1zsh"
export J3W1ZSH_CACHE_DIR="$XDG_CACHE_HOME/j3w1zsh"
export J3W1ZSH_TEST_MODE=1
export J3W1ZSH_TEST_PLATFORM=termux
export J3W1ZSH_ASSUME_YES=1

mkdir -p "$HOME"
printf 'original zsh config\n' >"$HOME/.zshrc"

# shellcheck source=scripts/lib/core/init.sh
source "$repo_root/scripts/lib/core/init.sh"
j3w1zsh_ensure_dirs
j3w1zsh_link_managed "$repo_root/dotfiles/zsh/.zshrc" "$HOME/.zshrc"
j3w1zsh_link_managed "$repo_root/dotfiles/local-bin/.local/bin/tma" "$HOME/.local/bin/tma"

[[ -L $HOME/.zshrc ]]
[[ $(readlink -f -- "$HOME/.zshrc") == "$(readlink -f -- "$repo_root/dotfiles/zsh/.zshrc")" ]]
[[ -L $HOME/.local/bin/tma ]]
grep -Rqx 'original zsh config' "$J3W1ZSH_STATE_DIR/backups"
grep -q $'\t__MISSING__$' "$J3W1ZSH_BACKUP_DIR/manifest.tsv"

backup_count="$(find "$J3W1ZSH_STATE_DIR/backups" -mindepth 1 -maxdepth 1 -type d | wc -l)"
j3w1zsh_link_managed "$repo_root/dotfiles/zsh/.zshrc" "$HOME/.zshrc"
[[ $(find "$J3W1ZSH_STATE_DIR/backups" -mindepth 1 -maxdepth 1 -type d | wc -l) == "$backup_count" ]]

backup_id="$(basename -- "$J3W1ZSH_BACKUP_DIR")"
env J3W1ZSH_ASSUME_YES=1 "$repo_root/bin/j3w1zsh" restore "$backup_id" >/dev/null
[[ ! -L $HOME/.zshrc ]]
grep -qx 'original zsh config' "$HOME/.zshrc"
[[ ! -e $HOME/.local/bin/tma && ! -L $HOME/.local/bin/tma ]]
if env J3W1ZSH_ASSUME_YES=1 "$repo_root/bin/j3w1zsh" restore "$backup_id" >/dev/null 2>&1; then
  printf 'A consumed installer backup was incorrectly restored twice.\n' >&2
  exit 1
fi

outside="$test_root/outside"
mkdir -p "$outside"
ln -s "$outside" "$HOME/escape"
if (j3w1zsh_link_managed "$repo_root/dotfiles/zsh/.zshrc" "$HOME/escape/.zshrc") >/dev/null 2>&1; then
  printf 'Managed path escaped HOME through a symlink.\n' >&2
  exit 1
fi

printf 'Linker, conflict backup, restore, idempotence, and path-containment tests passed.\n'
