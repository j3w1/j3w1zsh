#!/usr/bin/env bash
# shellcheck disable=SC2030,SC2031 # Isolated adapter fixtures intentionally replace HOME in separate subshells.
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
[[ $CODEX_INSTALLER_SHA256 =~ ^[0-9a-f]{64}$ ]]
# The assertions intentionally match literal variable references in the phase.
# shellcheck disable=SC2016
grep -Fq 'https://github.com/openai/codex/releases/download/rust-v$CODEX_VERSION/install.sh' "$repo_root/scripts/phases/70-codex.sh"
# shellcheck disable=SC2016
grep -Fq '== "$CODEX_INSTALLER_SHA256"' "$repo_root/scripts/phases/70-codex.sh"
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
