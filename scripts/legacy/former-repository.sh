#!/usr/bin/env bash

# Bounded former-identity adapter used only to recognize the canonical repository redirect.
j3w1zsh_legacy_canonical_url() {
  if [[ $J3W1ZSH_TEST_MODE == 1 && -n ${J3W1ZSH_TEST_OLD_CANONICAL_URL:-} ]]; then
    printf '%s\n' "$J3W1ZSH_TEST_OLD_CANONICAL_URL"
  else
    printf '%s\n' 'https://github.com/j3w1/bloody-writer.git'
  fi
}
