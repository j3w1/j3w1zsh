#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
test_root="$(mktemp -d)"
trap 'rm -rf -- "$test_root"' EXIT
mkdir -p "$test_root/bin"

export TMA_FAKE_STATE="$test_root/state"
export TMA_FAKE_LOG="$test_root/log"
printf 'j3w1zsh\nsecond\n' >"$TMA_FAKE_STATE"
: >"$TMA_FAKE_LOG"

apply_fake_tmux="$test_root/bin/tmux"
cp "$repo_root/tests/fixtures/fake-tmux.sh" "$apply_fake_tmux"
chmod +x "$apply_fake_tmux"

tma="$repo_root/dotfiles/local-bin/.local/bin/tma"
help_output="$(PATH="$test_root/bin:$PATH" "$tma" --help)"
grep -q 'Ctrl-X' <<<"$help_output"
grep -q 'confirmation' <<<"$help_output"
grep -q 'Termux on Android' <<<"$help_output"
grep -q 'j3w1zsh' <<<"$help_output"

PATH="$test_root/bin:$PATH" "$tma" second
grep -qx 'attach =second' "$TMA_FAKE_LOG"
TMUX=active PATH="$test_root/bin:$PATH" "$tma" j3w1zsh
grep -qx 'switch =j3w1zsh' "$TMA_FAKE_LOG"

printf 'n' | PATH="$test_root/bin:$PATH" "$tma" --kill j3w1zsh >/dev/null
grep -Fxq j3w1zsh "$TMA_FAKE_STATE"
if grep -q '^kill ' "$TMA_FAKE_LOG"; then
  printf 'Declined kill changed the tmux fixture.\n' >&2
  exit 1
fi

printf 'y' | PATH="$test_root/bin:$PATH" "$tma" --kill j3w1zsh >/dev/null
grep -qx 'kill =j3w1zsh' "$TMA_FAKE_LOG"

if printf 'y' | PATH="$test_root/bin:$PATH" "$tma" --kill missing >/dev/null 2>&1; then
  printf 'tma accepted a missing exact session target.\n' >&2
  exit 1
fi

printf 'tma help, multi-client attach, exact targeting, and confirmed-kill tests passed.\n'
