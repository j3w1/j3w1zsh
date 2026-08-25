#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

((EUID == 0)) || fail "The one-time bootstrap requires the initial root shell of official Arch under WSL 2."
grep -qi 'wsl2' /proc/sys/kernel/osrelease 2>/dev/null || fail "The root bootstrap supports WSL 2 only."
[[ -r /etc/os-release ]] || fail "Unable to identify the distribution."
# shellcheck disable=SC1091
source /etc/os-release
[[ ${ID:-} == arch ]] || fail "The root bootstrap supports official Arch Linux only."
git -C "$repo_root" rev-parse --is-inside-work-tree >/dev/null 2>&1 || fail "The root bootstrap requires a Git checkout."
[[ -z $(git -C "$repo_root" status --short --untracked-files=all) ]] ||
  fail "The bootstrap checkout contains local or untracked bytes; preserve and review them before continuing."

printf '\nj3w1zsh — one shell. every machine. zero compromise.\n'
printf 'One-time official Arch WSL 2 normal-user bootstrap\n\n'
printf 'This will perform a full Arch upgrade, install the bounded bootstrap packages, create or\n'
printf 'reconcile one normal user, enable password-protected wheel sudo, and write /etc/wsl.conf.\n\n'
read -r -p 'Continue? [y/N] ' answer
[[ $answer == [Yy] ]] || fail "Root bootstrap cancelled before mutation."

read -r -p 'New or existing Linux username: ' target_user
[[ $target_user =~ ^[a-z_][a-z0-9_-]*$ ]] || fail "Use a lowercase Linux username containing letters, digits, underscores, or hyphens."
[[ $target_user != root ]] || fail "The normal user cannot be root."

if id "$target_user" >/dev/null 2>&1; then
  target_home="$(getent passwd "$target_user" | cut -d: -f6)"
  [[ $target_home == /* && $target_home != / && $target_home != /root ]] || fail "The existing user has an unsafe home directory."
  [[ -d $target_home && ! -L $target_home ]] || fail "The existing user home must be a regular directory, not a symlink."
else
  target_home="/home/$target_user"
  [[ $(readlink -m -- "$target_home") == "$target_home" ]] || fail "The new user home resolves through an unsafe ancestor."
fi
target_repo="$target_home/j3w1zsh"
resolved_target_home="$(readlink -m -- "$target_home")"
resolved_target_repo="$(readlink -m -- "$target_repo")"
[[ $resolved_target_repo == "$resolved_target_home/"* ]] || fail "Computed checkout escaped the selected home."
if [[ $repo_root != "$target_repo" && ( -e $target_repo || -L $target_repo ) ]]; then
  fail "Target checkout already exists and was preserved: $target_repo"
fi

pacman -Syu --needed base-devel curl git jq sudo zsh

if ! id "$target_user" >/dev/null 2>&1; then
  useradd --create-home --groups wheel --shell /usr/bin/zsh "$target_user"
  printf 'Create the Linux password for %s:\n' "$target_user"
  passwd "$target_user"
else
  usermod --append --groups wheel --shell /usr/bin/zsh "$target_user"
fi
[[ -d $target_home && ! -L $target_home && $(readlink -f -- "$target_home") == "$resolved_target_home" ]] ||
  fail "The selected normal-user home failed post-creation validation."

install -d -m 0750 /etc/sudoers.d
temporary_sudoers="$(mktemp /etc/sudoers.d/.10-j3w1zsh.XXXXXX)"
printf '%%wheel ALL=(ALL:ALL) ALL\n' >"$temporary_sudoers"
chmod 0440 "$temporary_sudoers"
visudo -cf "$temporary_sudoers"
mv -- "$temporary_sudoers" /etc/sudoers.d/10-j3w1zsh-wheel

if [[ -f /etc/wsl.conf && ! -L /etc/wsl.conf ]]; then
  cp -p -- /etc/wsl.conf "/etc/wsl.conf.before-j3w1zsh-$(date +%Y%m%d-%H%M%S)"
elif [[ -e /etc/wsl.conf || -L /etc/wsl.conf ]]; then
  fail "Refusing to replace a non-regular /etc/wsl.conf."
fi
temporary_wsl="$(mktemp /etc/.wsl.conf.j3w1zsh.XXXXXX)"
printf '[boot]\nsystemd=true\n\n[user]\ndefault=%s\n\n[interop]\nenabled=true\nappendWindowsPath=true\n' "$target_user" >"$temporary_wsl"
chmod 0644 "$temporary_wsl"
mv -- "$temporary_wsl" /etc/wsl.conf

if [[ $repo_root != "$target_repo" ]]; then
  cp -a -- "$repo_root" "$target_repo"
fi
chown -R "$target_user:$target_user" "$target_repo"

printf '\nInitial user bootstrap is complete.\n\n'
printf 'From Windows PowerShell, run:\n\n'
printf '  wsl --terminate %q\n' "${WSL_DISTRO_NAME:-archlinux}"
printf '  wsl --distribution %q\n\n' "${WSL_DISTRO_NAME:-archlinux}"
printf 'Then, as %s:\n\n' "$target_user"
printf '  cd ~/j3w1zsh\n'
printf '  ./install.sh --dry-run\n'
printf '  ./install.sh\n\n'
