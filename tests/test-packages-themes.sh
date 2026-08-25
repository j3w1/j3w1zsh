#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
test_root="$(mktemp -d)"
trap 'rm -rf -- "$test_root"' EXIT
export HOME="$test_root/home"
export XDG_STATE_HOME="$HOME/.local/state"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_CACHE_HOME="$HOME/.cache"
export J3W1ZSH_REPO_ROOT="$repo_root"
export J3W1ZSH_TEST_MODE=1
export J3W1ZSH_TEST_PLATFORM=termux
mkdir -p "$HOME/.config/j3w1zsh"

# shellcheck source=scripts/lib/core/init.sh
source "$repo_root/scripts/lib/core/init.sh"
# shellcheck source=scripts/lib/presets.sh
source "$repo_root/scripts/lib/presets.sh"
# shellcheck source=scripts/lib/packages.sh
source "$repo_root/scripts/lib/packages.sh"
# shellcheck source=scripts/lib/themes.sh
source "$repo_root/scripts/lib/themes.sh"
# shellcheck source=scripts/lib/core/plan.sh
source "$repo_root/scripts/lib/core/plan.sh"
# shellcheck source=scripts/commands/packages.sh
source "$repo_root/scripts/commands/packages.sh"

j3w1zsh_test_forbidden_callback() {
  touch "$test_root/typed-callback-ran"
}
invalid_action='{"platform":"arch","kind":"shell-expression","mutation":true}'
if (j3w1zsh_execute_typed_callback "$invalid_action" j3w1zsh_test_forbidden_callback >/dev/null 2>&1); then
  printf 'Typed action executor accepted an unbounded action.\n' >&2
  exit 1
fi
[[ ! -e $test_root/typed-callback-ran ]]

j3w1zsh_resolve_preset j3w1
override="$HOME/.config/j3w1zsh/packages.json"
jq -n '{schema_version:1,additions:{pkg:["owner-extra"]},exclusions:{pkg:["proot-distro"]}}' >"$override"
package_json="$(j3w1zsh_packages_for_manager_json pkg)"
jq -e 'index("owner-extra") and index("bash") and index("jq") and (index("proot-distro")|not)' <<<"$package_json" >/dev/null

jq -n '{schema_version:1,additions:{},exclusions:{pkg:["jq"]}}' >"$override"
if (j3w1zsh_packages_for_manager_json pkg >/dev/null 2>&1); then
  printf 'A user exclusion removed protected core closure.\n' >&2
  exit 1
fi

custom_preset="$test_root/custom.json"
jq '.id="custom" | .features=["shell"] | .platforms.termux.pkg=[] | .platforms.termux.npm_global=[] | .platforms.termux.pip_user=[]' \
  "$repo_root/presets/minimal.json" >"$custom_preset"
rm -- "$override"
j3w1zsh_resolve_preset "$custom_preset"
custom_packages="$(j3w1zsh_packages_for_manager_json pkg)"
jq -e 'sort == ["bash","coreutils","curl","git","jq","zsh"]' <<<"$custom_packages" >/dev/null

j3w1zsh_ensure_dirs
export J3W1ZSH_PACKAGE_LAYER=workspace
j3w1zsh_record_package_provenance pkg preexisting true "$(printf '1%.0s' {1..64})"
j3w1zsh_record_package_provenance pkg preexisting false "$(printf '2%.0s' {1..64})"
unset J3W1ZSH_PACKAGE_LAYER
j3w1zsh_record_package_provenance pkg removable false "$(printf '3%.0s' {1..64})"
j3w1zsh_record_package_provenance pkg ambiguous false "$(printf '4%.0s' {1..64})"
export J3W1ZSH_PACKAGE_LAYER=workspace
j3w1zsh_record_package_provenance pkg workspace-held false "$(printf '5%.0s' {1..64})"
j3w1zsh_record_package_provenance pkg bash false "$(printf '6%.0s' {1..64})"
unset J3W1ZSH_PACKAGE_LAYER
ledger="$J3W1ZSH_STATE_DIR/packages/provenance.json"
jq -e '
  (.packages[]|select(.package=="preexisting")|.pre_existing==true and .installed_by_j3w1zsh==false and .declaring_layers==["workspace"] and .first_seen_product_version=="1.0.0") and
  (.packages[]|select(.package=="removable")|.pre_existing==false and .installed_by_j3w1zsh==true) and
  (.packages[]|select(.package=="bash")|.declaring_layers==["core","workspace"])
' "$ledger" >/dev/null

j3w1zsh_package_is_installed() {
  [[ $2 == preexisting || $2 == removable || $2 == workspace-held ]]
}
workspace_manifest="$test_root/active-workspace.json"
jq -n '{schema_version:2,targets:{termux:{packages:{pkg:["workspace-held"],npm_global:[],pip_user:[]}}}}' >"$workspace_manifest"
workspace_digest="$(sha256sum "$workspace_manifest" | awk '{print $1}')"
mkdir -p "$J3W1ZSH_STATE_DIR/workspaces"
jq -n --arg manifest "$workspace_manifest" --arg digest "$workspace_digest" \
  '{schema_version:1,manifest:$manifest,manifest_sha256:$digest,platform:"termux"}' >"$J3W1ZSH_STATE_DIR/workspaces/active.json"
candidates="$(j3w1zsh_packages_prune_candidates_json)"
jq -e 'length==1 and .[0].manager=="pkg" and .[0].package=="removable"' <<<"$candidates" >/dev/null
printf 'changed\n' >>"$workspace_manifest"
ambiguous_candidates="$(j3w1zsh_packages_prune_candidates_json)"
jq -e 'length==1 and .[0].package=="removable"' <<<"$ambiguous_candidates" >/dev/null
rm -- "$J3W1ZSH_STATE_DIR/workspaces/active.json"
inactive_candidates="$(j3w1zsh_packages_prune_candidates_json)"
jq -e '([.[].package] | sort) == ["removable","workspace-held"]' <<<"$inactive_candidates" >/dev/null

fake_bin="$test_root/bin"
mkdir -p "$fake_bin"
cat >"$fake_bin/dpkg-query" <<'EOF'
#!/usr/bin/env bash
package="${*: -1}"
[[ $package == preexisting || $package == removable ]] || exit 1
printf 'install ok installed'
EOF
chmod +x "$fake_bin/dpkg-query"
ledger_before="$(sha256sum "$ledger")"
prune_json="$(PATH="$fake_bin:$PATH" "$repo_root/bin/j3w1zsh" packages prune --dry-run --json --preset "$custom_preset")"
jq -e '.command=="packages-prune" and .status=="ok" and (.data|length)==1 and .data[0].package=="removable"' <<<"$prune_json" >/dev/null
[[ $(sha256sum "$ledger") == "$ledger_before" ]]
pkg() {
  printf '%s\n' "$*" >>"$test_root/prune.log"
}
j3w1zsh_packages_prune_execute "$candidates"
grep -qx 'uninstall -y -- removable' "$test_root/prune.log"
jq -e 'all(.packages[]; .package != "removable")' "$ledger" >/dev/null

# Theme dry-run is mutation-free; actual render derives every host artifact from strict JSON.
custom_theme_dir="$HOME/.config/j3w1zsh/themes/custom"
mkdir -p "$custom_theme_dir"
jq '.id="custom" | .display_name="Custom declarative theme" | .palette.blue="#3366FF"' \
  "$repo_root/themes/j3w1zsh/theme.json" >"$custom_theme_dir/theme.json"
before="$(find "$HOME/.config/j3w1zsh" -mindepth 1 -printf '%P\n' | LC_ALL=C sort)"
"$repo_root/bin/j3w1zsh" theme apply custom --dry-run >/dev/null
after="$(find "$HOME/.config/j3w1zsh" -mindepth 1 -printf '%P\n' | LC_ALL=C sort)"
[[ $before == "$after" ]]

apply_json="$("$repo_root/bin/j3w1zsh" theme apply custom --json)"
jq -e '.command=="theme-apply" and .status=="ok" and .data.id=="custom" and .data.dry_run==false' <<<"$apply_json" >/dev/null
generated="$HOME/.config/j3w1zsh/generated/theme"
for file in theme.zsh theme.tmux.conf theme.lua windows-terminal.json termux-colors.properties manifest.json; do
  [[ -s $generated/$file ]]
done
jq -e '.name=="j3w1zsh" and .background=="#000000" and .green=="#B00020" and .brightGreen=="#FF334D"' "$generated/windows-terminal.json" >/dev/null
grep -q 'semantic_green = "#50FA7B"' "$generated/theme.lua"
grep -q 'window-status-current-format' "$generated/theme.tmux.conf"
grep -Fq 'generated/theme/theme.lua' "$repo_root/dotfiles/nvim/.config/nvim/lua/j3w1zsh/theme.lua"
jq -e '.id=="custom" and (.source_sha256|length)==64' "$generated/manifest.json" >/dev/null
current="$("$repo_root/bin/j3w1zsh" theme current --json)"
jq -e '.data.id=="custom"' <<<"$current" >/dev/null
listed="$("$repo_root/bin/j3w1zsh" theme list --json)"
jq -e '[.data[].id] | index("j3w1zsh") and index("custom")' <<<"$listed" >/dev/null

mkdir -p "$HOME/.config/j3w1zsh/themes/hostile"
jq '.id="hostile" | .template="$(touch should-not-run)"' "$repo_root/themes/j3w1zsh/theme.json" \
  >"$HOME/.config/j3w1zsh/themes/hostile/theme.json"
manifest_before="$(sha256sum "$generated/manifest.json")"
if "$repo_root/bin/j3w1zsh" theme apply hostile --dry-run >/dev/null 2>&1; then
  printf 'Executable or extra theme content passed strict validation.\n' >&2
  exit 1
fi
[[ ! -e $test_root/should-not-run ]]
[[ $(sha256sum "$generated/manifest.json") == "$manifest_before" ]]

printf 'Preset closure, overrides, provenance, prune ambiguity, declarative theme, and renderer tests passed.\n'
