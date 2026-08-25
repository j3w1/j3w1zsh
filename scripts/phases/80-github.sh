#!/usr/bin/env bash

phase_80_github() {
  [[ $J3W1ZSH_TEST_MODE == 1 ]] && return 0
  if ! gh auth status >/dev/null 2>&1; then
    [[ -t 0 ]] || j3w1zsh_die "GitHub authentication requires an interactive terminal."
    j3w1zsh_run gh auth login --web --git-protocol ssh --skip-ssh-key --scopes admin:public_key
  fi
  local login user_id default_name default_email git_name git_email
  login="$(gh api user --jq .login)"
  user_id="$(gh api user --jq .id)"
  default_name="$(gh api user --jq '.name // .login')"
  default_email="${user_id}+${login}@users.noreply.github.com"
  git_name="$(git config --global user.name || true)"
  git_email="$(git config --global user.email || true)"
  [[ -n $git_name ]] || j3w1zsh_run git config --global user.name "$default_name"
  [[ -n $git_email ]] || j3w1zsh_run git config --global user.email "$default_email"
  j3w1zsh_run git config --global init.defaultBranch main
  j3w1zsh_note "GitHub login $login is active; SSH key selection remains user-owned."
}
