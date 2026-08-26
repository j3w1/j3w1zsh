#!/usr/bin/env bash

readonly J3W1ZSH_LAZY_REPOSITORY='https://github.com/folke/lazy.nvim.git'

j3w1zsh_neovim_tracked_lock_path() {
  if [[ $J3W1ZSH_TEST_MODE == 1 && -n ${J3W1ZSH_TEST_NEOVIM_TRACKED_LOCK:-} ]]; then
    printf '%s\n' "$J3W1ZSH_TEST_NEOVIM_TRACKED_LOCK"
  else
    printf '%s\n' "$J3W1ZSH_REPO_ROOT/dotfiles/nvim/.config/nvim/lazy-lock.json"
  fi
}

j3w1zsh_neovim_runtime_lock_path() {
  printf '%s/nvim/j3w1zsh/lazy-lock.json\n' "${XDG_STATE_HOME:-$HOME/.local/state}"
}

j3w1zsh_neovim_plugin_root() {
  printf '%s/nvim/lazy\n' "${XDG_DATA_HOME:-$HOME/.local/share}"
}

j3w1zsh_neovim_validate_lock() {
  local lockfile="$1" label="$2"
  local expected_names duplicate_name branch
  local -a encoded_names=()
  [[ -f $lockfile && ! -L $lockfile ]] ||
    j3w1zsh_die "$label Neovim lock must be a regular file: $lockfile"
  jq -e '
    type == "object" and length > 0 and
    all(to_entries[];
      (.key | type == "string" and test("^[A-Za-z0-9][A-Za-z0-9._-]*$")) and
      (.value | type == "object" and (keys | sort) == ["branch", "commit"]) and
      (.value.branch | type == "string" and test("^[A-Za-z0-9][A-Za-z0-9._/-]*$")) and
      (.value.commit | type == "string" and test("^[0-9a-f]{40}$"))
    )
  ' "$lockfile" >/dev/null 2>&1 ||
    j3w1zsh_die "$label Neovim lock is malformed or contains an ambiguous managed plugin identity: $lockfile"
  expected_names="$(jq length "$lockfile")"
  mapfile -t encoded_names < <(
    tr -d '\r\n' <"$lockfile" |
      grep -oE '"[A-Za-z0-9][A-Za-z0-9._-]*"[[:space:]]*:[[:space:]]*\{' |
      sed -E 's/^"([^"]+)".*/\1/'
  )
  duplicate_name="$(printf '%s\n' "${encoded_names[@]}" | LC_ALL=C sort | uniq -d | sed -n '1p')"
  [[ -z $duplicate_name ]] ||
    j3w1zsh_die "$label Neovim lock contains a duplicate managed plugin identity: $duplicate_name"
  ((${#encoded_names[@]} == expected_names)) ||
    j3w1zsh_die "$label Neovim lock contains an encoded or ambiguous managed plugin identity: $lockfile"
  while IFS= read -r branch; do
    git check-ref-format --branch "$branch" >/dev/null 2>&1 ||
      j3w1zsh_die "$label Neovim lock contains an invalid managed plugin branch: $branch"
  done < <(jq -r '.[].branch' "$lockfile")
}

j3w1zsh_neovim_validate_plugin_repository() {
  local plugin_root="$1" name="$2" expected_commit="$3"
  local plugin_dir="$plugin_root/$name" resolved_plugin resolved_toplevel actual_commit
  [[ -d $plugin_dir && ! -L $plugin_dir ]] ||
    j3w1zsh_die "Managed Neovim plugin is missing or ambiguous: $name"
  [[ -d $plugin_dir/.git && ! -L $plugin_dir/.git ]] ||
    j3w1zsh_die "Managed Neovim plugin is not an independent Git repository: $name"
  resolved_plugin="$(readlink -f -- "$plugin_dir")"
  resolved_toplevel="$(git -C "$plugin_dir" rev-parse --show-toplevel 2>/dev/null || true)"
  [[ -n $resolved_plugin && -n $resolved_toplevel ]] ||
    j3w1zsh_die "Managed Neovim plugin Git state is unreadable: $name"
  resolved_toplevel="$(readlink -f -- "$resolved_toplevel")"
  [[ $resolved_toplevel == "$resolved_plugin" ]] ||
    j3w1zsh_die "Managed Neovim plugin resolves to an unexpected Git repository root: $name"
  actual_commit="$(git -C "$plugin_dir" rev-parse --verify 'HEAD^{commit}' 2>/dev/null || true)"
  [[ $actual_commit == "$expected_commit" ]] ||
    j3w1zsh_die "Managed Neovim plugin does not match the reviewed lock: $name"
}

j3w1zsh_neovim_verify_runtime() {
  local tracked_lock runtime_lock plugin_root resolved_root name expected_commit
  tracked_lock="$(j3w1zsh_neovim_tracked_lock_path)"
  runtime_lock="$(j3w1zsh_neovim_runtime_lock_path)"
  plugin_root="$(j3w1zsh_neovim_plugin_root)"
  j3w1zsh_validate_home_target "$runtime_lock"
  j3w1zsh_validate_home_target "$plugin_root"
  j3w1zsh_neovim_validate_lock "$tracked_lock" "Tracked"
  j3w1zsh_neovim_validate_lock "$runtime_lock" "Runtime"
  jq -e -s 'length == 2 and .[0] == .[1]' "$tracked_lock" "$runtime_lock" >/dev/null 2>&1 ||
    j3w1zsh_die "Runtime Neovim lock does not semantically match the reviewed tracked lock."
  [[ -d $plugin_root && ! -L $plugin_root ]] ||
    j3w1zsh_die "Managed Neovim plugin root is missing or ambiguous: $plugin_root"
  resolved_root="$(readlink -f -- "$plugin_root")"
  [[ -n $resolved_root ]] || j3w1zsh_die "Managed Neovim plugin root cannot be resolved."
  while IFS=$'\t' read -r name expected_commit; do
    j3w1zsh_neovim_validate_plugin_repository "$resolved_root" "$name" "$expected_commit"
  done < <(jq -r 'to_entries[] | [.key, .value.commit] | @tsv' "$tracked_lock")
}

j3w1zsh_neovim_reconcile_manager() {
  local tracked_lock plugin_root manager_dir expected_branch expected_commit origin resolved_manager resolved_toplevel
  tracked_lock="$(j3w1zsh_neovim_tracked_lock_path)"
  plugin_root="$(j3w1zsh_neovim_plugin_root)"
  manager_dir="$plugin_root/lazy.nvim"
  j3w1zsh_neovim_validate_lock "$tracked_lock" "Tracked"
  expected_branch="$(jq -r '."lazy.nvim".branch // empty' "$tracked_lock")"
  expected_commit="$(jq -r '."lazy.nvim".commit // empty' "$tracked_lock")"
  [[ $expected_branch =~ ^[A-Za-z0-9][A-Za-z0-9._/-]*$ ]] ||
    j3w1zsh_die "The reviewed Neovim lock does not name a safe lazy.nvim branch."
  [[ $expected_commit =~ ^[0-9a-f]{40}$ ]] ||
    j3w1zsh_die "The reviewed Neovim lock does not pin lazy.nvim."
  j3w1zsh_validate_home_target "$plugin_root"
  if [[ -e $plugin_root || -L $plugin_root ]]; then
    [[ -d $plugin_root && ! -L $plugin_root ]] ||
      j3w1zsh_die "Managed Neovim plugin root is non-directory or ambiguous: $plugin_root"
  fi
  j3w1zsh_validate_home_target "$manager_dir"
  if [[ ! -e $manager_dir && ! -L $manager_dir ]]; then
    j3w1zsh_run mkdir -p "$manager_dir"
    j3w1zsh_run git -C "$manager_dir" init
    j3w1zsh_run git -C "$manager_dir" remote add origin "$J3W1ZSH_LAZY_REPOSITORY"
  fi
  [[ -d $manager_dir && ! -L $manager_dir && -d $manager_dir/.git && ! -L $manager_dir/.git ]] ||
    j3w1zsh_die "The lazy.nvim manager path is missing, non-Git, or ambiguous."
  resolved_manager="$(readlink -f -- "$manager_dir")"
  resolved_toplevel="$(git -C "$manager_dir" rev-parse --show-toplevel 2>/dev/null || true)"
  [[ -n $resolved_manager && -n $resolved_toplevel ]] ||
    j3w1zsh_die "The lazy.nvim manager repository cannot be resolved."
  resolved_toplevel="$(readlink -f -- "$resolved_toplevel")"
  [[ $resolved_toplevel == "$resolved_manager" ]] ||
    j3w1zsh_die "The lazy.nvim manager resolves to an unexpected Git repository root."
  origin="$(git -C "$manager_dir" remote get-url origin 2>/dev/null || true)"
  [[ $origin == "$J3W1ZSH_LAZY_REPOSITORY" ]] ||
    j3w1zsh_die "The lazy.nvim manager has an unrecognized origin."
  if ! git -C "$manager_dir" show-ref --verify --quiet "refs/remotes/origin/$expected_branch" ||
    ! git -C "$manager_dir" cat-file -e "$expected_commit^{commit}" 2>/dev/null; then
    j3w1zsh_run git -C "$manager_dir" fetch --filter=blob:none --no-tags origin \
      "refs/heads/$expected_branch:refs/remotes/origin/$expected_branch"
  fi
  if ! git -C "$manager_dir" cat-file -e "$expected_commit^{commit}" 2>/dev/null; then
    j3w1zsh_run git -C "$manager_dir" fetch --filter=blob:none --no-tags origin "$expected_commit"
  fi
  j3w1zsh_run git -C "$manager_dir" remote set-head origin "$expected_branch"
  j3w1zsh_run git -C "$manager_dir" checkout --detach "$expected_commit"
  [[ $(git -C "$manager_dir" rev-parse --verify 'HEAD^{commit}' 2>/dev/null || true) == "$expected_commit" ]] ||
    j3w1zsh_die "lazy.nvim did not converge to the reviewed commit."
}
