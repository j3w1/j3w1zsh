#!/usr/bin/env bash

j3w1zsh_is_termux() {
  local prefix="${PREFIX:-${TERMUX__PREFIX:-}}"
  [[ $J3W1ZSH_TEST_MODE != 1 || -z ${J3W1ZSH_TEST_PREFIX+x} ]] || prefix="$J3W1ZSH_TEST_PREFIX"
  [[ $prefix == /data/data/com.termux/files/usr ]]
}

j3w1zsh_is_proot() {
  [[ -n ${PROOT_DISTRO:-} || -n ${PROOT_LOADER:-} ]] && return 0
  [[ -z ${TERMUX_VERSION:-} || ${PREFIX:-} == /data/data/com.termux/files/usr ]] || return 0
  return 1
}

j3w1zsh_kernel_release() {
  if [[ $J3W1ZSH_TEST_MODE == 1 && -n ${J3W1ZSH_TEST_KERNEL_RELEASE+x} ]]; then
    printf '%s\n' "$J3W1ZSH_TEST_KERNEL_RELEASE"
  else
    cat /proc/sys/kernel/osrelease 2>/dev/null
  fi
}

j3w1zsh_effective_uid() {
  if [[ $J3W1ZSH_TEST_MODE == 1 && -n ${J3W1ZSH_TEST_EFFECTIVE_UID:-} ]]; then
    printf '%s\n' "$J3W1ZSH_TEST_EFFECTIVE_UID"
  else
    printf '%s\n' "$EUID"
  fi
}

j3w1zsh_is_wsl() {
  local distro="${WSL_DISTRO_NAME:-}"
  [[ $J3W1ZSH_TEST_MODE != 1 || -z ${J3W1ZSH_TEST_WSL_DISTRO+x} ]] || distro="$J3W1ZSH_TEST_WSL_DISTRO"
  [[ -n $distro ]] || grep -qi microsoft <<<"$(j3w1zsh_kernel_release)"
}

j3w1zsh_os_id() {
  if [[ $J3W1ZSH_TEST_MODE == 1 && -n ${J3W1ZSH_TEST_OS_ID+x} ]]; then
    printf '%s\n' "$J3W1ZSH_TEST_OS_ID"
    return 0
  fi
  [[ -r /etc/os-release ]] || return 1
  (
    # shellcheck disable=SC1091
    source /etc/os-release
    printf '%s\n' "${ID:-}"
  )
}

j3w1zsh_is_official_arch() {
  [[ $(j3w1zsh_os_id 2>/dev/null || true) == arch ]]
}

j3w1zsh_detect_platform() {
  if [[ $J3W1ZSH_TEST_MODE == 1 && -n ${J3W1ZSH_TEST_PLATFORM:-} ]]; then
    case "$J3W1ZSH_TEST_PLATFORM" in
    arch | wsl | termux | unsupported | wsl1) printf '%s\n' "$J3W1ZSH_TEST_PLATFORM"; return 0 ;;
    *) printf 'unsupported\n'; return 0 ;;
    esac
  fi
  if j3w1zsh_is_termux; then
    printf 'termux\n'
  elif j3w1zsh_is_proot; then
    printf 'unsupported\n'
  elif j3w1zsh_is_wsl; then
    if ! grep -qi 'wsl2' <<<"$(j3w1zsh_kernel_release)"; then
      printf 'wsl1\n'
    elif j3w1zsh_is_official_arch; then
      printf 'wsl\n'
    else
      printf 'unsupported\n'
    fi
  elif j3w1zsh_is_official_arch; then
    printf 'arch\n'
  else
    printf 'unsupported\n'
  fi
}

J3W1ZSH_PLATFORM="$(j3w1zsh_detect_platform)"
readonly J3W1ZSH_PLATFORM
export J3W1ZSH_PLATFORM

j3w1zsh_platform_label() {
  case "$J3W1ZSH_PLATFORM" in
  arch) printf 'native official Arch Linux\n' ;;
  wsl) printf 'official Arch Linux on Windows WSL 2\n' ;;
  termux) printf 'native Termux on Android\n' ;;
  wsl1) printf 'unsupported Windows WSL 1\n' ;;
  *) printf 'unsupported platform\n' ;;
  esac
}

j3w1zsh_platform_preflight() {
  [[ -n ${HOME:-} && -d $HOME ]] || j3w1zsh_die "HOME is not a usable directory."
  [[ $HOME != /root ]] || j3w1zsh_die "A normal user account is required."
  [[ -r $J3W1ZSH_REPO_ROOT/versions.env ]] || j3w1zsh_die "Repository files are incomplete."
  j3w1zsh_have bash || j3w1zsh_die "bash is required."

  if [[ $(j3w1zsh_effective_uid) == 0 ]]; then
    j3w1zsh_die "Run j3w1zsh as a normal user, not root."
  fi

  # Test-only platform forcing validates supported adapters without impersonating a host.
  if [[ $J3W1ZSH_TEST_MODE == 1 && $J3W1ZSH_PLATFORM =~ ^(arch|wsl|termux)$ ]]; then
    return 0
  fi

  case "$J3W1ZSH_PLATFORM" in
  arch)
    j3w1zsh_is_official_arch || j3w1zsh_die "Native installation requires official Arch Linux."
    j3w1zsh_have sudo || j3w1zsh_die "Native Arch requires functional sudo for the normal user."
    [[ $J3W1ZSH_DRY_RUN == 1 || $J3W1ZSH_TEST_MODE == 1 ]] || sudo -v
    ;;
  wsl)
    j3w1zsh_is_official_arch || j3w1zsh_die "WSL installation requires the official Arch Linux distribution."
    grep -qi 'wsl2' <<<"$(j3w1zsh_kernel_release)" || j3w1zsh_die "WSL 2 is required."
    j3w1zsh_have sudo || j3w1zsh_die "sudo is required after the one-time WSL root bootstrap."
    [[ $J3W1ZSH_DRY_RUN == 1 || $J3W1ZSH_TEST_MODE == 1 ]] || sudo -v
    ;;
  termux)
    [[ ${PREFIX:-} == /data/data/com.termux/files/usr ]] || j3w1zsh_die "Use the native main Termux environment."
    j3w1zsh_have pkg || j3w1zsh_die "Termux package management is missing."
    ;;
  wsl1) j3w1zsh_die "WSL 1 is unsupported; convert the distribution to WSL 2." ;;
  *) j3w1zsh_die "Unsupported platform. Use native official Arch Linux, official Arch under WSL 2, or native Termux." ;;
  esac
}

j3w1zsh_platform_json() {
  jq -cn --arg id "$J3W1ZSH_PLATFORM" --arg label "$(j3w1zsh_platform_label)" \
    --argjson supported "$([[ $J3W1ZSH_PLATFORM =~ ^(arch|wsl|termux)$ ]] && printf true || printf false)" \
    '{id:$id,label:$label,supported:$supported}'
}
