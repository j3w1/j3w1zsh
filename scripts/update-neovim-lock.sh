#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
tracked_lock="$repo_root/dotfiles/nvim/.config/nvim/lazy-lock.json"

command -v nvim >/dev/null 2>&1 || {
  printf 'ERROR: Neovim is required to update the plugin lock.\n' >&2
  exit 1
}
[[ -f $tracked_lock ]] || {
  printf 'ERROR: Tracked Neovim lockfile is missing: %s\n' "$tracked_lock" >&2
  exit 1
}

printf 'Updating the reviewed repository lockfile in maintainer mode...\n'
env \
  J3W1ZSH_MAINTAINER=1 \
  XDG_CONFIG_HOME="$repo_root/dotfiles/nvim/.config" \
  nvim --headless "+Lazy! update" +qa

printf '\nReview before committing:\n'
printf '  git diff -- %q\n' "$tracked_lock"
printf '  tests/run.sh\n'
