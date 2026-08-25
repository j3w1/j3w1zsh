#!/usr/bin/env bash

phase_20_packages() {
  [[ $J3W1ZSH_TEST_MODE != 1 || ${J3W1ZSH_TEST_PACKAGE_ADAPTERS:-0} == 1 ]] || return 0
  local manager
  manager="$(j3w1zsh_package_manager_for_platform)"
  j3w1zsh_install_package_set "$manager" "$(j3w1zsh_packages_for_manager_json "$manager")"
  j3w1zsh_install_package_set npm_global "$(j3w1zsh_packages_for_manager_json npm_global)"
  j3w1zsh_install_package_set pip_user "$(j3w1zsh_packages_for_manager_json pip_user)"
}
