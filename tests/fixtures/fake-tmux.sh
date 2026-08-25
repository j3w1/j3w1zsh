#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
list-sessions)
  while IFS= read -r session_name; do
    [[ -n $session_name ]] && printf '%s\t1 window(s)\tdetached\tcreated now\n' "$session_name"
  done <"$TMA_FAKE_STATE"
  ;;
has-session)
  target="${3#=}"
  grep -Fxq "$target" "$TMA_FAKE_STATE"
  ;;
kill-session)
  printf 'kill %s\n' "$3" >>"$TMA_FAKE_LOG"
  target="${3#=}"
  grep -Fxv "$target" "$TMA_FAKE_STATE" >"$TMA_FAKE_STATE.next" || true
  mv -- "$TMA_FAKE_STATE.next" "$TMA_FAKE_STATE"
  ;;
attach-session)
  printf 'attach %s\n' "$3" >>"$TMA_FAKE_LOG"
  ;;
switch-client)
  printf 'switch %s\n' "$3" >>"$TMA_FAKE_LOG"
  ;;
*)
  printf 'Unexpected fake tmux command: %s\n' "$*" >&2
  exit 1
  ;;
esac
