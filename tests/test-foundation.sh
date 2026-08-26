#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
test_root="$(mktemp -d)"
trap 'rm -rf -- "$test_root"' EXIT

for platform in arch wsl termux wsl1 unsupported; do
  output="$(env J3W1ZSH_TEST_MODE=1 J3W1ZSH_TEST_PLATFORM="$platform" "$repo_root/bin/j3w1zsh" platform --json)"
  jq -e --arg platform "$platform" '.schema_version == 1 and .command == "platform" and .status == "ok" and .data.id == $platform' \
    <<<"$output" >/dev/null
done

if env \
  HOME="$test_root/rejected-home" \
  J3W1ZSH_TEST_MODE=1 \
  J3W1ZSH_TEST_PLATFORM=wsl1 \
  "$repo_root/bin/j3w1zsh" install --preset minimal --yes >/dev/null 2>&1; then
  printf 'WSL 1 test override was not rejected.\n' >&2
  exit 1
fi

dry_root="$test_root/dry"
mkdir -p "$dry_root/home"
before="$(find "$dry_root" -mindepth 1 -printf '%P\n' | LC_ALL=C sort)"
dry_json="$(
  env \
    HOME="$dry_root/home" \
    XDG_STATE_HOME="$dry_root/home/.local/state" \
    XDG_CONFIG_HOME="$dry_root/home/.config" \
    XDG_CACHE_HOME="$dry_root/home/.cache" \
    J3W1ZSH_TEST_MODE=1 \
    J3W1ZSH_TEST_PLATFORM=termux \
    "$repo_root/bin/j3w1zsh" install --preset minimal --dry-run --json
)"
after="$(find "$dry_root" -mindepth 1 -printf '%P\n' | LC_ALL=C sort)"
[[ $before == "$after" ]] || {
  printf 'Dry-run changed the isolated fixture.\nBefore:\n%s\nAfter:\n%s\n' "$before" "$after" >&2
  exit 1
}
jq -e '.status == "ok" and .data.dry_run == true and (.data.actions | length > 0) and ([.data.actions[].mutation] | any)' \
  <<<"$dry_json" >/dev/null

home="$test_root/install/home"
state="$home/.local/state"
config="$home/.config"
cache="$home/.cache"
mkdir -p "$home"
run_install() {
  env \
    HOME="$home" \
    XDG_STATE_HOME="$state" \
    XDG_CONFIG_HOME="$config" \
    XDG_CACHE_HOME="$cache" \
    J3W1ZSH_TEST_MODE=1 \
    J3W1ZSH_TEST_PLATFORM=termux \
    "$repo_root/bin/j3w1zsh" "$@"
}

run_install install --preset minimal --yes --plain >/dev/null
[[ -L $home/.zshrc ]]
[[ -L $home/.tmux.conf ]]
[[ -L $home/.config/nvim ]]
[[ -L $home/.local/bin/j3w1zsh ]]
[[ -x $home/.local/bin/j3w1zsh-clipboard-copy ]]
[[ -f $state/j3w1zsh/phases/90-verify.json ]]
[[ -f $config/j3w1zsh/generated/theme/manifest.json ]]
jq -e '.state_schema_version == 1 and .platform == "termux" and .preset == "minimal" and (.input_digest | length == 64)' \
  "$state/j3w1zsh/phases/90-verify.json" >/dev/null
status_json="$(run_install status --json)"
jq -e '
  (.data.phases[] | select(.phase=="70-codex") | .state)=="inapplicable" and
  (.data.phases[] | select(.phase=="80-github") | .state)=="unselected" and
  (.data.phases[] | select(.phase=="90-verify") | .state)=="complete"
' <<<"$status_json" >/dev/null
backup_json="$(run_install backup --json)"
backup_id="$(jq -r .data.backup_id <<<"$backup_json")"
backup_archive="$(jq -r .data.archive <<<"$backup_json")"
[[ -f $backup_archive ]]
tar -tvzf "$backup_archive" |
  awk '$1 ~ /^l/ && $0 ~ / \.zshrc -> / { found=1 } END { exit(found ? 0 : 1) }'
rm -- "$home/.zshrc"
printf 'temporary replacement\n' >"$home/.zshrc"
J3W1ZSH_ASSUME_YES=1 run_install restore "$backup_id" >/dev/null
[[ -L $home/.zshrc ]]
[[ $(readlink -f -- "$home/.zshrc") == "$repo_root/dotfiles/zsh/.zshrc" ]]

malicious_root="$test_root/malicious-archive"
mkdir -p "$malicious_root"
ln -s /tmp/j3w1zsh-restore-escape "$malicious_root/.zshrc"
tar -C "$malicious_root" -czf "$state/j3w1zsh/backups/configuration-malicious.tar.gz" .zshrc
if J3W1ZSH_ASSUME_YES=1 run_install restore configuration-malicious >/dev/null 2>&1; then
  printf 'Restore accepted an archive symlink outside HOME and the current checkout.\n' >&2
  exit 1
fi
[[ -L $home/.zshrc ]]
[[ -z $(find "$state/j3w1zsh/backups" -maxdepth 1 -type d -name '.restore.*' -print -quit) ]]

no_op="$(run_install install --preset minimal --yes --plain)"
grep -q '^\[+\] Phase 20-packages$' <<<"$no_op"
grep -q '^\[+\] Phase 90-verify$' <<<"$no_op"
grep -q 'Skipping completed phase: 40-config' <<<"$no_op"
if grep -q 'Skipping completed phase: 20-packages' <<<"$no_op"; then
  printf 'Explicit install skipped rolling package reconciliation.\n' >&2
  exit 1
fi

cat >"$config/j3w1zsh/packages.json" <<'JSON'
{"schema_version":1,"additions":{"pkg":["termux-api"]},"exclusions":{}}
JSON
status_after_package_change="$(run_install status --json)"
jq -e '
  (.data.phases[] | select(.phase=="20-packages") | .state)=="pending" and
  (.data.phases[] | select(.phase=="40-config") | .state)=="complete" and
  (.data.phases[] | select(.phase=="90-verify") | .state)=="pending"
' <<<"$status_after_package_change" >/dev/null

help_edit="$(run_install help edit)"
help_remote="$(run_install help remote)"
grep -q 'nvim -- PATH' <<<"$help_edit"
grep -q 'configure-client' <<<"$help_remote"

plan_json="$(run_install plan --preset minimal --json)"
jq -e '.command == "plan" and .data.platform == "termux" and .data.preset == "minimal"' <<<"$plan_json" >/dev/null

for package_free_flag in --no-packages --do-not-install-anything -dnia; do
  package_free="$(run_install install --preset j3w1 "$package_free_flag" --dry-run --json)"
  jq -e '
    .data.dry_run==true and
    ([.data.actions[] | select(.kind=="package-operation")] | length)==0 and
    ([.data.actions[] | select(.phase=="20-packages" and .kind=="verification" and .mutation==false)] | length)==1 and
    ([.data.actions[] | select(.phase=="70-codex")] | length)==0
  ' <<<"$package_free" >/dev/null
done
packages_only="$(run_install install --preset minimal --packages-only --dry-run --json)"
jq -e '
  ([.data.actions[] | select(.phase=="20-packages")] | length)>0 and
  ([.data.actions[] | select(.phase=="20-packages" and .package_manager=="pkg" and (.reason | contains("upgrade Termux")))] | length)==1 and
  ([.data.actions[] | select(.phase=="10-platform" and .kind=="verification" and .mutation==false)] | length)==1 and
  ([.data.actions[] | select(.phase=="30-shell" or .phase=="40-config" or .phase=="50-theme" or .phase=="60-neovim" or .phase=="90-verify")] | length)==0
' <<<"$packages_only" >/dev/null

if run_install install --no-packages --packages-only >/dev/null 2>&1; then
  printf 'Incompatible package flags were accepted.\n' >&2
  exit 1
fi
if run_install install --no-packages --workspace missing.json >/dev/null 2>&1; then
  printf 'Incompatible workspace/package flags were accepted.\n' >&2
  exit 1
fi

symlink_home="$test_root/symlink-settings/home"
outside_settings="$test_root/symlink-settings/outside-settings.zsh"
mkdir -p "$symlink_home/.config/j3w1zsh"
ln -s "$outside_settings" "$symlink_home/.config/j3w1zsh/settings.zsh"
if env HOME="$symlink_home" XDG_STATE_HOME="$symlink_home/.local/state" XDG_CONFIG_HOME="$symlink_home/.config" \
  XDG_CACHE_HOME="$symlink_home/.cache" J3W1ZSH_TEST_MODE=1 J3W1ZSH_TEST_PLATFORM=termux \
  "$repo_root/bin/j3w1zsh" install --preset minimal --yes >/dev/null 2>&1; then
  printf 'Installer accepted a symlinked user-owned settings file.\n' >&2
  exit 1
fi
[[ -L $symlink_home/.config/j3w1zsh/settings.zsh && ! -e $outside_settings ]]

plain="$(COLUMNS=50 run_install plan --preset minimal --plain)"
if grep -q $'\033' <<<"$plain"; then
  printf 'Plain output contained ANSI escapes.\n' >&2
  exit 1
fi

printf 'Core planning, platform, output, theme, and isolated install tests passed.\n'
