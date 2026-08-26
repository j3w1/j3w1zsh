#!/usr/bin/env bash

phase_60_neovim() {
  [[ $J3W1ZSH_TEST_MODE != 1 || ${J3W1ZSH_TEST_NEOVIM_ADAPTERS:-0} == 1 ]] || return 0
  j3w1zsh_clear_phase 60-neovim
  local tracked_lock runtime_lock runtime_lock_dir
  tracked_lock="$(j3w1zsh_neovim_tracked_lock_path)"
  runtime_lock="$(j3w1zsh_neovim_runtime_lock_path)"
  runtime_lock_dir="$(dirname -- "$runtime_lock")"
  j3w1zsh_neovim_validate_lock "$tracked_lock" "Tracked"
  j3w1zsh_validate_home_target "$runtime_lock"
  j3w1zsh_have nvim || j3w1zsh_die "Neovim is missing; phase 60 cannot verify the reviewed plugin state."
  if [[ $J3W1ZSH_NO_PACKAGES == 1 ]]; then
    j3w1zsh_run mkdir -p "$runtime_lock_dir"
    j3w1zsh_run cp -- "$tracked_lock" "$runtime_lock"
    j3w1zsh_neovim_verify_runtime
    j3w1zsh_note "Package-free mode verified the reviewed lock and plugin commits without acquiring plugins or spell files."
    return 0
  fi
  local spell_dir="$HOME/.local/share/nvim/site/spell"
  j3w1zsh_run mkdir -p "$spell_dir"
  local base_url="https://ftp.nluug.nl/pub/vim/runtime/spell"
  local entries=(
    "en.utf-8.spl:fecabdc949b6a39d32c0899fa2545eab25e63f2ed0a33c4ad1511426384d3070"
    "en.utf-8.sug:5b6e5e6165582d2fd7a1bfa41fbce8242c72476222c55d17c2aa2ba933c932ec"
    "es.utf-8.spl:963637ac925cf8a51bf207fac392d6b4c69795711dcc2d4809b78846ae367be3"
    "es.utf-8.sug:e70f3478aa653c2ae905086328fbff4e43bd646d76534645f50a65344801bd6c"
  )
  if [[ $J3W1ZSH_TEST_MODE != 1 ]]; then
    local entry file expected actual temporary
    for entry in "${entries[@]}"; do
      file="${entry%%:*}"
      expected="${entry#*:}"
      actual="$(sha256sum "$spell_dir/$file" 2>/dev/null | awk '{print $1}')"
      [[ $actual != "$expected" ]] || continue
      temporary="$J3W1ZSH_CACHE_DIR/$file.download"
      j3w1zsh_run curl -fsSL "$base_url/$file" -o "$temporary"
      actual="$(sha256sum "$temporary" | awk '{print $1}')"
      [[ $actual == "$expected" ]] || j3w1zsh_die "Checksum verification failed for $file."
      j3w1zsh_run install -m 0644 "$temporary" "$spell_dir/$file"
    done
  fi
  j3w1zsh_run mkdir -p "$runtime_lock_dir"
  j3w1zsh_run cp -- "$tracked_lock" "$runtime_lock"
  j3w1zsh_neovim_reconcile_manager
  j3w1zsh_run env J3W1ZSH_NEOVIM_INSTALL_MISSING=1 XDG_CONFIG_HOME="$HOME/.config" \
    nvim --headless +qa
  j3w1zsh_run cp -- "$tracked_lock" "$runtime_lock"
  j3w1zsh_run env J3W1ZSH_NEOVIM_RECONCILE=1 XDG_CONFIG_HOME="$HOME/.config" \
    nvim --headless '+Lazy! restore' '+Lazy! clean' +qa
  j3w1zsh_neovim_verify_runtime
  j3w1zsh_run env J3W1ZSH_NEOVIM_VERIFY=1 XDG_CONFIG_HOME="$HOME/.config" \
    nvim --headless '+checkhealth vim.lsp' +qa
}
