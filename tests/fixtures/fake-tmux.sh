#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
list-sessions)
  [[ ${2:-} == -F && $# == 3 ]]
  printf '%s' "$3" >"$TMA_FAKE_FORMAT"
  while IFS=$'\t' read -r session_name session_state; do
    [[ -n $session_name ]] || continue
    row="$3"
    row="${row//'#{session_name}'/$session_name}"
    row="${row//'#{session_windows}'/1}"
    row="${row//\#\{[?]session_attached,attached,detached\}/$session_state}"
    row="${row//'#{t:session_created}'/now}"
    printf '%s\n' "$row"
  done <"$TMA_FAKE_STATE"
  ;;
has-session)
  target="${3#=}"
  awk -F '\t' -v target="$target" '$1 == target { found=1 } END { exit !found }' "$TMA_FAKE_STATE"
  ;;
kill-session)
  printf 'kill %s\n' "$3" >>"$TMA_FAKE_LOG"
  target="${3#=}"
  awk -F '\t' -v target="$target" '$1 != target' "$TMA_FAKE_STATE" >"$TMA_FAKE_STATE.next"
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
