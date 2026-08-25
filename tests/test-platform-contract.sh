#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
test_root="$(mktemp -d)"
trap 'rm -rf -- "$test_root"' EXIT

detect() {
  env HOME="$test_root/home" J3W1ZSH_TEST_MODE=1 J3W1ZSH_TEST_PREFIX="${1-}" \
    J3W1ZSH_TEST_WSL_DISTRO="${2-}" J3W1ZSH_TEST_KERNEL_RELEASE="${3-}" J3W1ZSH_TEST_OS_ID="${4-}" \
    "$repo_root/bin/j3w1zsh" platform --json | jq -r .data.id
}
mkdir -p "$test_root/home"

[[ $(detect /data/data/com.termux/files/usr archlinux microsoft-standard-WSL2 arch) == termux ]]
[[ $(detect '' archlinux microsoft-standard-WSL2 arch) == wsl ]]
[[ $(detect '' archlinux 4.4.0-microsoft-standard arch) == wsl1 ]]
[[ $(detect '' '' 6.12.0-arch1-1 arch) == arch ]]
[[ $(detect '' '' 6.12.0-arch1-1 endeavouros) == unsupported ]]
[[ $(detect '' '' 6.12.0-generic ubuntu) == unsupported ]]

proot="$(env HOME="$test_root/home" J3W1ZSH_TEST_MODE=1 J3W1ZSH_TEST_PREFIX=/usr J3W1ZSH_TEST_WSL_DISTRO='' \
  J3W1ZSH_TEST_KERNEL_RELEASE=6.12.0-arch1-1 J3W1ZSH_TEST_OS_ID=arch PROOT_DISTRO=arch \
  "$repo_root/bin/j3w1zsh" platform --json | jq -r .data.id)"
[[ $proot == unsupported ]]

unsupported_home="$test_root/unsupported-home"
mkdir -p "$unsupported_home"
if env HOME="$unsupported_home" J3W1ZSH_TEST_MODE=1 J3W1ZSH_TEST_PLATFORM=unsupported \
  "$repo_root/bin/j3w1zsh" install --preset minimal --dry-run >/dev/null 2>&1; then
  printf 'Unsupported platform unexpectedly produced an install plan.\n' >&2
  exit 1
fi
[[ -z $(find "$unsupported_home" -mindepth 1 -print) ]]

root_home="$test_root/root-home"
mkdir -p "$root_home"
before="$(find "$root_home" -mindepth 1 -print)"
set +e
env HOME="$root_home" J3W1ZSH_TEST_MODE=1 J3W1ZSH_TEST_PLATFORM=termux J3W1ZSH_TEST_EFFECTIVE_UID=0 \
  "$repo_root/bin/j3w1zsh" install --preset minimal --yes >/dev/null 2>&1
root_code=$?
set -e
[[ $root_code == 1 ]]
after="$(find "$root_home" -mindepth 1 -print)"
[[ $before == "$after" ]]

grep -Fq 'status --short --untracked-files=all' "$repo_root/scripts/bootstrap-root.sh"
grep -Fq 'existing user home must be a regular directory, not a symlink' "$repo_root/scripts/bootstrap-root.sh"

printf 'Termux-first, WSL 2, WSL 1, native Arch, derivative, PRoot, unsupported, and root dispatch tests passed.\n'
