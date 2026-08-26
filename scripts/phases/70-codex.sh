#!/usr/bin/env bash

readonly J3W1ZSH_CODEX_STABLE_CHANNEL_URL="https://releases.openai.com/codex/channels/latest"

j3w1zsh_codex_version_valid() {
  [[ $1 =~ ^[0-9]{1,9}\.[0-9]{1,9}\.[0-9]{1,9}$ ]]
}

j3w1zsh_codex_version_at_least() {
  local installed="$1" required="$2" index
  local installed_parts=() required_parts=()
  j3w1zsh_codex_version_valid "$installed" && j3w1zsh_codex_version_valid "$required" || return 1
  IFS=. read -r -a installed_parts <<<"$installed"
  IFS=. read -r -a required_parts <<<"$required"
  for index in 0 1 2; do
    if ((10#${installed_parts[$index]} > 10#${required_parts[$index]})); then
      return 0
    fi
    if ((10#${installed_parts[$index]} < 10#${required_parts[$index]})); then
      return 1
    fi
  done
  return 0
}

j3w1zsh_codex_current_stable_version() {
  local metadata tag
  if [[ $J3W1ZSH_TEST_MODE == 1 && ${J3W1ZSH_TEST_CODEX_ADAPTERS:-0} == 1 && -n ${J3W1ZSH_TEST_CODEX_CHANNEL_FILE:-} ]]; then
    [[ -f $J3W1ZSH_TEST_CODEX_CHANNEL_FILE && ! -L $J3W1ZSH_TEST_CODEX_CHANNEL_FILE ]] ||
      j3w1zsh_die "Test Codex channel fixture must be a regular file."
    metadata="$(<"$J3W1ZSH_TEST_CODEX_CHANNEL_FILE")"
  else
    metadata="$(curl --proto '=https' --tlsv1.2 --max-time 30 -fsSL "$J3W1ZSH_CODEX_STABLE_CHANNEL_URL")" ||
      j3w1zsh_die "Unable to resolve OpenAI's current stable Codex release."
  fi
  tag="$(jq -er '.tag_name | select(type == "string" and test("^rust-v[0-9]{1,9}\\.[0-9]{1,9}\\.[0-9]{1,9}$"))' <<<"$metadata")" ||
    j3w1zsh_die "OpenAI's current stable Codex channel returned an invalid release tag."
  printf '%s\n' "${tag#rust-v}"
}

j3w1zsh_codex_installed_version() {
  local codex_bin="$1"
  [[ -x $codex_bin ]] || return 0
  env CODEX_HOME="$HOME/.codex" "$codex_bin" --version 2>/dev/null |
    awk 'NR == 1 && $1 == "codex-cli" { print $2 }'
}

j3w1zsh_codex_download_installer() {
  local installer="$1"
  local installer_url="https://github.com/openai/codex/releases/download/rust-v$CODEX_INSTALLER_VERSION/install.sh"
  if [[ $J3W1ZSH_TEST_MODE == 1 && ${J3W1ZSH_TEST_CODEX_ADAPTERS:-0} == 1 && -n ${J3W1ZSH_TEST_CODEX_INSTALLER_FILE:-} ]]; then
    if [[ ! -f $J3W1ZSH_TEST_CODEX_INSTALLER_FILE || -L $J3W1ZSH_TEST_CODEX_INSTALLER_FILE ]]; then
      return 1
    fi
    cp -- "$J3W1ZSH_TEST_CODEX_INSTALLER_FILE" "$installer"
  else
    curl --proto '=https' --tlsv1.2 --max-time 60 -fsSL "$installer_url" -o "$installer"
  fi
}

j3w1zsh_codex_install_release() {
  local stable_version="$1" installer expected_checksum result
  installer="$(mktemp "$J3W1ZSH_CACHE_DIR/.codex-install.XXXXXX")"
  expected_checksum="$CODEX_INSTALLER_SHA256"
  if [[ $J3W1ZSH_TEST_MODE == 1 && ${J3W1ZSH_TEST_CODEX_ADAPTERS:-0} == 1 && -n ${J3W1ZSH_TEST_CODEX_INSTALLER_SHA256:-} ]]; then
    expected_checksum="$J3W1ZSH_TEST_CODEX_INSTALLER_SHA256"
  fi
  if j3w1zsh_codex_download_installer "$installer"; then
    :
  else
    result=$?
    rm -f -- "$installer"
    j3w1zsh_die "Unable to download the pinned official Codex installer artifact." "$result"
  fi
  if [[ $(sha256sum "$installer" | awk '{print $1}') != "$expected_checksum" ]]; then
    rm -f -- "$installer"
    j3w1zsh_die "Codex installer checksum verification failed."
  fi
  if ! sh -n "$installer"; then
    rm -f -- "$installer"
    j3w1zsh_die "Codex installer syntax verification failed."
  fi
  if env CODEX_HOME="$HOME/.codex" CODEX_NON_INTERACTIVE=true PATH="$HOME/.local/bin:$PATH" \
    sh "$installer" --release "$stable_version"; then
    rm -f -- "$installer"
  else
    result=$?
    rm -f -- "$installer"
    j3w1zsh_die "The verified official Codex installer failed." "$result"
  fi
}

phase_70_codex() {
  [[ $J3W1ZSH_TEST_MODE != 1 || ${J3W1ZSH_TEST_CODEX_ADAPTERS:-0} == 1 ]] || return 0
  [[ $J3W1ZSH_PLATFORM == wsl ]] || return 0
  local codex_bin="$HOME/.local/bin/codex"
  local installed_version stable_version="" install_required=0
  installed_version="$(j3w1zsh_codex_installed_version "$codex_bin")"

  if [[ -n $installed_version ]] && ! j3w1zsh_codex_version_valid "$installed_version"; then
    j3w1zsh_die "Installed Codex version cannot be compared safely; preserving it for owner review: $installed_version" \
      "$J3W1ZSH_EXIT_PROTECTED" unclassified_codex_version
  fi

  if [[ -z $installed_version || ${J3W1ZSH_PACKAGE_REFRESH:-0} == 1 ]]; then
    stable_version="$(j3w1zsh_codex_current_stable_version)"
    if [[ -z $installed_version ]] || ! j3w1zsh_codex_version_at_least "$installed_version" "$stable_version"; then
      install_required=1
    fi
  fi

  if ((install_required)); then
    j3w1zsh_codex_install_release "$stable_version"
    installed_version="$(j3w1zsh_codex_installed_version "$codex_bin")"
    if ! j3w1zsh_codex_version_valid "$installed_version" ||
      ! j3w1zsh_codex_version_at_least "$installed_version" "$stable_version"; then
      j3w1zsh_die "Codex did not verify at the resolved stable release after installation."
    fi
  fi

  j3w1zsh_write_if_missing "$HOME/.codex/config.toml" "$J3W1ZSH_REPO_ROOT/templates/codex-config.toml"
  if ! env CODEX_HOME="$HOME/.codex" "$codex_bin" login status >/dev/null 2>&1; then
    j3w1zsh_warn "Codex is installed but authentication remains user-owned: run 'codex login --device-auth'."
  fi
}
