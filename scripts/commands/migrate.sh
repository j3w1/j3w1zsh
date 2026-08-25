#!/usr/bin/env bash

j3w1zsh_migrate_execute() {
  exec "$J3W1ZSH_REPO_ROOT/scripts/legacy/migrate-to-j3w1zsh.sh" "$1"
}

j3w1zsh_migrate_command() {
  local subcommand="${1:-help}"
  (($# == 0)) || shift
  (($# == 0)) || j3w1zsh_usage_error "migrate $subcommand accepts no additional arguments."
  case "$subcommand" in
  status) exec "$J3W1ZSH_REPO_ROOT/scripts/legacy/migrate-to-j3w1zsh.sh" --status ;;
  resume | rollback)
    j3w1zsh_plan_reset
    j3w1zsh_plan_add "migration-$subcommand" "migration-$subcommand" direct-argv-lifecycle migration "" "$J3W1ZSH_STATE_DIR/migrations" \
      "$subcommand the exact journalled major-install migration" false true migration-recovery true \
      "the migration journal records the completed bounded operation"
    j3w1zsh_execute_typed_callback "${J3W1ZSH_PLAN_ACTIONS[0]}" j3w1zsh_migrate_execute "--$subcommand"
    ;;
  help | -h | --help) printf 'Usage: j3w1zsh migrate status|resume|rollback\n' ;;
  *) j3w1zsh_usage_error "Unknown migrate command: $subcommand" ;;
  esac
}
