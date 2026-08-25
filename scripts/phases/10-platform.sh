#!/usr/bin/env bash

phase_10_platform() {
  if [[ $J3W1ZSH_PACKAGES_ONLY == 1 ]]; then
    j3w1zsh_note "Package-only mode performs no platform host reconciliation."
    return 0
  fi
  "j3w1zsh_platform_configure_${J3W1ZSH_PLATFORM}"
}
