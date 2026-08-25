#!/usr/bin/env bash

j3w1zsh_help_overview() {
  cat <<'EOF'
j3w1zsh — one shell. every machine. zero compromise.

Usage:
  j3w1zsh help [COMMAND]
  j3w1zsh install [OPTIONS]
  j3w1zsh plan [FILE] [OPTIONS]
  j3w1zsh update [--dry-run] [--yes] [--configure-upstream]
  j3w1zsh update wiki
  j3w1zsh migrate status|resume|rollback
  j3w1zsh status [--json]
  j3w1zsh doctor [--json]
  j3w1zsh platform [--json]
  j3w1zsh backup [--dry-run]
  j3w1zsh restore [BACKUP_ID] [--dry-run]
  j3w1zsh reset-phase PHASE
  j3w1zsh edit [PATH]
  j3w1zsh attach [SESSION]|--list|--new NAME|--kill NAME
  j3w1zsh remote setup-host|configure-client|attach|status
  j3w1zsh packages plan|status|prune
  j3w1zsh theme list|show|current|apply
  j3w1zsh workspace scan|validate|plan|audit|apply|status|resume|migrate
  j3w1zsh wiki sync|status|context|publish

Global output options may appear before or after the command until --:
  --json                 Emit one stable JSON envelope.
  --plain                Use undecorated ASCII output.
  --color=auto|always|never

Supported install targets:
  native official Arch Linux
  official Arch Linux under Windows WSL 2
  native main Termux on Android

Exit codes:
  0 success or no required change
  1 validation, verification, runtime, or health failure
  2 invalid command, option, or argument
  20 external/manual checkpoint required
  21 protected authored, staged, ahead, or divergent state requires owner review
EOF
}

j3w1zsh_help_install() {
  cat <<'EOF'
Usage: j3w1zsh install [OPTIONS]

  --preset j3w1|minimal|FILE
  --theme NAME
  --workspace FILE
  --no-packages, --do-not-install-anything, -dnia
  --packages-only
  --dry-run
  --yes
  --force
  --from PHASE
  --only PHASE

--no-packages reconciles configuration using available tools and reports missing
prerequisites without installing them. It is incompatible with --packages-only
and --workspace. --packages-only never runs file or lifecycle phases.
EOF
}

j3w1zsh_help_edit() {
  cat <<'EOF'
Usage: j3w1zsh edit [PATH]

Opens Neovim with direct argv: nvim -- PATH. Without PATH, the command uses
J3W1ZSH_EDIT_ROOT and otherwise defaults to $HOME/Documents.
EOF
}

j3w1zsh_help_remote() {
  cat <<'EOF'
Usage:
  j3w1zsh remote setup-host
  j3w1zsh remote configure-client [--host HOST] [--user USER]
  j3w1zsh remote attach [SESSION]
  j3w1zsh remote status [--json]

setup-host is available on native Arch and WSL. configure-client and attach are
the native Termux client flow. Credentials and authentication remain user-owned.
EOF
}

j3w1zsh_help_plan() {
  cat <<'EOF'
Usage: j3w1zsh plan [FILE] [--preset NAME|FILE] [--theme NAME] [--json]

Without FILE, the command checks exactly the current Git repository root for
j3w1zsh.workspace.json; outside Git it checks only the current directory. It
never recursively searches HOME or parent repositories.
EOF
}

j3w1zsh_help_command() {
  local topic="${1:-}"
  case "$topic" in
  "") j3w1zsh_help_overview ;;
  install) j3w1zsh_help_install ;;
  edit) j3w1zsh_help_edit ;;
  remote) j3w1zsh_help_remote ;;
  plan) j3w1zsh_help_plan ;;
  help | status | doctor | platform | update | migrate | backup | restore | reset-phase | attach | packages | theme | workspace | wiki)
    printf 'Run j3w1zsh help for the complete command summary.\n'
    ;;
  *) j3w1zsh_usage_error "Unknown help topic: $topic" ;;
  esac
}
