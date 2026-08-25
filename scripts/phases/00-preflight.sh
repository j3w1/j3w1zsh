#!/usr/bin/env bash

phase_00_preflight() {
  j3w1zsh_platform_preflight
  j3w1zsh_note "User: ${USER:-$(id -un)}"
  j3w1zsh_note "Platform: $(j3w1zsh_platform_label)"
  j3w1zsh_note "Repository: $J3W1ZSH_REPO_ROOT"
}
