#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2030,SC2031 # Isolated adapter fixtures intentionally use literal subshell programs and replace HOME.
set -Eeuo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
test_root="$(mktemp -d)"
trap 'rm -rf -- "$test_root"' EXIT

lock="$repo_root/dotfiles/nvim/.config/nvim/lazy-lock.json"
jq -e 'type=="object" and length>0 and all(.[]; (.branch|type)=="string" and (.commit|type)=="string" and (.commit|test("^[0-9a-f]{40}$")))' "$lock" >/dev/null

init="$repo_root/dotfiles/nvim/.config/nvim/init.lua"
keymaps="$repo_root/dotfiles/nvim/.config/nvim/lua/j3w1zsh/keymaps.lua"
platform="$repo_root/dotfiles/nvim/.config/nvim/lua/j3w1zsh/platform.lua"
tmux_config="$repo_root/dotfiles/tmux/.tmux.conf"
grep -Fq 'vim.env.J3W1ZSH_MAINTAINER == "1"' "$init"
grep -Fq 'runtime_lockfile' "$init"
grep -Fq 'vim.o.columns < 140' "$keymaps"
grep -Fq 'map("n", "<leader>?", toggle_cheatsheet' "$keymaps"
grep -Fq 'vim.keymap.set({ "n", "x" }, "<C-q>", "<C-v>"' "$platform"
grep -Fqx 'set -g prefix C-a' "$tmux_config"
grep -Fqx 'bind C-a send-prefix' "$tmux_config"
grep -Fq 'j3w1zsh-clipboard-copy' "$tmux_config"

fake_bin="$test_root/bin"
mkdir -p "$fake_bin"
cat >"$fake_bin/clip.exe" <<'EOF'
#!/usr/bin/env bash
cat >"$J3W1ZSH_CLIPBOARD_LOG"
EOF
cat >"$fake_bin/termux-clipboard-set" <<'EOF'
#!/usr/bin/env bash
cat >"$J3W1ZSH_CLIPBOARD_LOG"
EOF
chmod +x "$fake_bin/clip.exe" "$fake_bin/termux-clipboard-set"
helper="$repo_root/dotfiles/local-bin/.local/bin/j3w1zsh-clipboard-copy"
# shellcheck source=versions.env
source "$repo_root/versions.env"
[[ $CODEX_INSTALLER_VERSION =~ ^[0-9]{1,9}\.[0-9]{1,9}\.[0-9]{1,9}$ ]]
[[ $CODEX_INSTALLER_SHA256 =~ ^[0-9a-f]{64}$ ]]
# The assertions intentionally match literal variable references in the phase.
# shellcheck disable=SC2016
grep -Fq 'https://github.com/openai/codex/releases/download/rust-v$CODEX_INSTALLER_VERSION/install.sh' "$repo_root/scripts/phases/70-codex.sh"
# shellcheck disable=SC2016
grep -Fq 'expected_checksum="$CODEX_INSTALLER_SHA256"' "$repo_root/scripts/phases/70-codex.sh"
grep -Fq 'https://releases.openai.com/codex/channels/latest' "$repo_root/scripts/phases/70-codex.sh"

# The pinned installer artifact resolves an exact current-stable release,
# upgrades older Codex installations, and never downgrades a newer valid one.
codex_home="$test_root/codex-home"
codex_channel="$test_root/codex-channel.json"
codex_binary="$test_root/codex-binary"
codex_installer="$test_root/codex-installer.sh"
codex_failure_installer="$test_root/codex-installer-failure.sh"
codex_preset="$test_root/codex-preset.json"
codex_version_file="$test_root/codex-version"
codex_log="$test_root/codex.log"
mkdir -p "$codex_home/.local/bin" "$codex_home/.codex"
printf '{"tag_name":"rust-v0.149.1"}\n' >"$codex_channel"
printf '0.146.0\n' >"$codex_version_file"
printf 'owner-authored = true\n' >"$codex_home/.codex/config.toml"
printf 'owner-authentication-state\n' >"$codex_home/.codex/owner-state"
cat >"$codex_binary" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
--version) printf 'codex-cli %s\n' "$(cat "$TEST_CODEX_VERSION_FILE")" ;;
login)
  [[ ${2:-} == status ]] || exit 2
  printf 'login-status\n' >>"$TEST_CODEX_LOG"
  ;;
*) exit 2 ;;
esac
EOF
cat >"$codex_installer" <<'EOF'
#!/usr/bin/env sh
test "$1" = --release
mkdir -p "$HOME/.local/bin"
cp "$TEST_CODEX_BINARY_FILE" "$HOME/.local/bin/codex"
chmod +x "$HOME/.local/bin/codex"
printf '%s\n' "$2" >"$TEST_CODEX_VERSION_FILE"
printf 'install-release=%s\n' "$2" >>"$TEST_CODEX_LOG"
EOF
cat >"$codex_failure_installer" <<'EOF'
#!/usr/bin/env sh
printf 'installer-failed\n' >>"$TEST_CODEX_LOG"
exit 42
EOF
jq '
  .id="codex-test" | .features=["codex"] |
  .platforms.arch={pacman:[],npm_global:[],pip_user:[]} |
  .platforms.wsl={pacman:[],npm_global:[],pip_user:[]} |
  .platforms.termux={pkg:[],npm_global:[],pip_user:[]}
' "$repo_root/presets/minimal.json" >"$codex_preset"
chmod +x "$codex_binary"
codex_installer_sha="$(sha256sum "$codex_installer" | awk '{print $1}')"
codex_failure_installer_sha="$(sha256sum "$codex_failure_installer" | awk '{print $1}')"
codex_config_before="$(sha256sum "$codex_home/.codex/config.toml")"
codex_owner_state_before="$(sha256sum "$codex_home/.codex/owner-state")"

run_codex_phase() {
  env \
    HOME="$codex_home" \
    XDG_STATE_HOME="$codex_home/.local/state" \
    XDG_CONFIG_HOME="$codex_home/.config" \
    XDG_CACHE_HOME="$codex_home/.cache" \
    J3W1ZSH_REPO_ROOT="$repo_root" \
    J3W1ZSH_TEST_MODE=1 \
    J3W1ZSH_TEST_PLATFORM=wsl \
    J3W1ZSH_TEST_CODEX_ADAPTERS=1 \
    J3W1ZSH_TEST_CODEX_CHANNEL_FILE="$codex_channel" \
    J3W1ZSH_TEST_CODEX_INSTALLER_FILE="${J3W1ZSH_TEST_CODEX_INSTALLER_FILE:-$codex_installer}" \
    J3W1ZSH_TEST_CODEX_INSTALLER_SHA256="${J3W1ZSH_TEST_CODEX_INSTALLER_SHA256:-$codex_installer_sha}" \
    TEST_CODEX_PACKAGE_REFRESH="${J3W1ZSH_PACKAGE_REFRESH:-1}" \
    TEST_CODEX_BINARY_FILE="$codex_binary" \
    TEST_CODEX_VERSION_FILE="$codex_version_file" \
    TEST_CODEX_LOG="$codex_log" \
    bash -c '
      set -Eeuo pipefail
      source "$J3W1ZSH_REPO_ROOT/scripts/lib/core/init.sh"
      source "$J3W1ZSH_REPO_ROOT/scripts/phases/70-codex.sh"
      J3W1ZSH_PACKAGE_REFRESH="$TEST_CODEX_PACKAGE_REFRESH"
      export J3W1ZSH_PACKAGE_REFRESH
      j3w1zsh_ensure_dirs
      phase_70_codex
    '
}

run_codex_phase
[[ -x $codex_home/.local/bin/codex ]]
[[ $(<"$codex_version_file") == 0.149.1 ]]
grep -qx 'install-release=0.149.1' "$codex_log"
[[ $(sha256sum "$codex_home/.codex/config.toml") == "$codex_config_before" ]]
[[ $(sha256sum "$codex_home/.codex/owner-state") == "$codex_owner_state_before" ]]
grep -qx 'login-status' "$codex_log"
install_count="$(grep -c '^install-release=' "$codex_log")"
run_codex_phase
[[ $(grep -c '^install-release=' "$codex_log") == "$install_count" ]]
printf '0.150.0\n' >"$codex_version_file"
run_codex_phase
[[ $(<"$codex_version_file") == 0.150.0 ]]
[[ $(grep -c '^install-release=' "$codex_log") == "$install_count" ]]

# Product-update reconciliation with an already installed CLI is offline and
# does not refresh Codex merely because the implementation phase is forced.
printf '0.146.0\n' >"$codex_version_file"
printf '{"tag_name":"invalid-if-read"}\n' >"$codex_channel"
J3W1ZSH_PACKAGE_REFRESH=0 run_codex_phase
[[ $(<"$codex_version_file") == 0.146.0 ]]
[[ $(grep -c '^install-release=' "$codex_log") == "$install_count" ]]

# Stable-channel and pinned-installer verification fail before executing
# untrusted or mismatched bytes.
printf '{"tag_name":"invalid"}\n' >"$codex_channel"
set +e
J3W1ZSH_PACKAGE_REFRESH=1 run_codex_phase >"$test_root/codex-channel-invalid.out" 2>&1
codex_channel_result=$?
set -e
[[ $codex_channel_result == 1 ]]
[[ $(grep -c '^install-release=' "$codex_log") == "$install_count" ]]
printf '{"tag_name":"rust-v0.149.1"}\n' >"$codex_channel"
set +e
env \
  HOME="$codex_home" XDG_STATE_HOME="$codex_home/.local/state" XDG_CONFIG_HOME="$codex_home/.config" XDG_CACHE_HOME="$codex_home/.cache" \
  PATH="$codex_home/.local/bin:$PATH" J3W1ZSH_TEST_MODE=1 J3W1ZSH_TEST_PLATFORM=wsl J3W1ZSH_TEST_CODEX_ADAPTERS=1 \
  J3W1ZSH_TEST_CODEX_CHANNEL_FILE="$codex_channel" J3W1ZSH_TEST_CODEX_INSTALLER_FILE="$codex_installer" \
  J3W1ZSH_TEST_CODEX_INSTALLER_SHA256="$(printf '0%.0s' {1..64})" TEST_CODEX_BINARY_FILE="$codex_binary" \
  TEST_CODEX_VERSION_FILE="$codex_version_file" TEST_CODEX_LOG="$codex_log" \
  "$repo_root/bin/j3w1zsh" install --preset "$codex_preset" --only 70-codex --force --yes --plain \
  >"$test_root/codex-checksum-invalid.out" 2>&1
codex_checksum_result=$?
set -e
[[ $codex_checksum_result == 1 ]]
grep -q 'checksum verification failed' "$test_root/codex-checksum-invalid.out"
[[ $(<"$codex_version_file") == 0.146.0 ]]
[[ $(grep -c '^install-release=' "$codex_log") == "$install_count" ]]
[[ -z $(find "$codex_home/.cache/j3w1zsh" -maxdepth 1 -type f -name '.codex-install.*' -print -quit) ]]
[[ ! -e $codex_home/.local/state/j3w1zsh/phases/70-codex.json ]]

set +e
J3W1ZSH_PACKAGE_REFRESH=1 J3W1ZSH_TEST_CODEX_INSTALLER_FILE="$test_root/missing-installer" \
  run_codex_phase >"$test_root/codex-download-failure.out" 2>&1
codex_download_result=$?
set -e
[[ $codex_download_result == 1 ]]
grep -q 'Unable to download the pinned official Codex installer artifact' "$test_root/codex-download-failure.out"
[[ $(<"$codex_version_file") == 0.146.0 ]]
[[ -z $(find "$codex_home/.cache/j3w1zsh" -maxdepth 1 -type f -name '.codex-install.*' -print -quit) ]]

set +e
J3W1ZSH_PACKAGE_REFRESH=1 J3W1ZSH_TEST_CODEX_INSTALLER_FILE="$codex_failure_installer" \
  J3W1ZSH_TEST_CODEX_INSTALLER_SHA256="$codex_failure_installer_sha" \
  run_codex_phase >"$test_root/codex-install-failure.out" 2>&1
codex_install_result=$?
set -e
[[ $codex_install_result == 42 ]]
grep -q 'verified official Codex installer failed' "$test_root/codex-install-failure.out"
[[ $(<"$codex_version_file") == 0.146.0 ]]
[[ -z $(find "$codex_home/.cache/j3w1zsh" -maxdepth 1 -type f -name '.codex-install.*' -print -quit) ]]

# An unclassifiable locally authored version is preserved rather than replaced
# or silently downgraded.
printf 'owner-build\n' >"$codex_version_file"
set +e
J3W1ZSH_PACKAGE_REFRESH=1 run_codex_phase >"$test_root/codex-unclassified.out" 2>&1
codex_unclassified_result=$?
set -e
[[ $codex_unclassified_result == 21 ]]
grep -q 'preserving it for owner review' "$test_root/codex-unclassified.out"
[[ $(<"$codex_version_file") == owner-build ]]

# A manually upgraded valid Codex remains healthy in status, doctor, and the
# network-independent final verification phase.
printf '0.150.0\n' >"$codex_version_file"
cat >"$codex_home/.local/bin/curl" <<'EOF'
#!/usr/bin/env bash
printf 'health checks must not query the Codex stable channel\n' >&2
exit 99
EOF
cat >"$codex_home/.local/bin/j3w1zsh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$codex_home/.local/bin/curl" "$codex_home/.local/bin/j3w1zsh"
mkdir -p "$codex_home/.local/state/j3w1zsh/phases"
jq -n --arg preset "$codex_preset" '{preset_source:$preset,theme_source:"j3w1zsh",no_packages:false,packages_only:false}' \
  >"$codex_home/.local/state/j3w1zsh/phases/00-preflight.json"
codex_status="$(env HOME="$codex_home" XDG_STATE_HOME="$codex_home/.local/state" XDG_CONFIG_HOME="$codex_home/.config" \
  XDG_CACHE_HOME="$codex_home/.cache" PATH="$codex_home/.local/bin:$PATH" J3W1ZSH_TEST_MODE=1 J3W1ZSH_TEST_PLATFORM=wsl \
  TEST_CODEX_VERSION_FILE="$codex_version_file" TEST_CODEX_LOG="$codex_log" "$repo_root/bin/j3w1zsh" status --json)"
jq -e '.status=="ok"' <<<"$codex_status" >/dev/null
codex_doctor="$(env HOME="$codex_home" XDG_STATE_HOME="$codex_home/.local/state" XDG_CONFIG_HOME="$codex_home/.config" \
  XDG_CACHE_HOME="$codex_home/.cache" PATH="$codex_home/.local/bin:$PATH" J3W1ZSH_TEST_MODE=1 J3W1ZSH_TEST_PLATFORM=wsl \
  TEST_CODEX_VERSION_FILE="$codex_version_file" TEST_CODEX_LOG="$codex_log" "$repo_root/bin/j3w1zsh" doctor --json)"
jq -e '.status=="ok" and (.data.checks[] | select(.name=="codex") | .ok)==true' <<<"$codex_doctor" >/dev/null
env \
  HOME="$codex_home" XDG_STATE_HOME="$codex_home/.local/state" XDG_CONFIG_HOME="$codex_home/.config" XDG_CACHE_HOME="$codex_home/.cache" \
  PATH="$codex_home/.local/bin:$PATH" J3W1ZSH_REPO_ROOT="$repo_root" J3W1ZSH_TEST_MODE=1 J3W1ZSH_TEST_PLATFORM=wsl \
  J3W1ZSH_TEST_VERIFY_ADAPTERS=1 TEST_CODEX_VERSION_FILE="$codex_version_file" TEST_CODEX_LOG="$codex_log" TEST_PRESET="$codex_preset" \
  bash -c '
    set -Eeuo pipefail
    source "$J3W1ZSH_REPO_ROOT/scripts/lib/core/init.sh"
    source "$J3W1ZSH_REPO_ROOT/scripts/lib/presets.sh"
    source "$J3W1ZSH_REPO_ROOT/scripts/phases/90-verify.sh"
    j3w1zsh_resolve_preset "$TEST_PRESET"
    phase_90_verify
  '
export J3W1ZSH_CLIPBOARD_LOG="$test_root/clipboard.log"
printf 'windows bytes' | PATH="$fake_bin:/usr/bin:/bin" WSL_DISTRO_NAME=archlinux "$helper"
grep -qx 'windows bytes' "$J3W1ZSH_CLIPBOARD_LOG"
rm -- "$fake_bin/clip.exe"
printf 'android bytes' | PATH="$fake_bin:/usr/bin:/bin" PREFIX=/data/data/com.termux/files/usr "$helper"
grep -qx 'android bytes' "$J3W1ZSH_CLIPBOARD_LOG"
if PATH=/usr/bin:/bin "$helper" </dev/null >/dev/null 2>&1; then
  printf 'Clipboard helper succeeded without a supported bridge.\n' >&2
  exit 1
fi

# The simulated Termux host adapter reconciles user paths while package-free mode performs no acquisition.
termux_home="$test_root/termux-home"
termux_bin="$test_root/termux-bin"
termux_log="$test_root/termux-host.log"
mkdir -p "$termux_home/storage/shared" "$termux_home/.config/j3w1zsh/generated/theme" "$termux_bin"
printf 'background=#000000\nforeground=#FFF1F1\n' >"$termux_home/.config/j3w1zsh/generated/theme/termux-colors.properties"
for command in termux-clipboard-get termux-reload-settings termux-setup-storage; do
  cat >"$termux_bin/$command" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$(basename -- "$0")" >>"$J3W1ZSH_TERMUX_HOST_LOG"
EOF
done
cat >"$termux_bin/curl" <<'EOF'
#!/usr/bin/env bash
printf 'curl must not run in package-free Termux reconciliation\n' >&2
exit 99
EOF
chmod +x "$termux_bin"/*
(
  export HOME="$termux_home"
  export XDG_CONFIG_HOME="$HOME/.config" XDG_STATE_HOME="$HOME/.local/state" XDG_CACHE_HOME="$HOME/.cache"
  export J3W1ZSH_REPO_ROOT="$repo_root" J3W1ZSH_TEST_MODE=1 J3W1ZSH_TEST_PLATFORM=termux
  export J3W1ZSH_TEST_HOST_ADAPTERS=1 J3W1ZSH_NO_PACKAGES=1 J3W1ZSH_TERMUX_HOST_LOG="$termux_log"
  export PATH="$termux_bin:/usr/bin:/bin"
  # shellcheck source=scripts/lib/core/init.sh
  source "$repo_root/scripts/lib/core/init.sh"
  # shellcheck source=scripts/platforms/termux.sh
  source "$repo_root/scripts/platforms/termux.sh"
  j3w1zsh_host_theme_termux
)
[[ -L $termux_home/.termux/colors.properties ]]
grep -Fq "export J3W1ZSH_EDIT_ROOT='$termux_home/storage/shared/Documents'" "$termux_home/.config/j3w1zsh/settings.zsh"
[[ ! -e $termux_home/.termux/font.ttf ]]
grep -qx termux-clipboard-get "$termux_log"
grep -qx termux-reload-settings "$termux_log"
if grep -qx termux-setup-storage "$termux_log"; then
  printf 'Termux storage setup ran despite an existing permission surface.\n' >&2
  exit 1
fi

escape_home="$test_root/escape-home"
escape_target="$test_root/escape-target"
mkdir -p "$escape_home/storage/shared" "$escape_home/.config/j3w1zsh/generated/theme" "$escape_target"
printf 'background=#000000\n' >"$escape_home/.config/j3w1zsh/generated/theme/termux-colors.properties"
ln -s "$escape_target" "$escape_home/.termux"
if (
  export HOME="$escape_home"
  export XDG_CONFIG_HOME="$HOME/.config" XDG_STATE_HOME="$HOME/.local/state" XDG_CACHE_HOME="$HOME/.cache"
  export J3W1ZSH_REPO_ROOT="$repo_root" J3W1ZSH_TEST_MODE=1 J3W1ZSH_TEST_PLATFORM=termux
  export J3W1ZSH_TEST_HOST_ADAPTERS=1 J3W1ZSH_NO_PACKAGES=1 J3W1ZSH_TERMUX_HOST_LOG="$termux_log"
  export PATH="$termux_bin:/usr/bin:/bin"
  source "$repo_root/scripts/lib/core/init.sh"
  source "$repo_root/scripts/platforms/termux.sh"
  j3w1zsh_host_theme_termux
) >/dev/null 2>&1; then
  printf 'Termux host adapter followed a .termux ancestor outside HOME.\n' >&2
  exit 1
fi
[[ -z $(find "$escape_target" -mindepth 1 -print -quit) ]]

printf 'Neovim lock, responsive keys, tmux, platform clipboards, and package-free Termux host tests passed.\n'
