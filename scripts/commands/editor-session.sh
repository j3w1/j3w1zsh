#!/usr/bin/env bash

j3w1zsh_edit_execute() {
  exec nvim -- "$1"
}

j3w1zsh_edit_command() {
  (($# <= 1)) || j3w1zsh_usage_error "edit accepts at most one path."
  local target="${1:-${J3W1ZSH_EDIT_ROOT:-$HOME/Documents}}"
  j3w1zsh_plan_reset
  j3w1zsh_plan_add edit edit direct-argv-lifecycle user "" "$target" \
    "open the exact user-selected path in Neovim" false false "" true "Neovim receives the path after an argv separator"
  j3w1zsh_execute_typed_callback "${J3W1ZSH_PLAN_ACTIONS[0]}" j3w1zsh_edit_execute "$target"
}

j3w1zsh_attach_validate_session() {
  [[ $1 =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] || j3w1zsh_usage_error "Invalid tmux session name: $1"
}

j3w1zsh_attach_execute() {
  local mode="$1" session="${2:-}"
  case "$mode" in
  picker) exec "$J3W1ZSH_REPO_ROOT/dotfiles/local-bin/.local/bin/tma" ;;
  new | direct) exec tmux new-session -A -s "$session" ;;
  kill) exec "$J3W1ZSH_REPO_ROOT/dotfiles/local-bin/.local/bin/tma" --kill "$session" ;;
  *) j3w1zsh_die "Unknown attach adapter mode: $mode" ;;
  esac
}

j3w1zsh_attach_planned_execute() {
  local mode="$1" session="${2:-}"
  j3w1zsh_plan_reset
  j3w1zsh_plan_add "attach-$mode" attach direct-argv-lifecycle user "" "" \
    "run the bounded tmux $mode operation${session:+ for exact session $session}" false "$([[ $mode == kill ]] && printf true || printf false)" "" true \
    "tmux receives only validated direct argv and preserves other clients"
  j3w1zsh_execute_typed_callback "${J3W1ZSH_PLAN_ACTIONS[0]}" j3w1zsh_attach_execute "$mode" "$session"
}

j3w1zsh_attach_command() {
  if (($# == 0)); then
    j3w1zsh_attach_planned_execute picker
  fi
  case "$1" in
  --list)
    (($# == 1)) || j3w1zsh_usage_error "attach --list accepts no additional arguments."
    exec tmux list-sessions
    ;;
  --new)
    (($# == 2)) || j3w1zsh_usage_error "attach --new requires exactly one session name."
    j3w1zsh_attach_validate_session "$2"
    j3w1zsh_attach_planned_execute new "$2"
    ;;
  --kill)
    (($# == 2)) || j3w1zsh_usage_error "attach --kill requires exactly one session name."
    j3w1zsh_attach_validate_session "$2"
    j3w1zsh_attach_planned_execute kill "$2"
    ;;
  --*) j3w1zsh_usage_error "Unknown attach option: $1" ;;
  *)
    (($# == 1)) || j3w1zsh_usage_error "attach accepts at most one session name."
    j3w1zsh_attach_validate_session "$1"
    j3w1zsh_attach_planned_execute direct "$1"
    ;;
  esac
}
