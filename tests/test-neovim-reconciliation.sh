#!/usr/bin/env bash
# shellcheck disable=SC2016 # The verifier subprocess intentionally expands its own exported environment.
set -Eeuo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
test_root="$(mktemp -d)"
trap 'rm -rf -- "$test_root"' EXIT

fixture_home="$test_root/home"
fixture_bin="$test_root/bin"
fixture_sources="$test_root/sources"
tracked_lock="$test_root/tracked-lazy-lock.json"
plugin_map="$test_root/plugin-map.tsv"
nvim_log="$test_root/nvim.log"
preset="$test_root/neovim-preset.json"
mkdir -p \
  "$fixture_home/.config" \
  "$fixture_home/.local/bin" \
  "$fixture_home/.local/share/nvim/lazy" \
  "$fixture_home/.local/state/nvim/j3w1zsh" \
  "$fixture_bin" \
  "$fixture_sources"

create_plugin_history() {
  local name="$1"
  local source_dir="$fixture_sources/$name" old_commit reviewed_commit newer_commit
  git init -q -b main "$source_dir"
  git -C "$source_dir" config user.name fixture
  git -C "$source_dir" config user.email fixture@example.invalid
  printf '%s-old\n' "$name" >"$source_dir/state.txt"
  git -C "$source_dir" add state.txt
  git -C "$source_dir" commit -q -m old
  old_commit="$(git -C "$source_dir" rev-parse HEAD)"
  printf '%s-reviewed\n' "$name" >"$source_dir/state.txt"
  git -C "$source_dir" commit -qam reviewed
  reviewed_commit="$(git -C "$source_dir" rev-parse HEAD)"
  printf '%s-upstream-newer\n' "$name" >"$source_dir/state.txt"
  git -C "$source_dir" commit -qam upstream-newer
  newer_commit="$(git -C "$source_dir" rev-parse HEAD)"
  printf '%s\t%s\n' "$name" "$source_dir" >>"$plugin_map"
  printf '%s\t%s\t%s\n' "$old_commit" "$reviewed_commit" "$newer_commit"
}

IFS=$'\t' read -r _ lazy_nvim_reviewed lazy_nvim_newer < <(create_plugin_history lazy.nvim)
IFS=$'\t' read -r fixture_nvim_old fixture_nvim_reviewed fixture_nvim_newer < <(create_plugin_history fixture.nvim)
IFS=$'\t' read -r _ second_nvim_reviewed second_nvim_newer < <(create_plugin_history second.nvim)
[[ $lazy_nvim_reviewed != "$fixture_nvim_reviewed" ]]
[[ $fixture_nvim_reviewed != "$second_nvim_reviewed" ]]

jq -n \
  --arg lazy_commit "$lazy_nvim_reviewed" \
  --arg fixture_commit "$fixture_nvim_reviewed" \
  --arg second_commit "$second_nvim_reviewed" \
  '{
    "lazy.nvim": {branch:"main", commit:$lazy_commit},
    "fixture.nvim": {branch:"main", commit:$fixture_commit},
    "second.nvim": {branch:"main", commit:$second_commit}
  }' >"$tracked_lock"
tracked_lock_sha="$(sha256sum "$tracked_lock" | awk '{print $1}')"

jq '
  .id="neovim-reconciliation" |
  .features=["neovim"] |
  .platforms.arch={pacman:[],npm_global:[],pip_user:[]} |
  .platforms.wsl={pacman:[],npm_global:[],pip_user:[]} |
  .platforms.termux={pkg:[],npm_global:[],pip_user:[]}
' "$repo_root/presets/minimal.json" >"$preset"

cat >"$fixture_bin/nvim" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'install_missing=%s reconcile=%s verify=%s args=%s\n' \
  "${J3W1ZSH_NEOVIM_INSTALL_MISSING:-0}" "${J3W1ZSH_NEOVIM_RECONCILE:-0}" \
  "${J3W1ZSH_NEOVIM_VERIFY:-0}" "$*" \
  >>"$J3W1ZSH_TEST_NEOVIM_LOG"
if [[ ${J3W1ZSH_NEOVIM_INSTALL_MISSING:-0} == 1 || ${J3W1ZSH_NEOVIM_RECONCILE:-0} == 1 ]]; then
  plugin_root="${XDG_DATA_HOME:-$HOME/.local/share}/nvim/lazy"
  runtime_lock="${XDG_STATE_HOME:-$HOME/.local/state}/nvim/j3w1zsh/lazy-lock.json"
  mkdir -p "$plugin_root" "$(dirname -- "$runtime_lock")"
  actual_lock='{}'
  while IFS=$'\t' read -r name branch expected_commit; do
    plugin_dir="$plugin_root/$name"
    source_dir="$(awk -F '\t' -v wanted="$name" '$1 == wanted { print $2; exit }' "$J3W1ZSH_TEST_NEOVIM_MAP")"
    [[ -n $source_dir ]] || exit 89
    if [[ ! -d $plugin_dir/.git ]]; then
      git clone -q "$source_dir" "$plugin_dir"
      git -C "$plugin_dir" checkout -q --detach "$expected_commit"
    fi
    if [[ ${J3W1ZSH_NEOVIM_RECONCILE:-0} == 1 ]]; then
      git -C "$plugin_dir" checkout -q --detach "$expected_commit"
    fi
    actual_commit="$(git -C "$plugin_dir" rev-parse HEAD)"
    actual_lock="$(jq -cn \
      --argjson lock "$actual_lock" --arg name "$name" --arg branch "$branch" --arg commit "$actual_commit" \
      '$lock + {($name):{branch:$branch,commit:$commit}}')"
  done < <(jq -r 'to_entries[] | [.key, .value.branch, .value.commit] | @tsv' "$J3W1ZSH_TEST_NEOVIM_TRACKED_LOCK")
  printf '%s\n' "$actual_lock" >"$runtime_lock"
fi
if [[ ${J3W1ZSH_NEOVIM_RECONCILE:-0} == 1 ]]; then
  [[ $* == *'+Lazy! restore'* && $* == *'+Lazy! clean'* ]] || {
    printf 'phase 60 did not request blocking lockfile restore and clean\n' >&2
    exit 88
  }
fi
EOF
chmod +x "$fixture_bin/nvim"

ln -s "$repo_root/dotfiles/nvim/.config/nvim" "$fixture_home/.config/nvim"
ln -s "$repo_root/bin/j3w1zsh" "$fixture_home/.local/bin/j3w1zsh"
cat >"$fixture_home/.local/bin/j3w1zsh-clipboard-copy" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$fixture_home/.local/bin/j3w1zsh-clipboard-copy"

plugin_root="$fixture_home/.local/share/nvim/lazy"
runtime_lock="$fixture_home/.local/state/nvim/j3w1zsh/lazy-lock.json"
git clone -q "$fixture_sources/lazy.nvim" "$plugin_root/lazy.nvim"
git -C "$plugin_root/lazy.nvim" remote set-url origin https://github.com/folke/lazy.nvim.git
git -C "$plugin_root/lazy.nvim" checkout -q --detach "$lazy_nvim_newer"
git clone -q "$fixture_sources/fixture.nvim" "$plugin_root/fixture.nvim"
git -C "$plugin_root/fixture.nvim" checkout -q --detach "$fixture_nvim_newer"
git clone -q "$fixture_sources/second.nvim" "$plugin_root/second.nvim"
git -C "$plugin_root/second.nvim" checkout -q --detach "$second_nvim_newer"
jq -n \
  --arg lazy_commit "$lazy_nvim_newer" \
  --arg fixture_commit "$fixture_nvim_newer" \
  --arg second_commit "$second_nvim_newer" \
  '{
    "lazy.nvim": {branch:"main", commit:$lazy_commit},
    "fixture.nvim": {branch:"main", commit:$fixture_commit},
    "second.nvim": {branch:"main", commit:$second_commit}
  }' >"$runtime_lock"

run_install() {
  env \
    HOME="$fixture_home" \
    XDG_CONFIG_HOME="$fixture_home/.config" \
    XDG_STATE_HOME="$fixture_home/.local/state" \
    XDG_DATA_HOME="$fixture_home/.local/share" \
    XDG_CACHE_HOME="$fixture_home/.cache" \
    PATH="$fixture_bin:/usr/bin:/bin" \
    J3W1ZSH_TEST_MODE=1 \
    J3W1ZSH_TEST_PLATFORM=termux \
    J3W1ZSH_TEST_EFFECTIVE_UID=1000 \
    J3W1ZSH_TEST_NEOVIM_ADAPTERS=1 \
    J3W1ZSH_TEST_NEOVIM_TRACKED_LOCK="$tracked_lock" \
    J3W1ZSH_TEST_NEOVIM_MAP="$plugin_map" \
    J3W1ZSH_TEST_NEOVIM_LOG="$nvim_log" \
    "$repo_root/bin/j3w1zsh" "$@"
}

assert_reviewed_state() {
  [[ $(sha256sum "$tracked_lock" | awk '{print $1}') == "$tracked_lock_sha" ]]
  jq -e -s '.[0] == .[1]' "$tracked_lock" "$runtime_lock" >/dev/null
  [[ $(git -C "$plugin_root/lazy.nvim" rev-parse HEAD) == "$lazy_nvim_reviewed" ]]
  [[ $(git -C "$plugin_root/fixture.nvim" rev-parse HEAD) == "$fixture_nvim_reviewed" ]]
  [[ $(git -C "$plugin_root/second.nvim" rev-parse HEAD) == "$second_nvim_reviewed" ]]
}

# Reproduce the device defect: both installed repositories and the runtime lock
# start newer than the reviewed tracked state. A package-enabled phase 60 must
# downgrade deterministically rather than rewriting the lock to upstream HEAD.
run_install install --preset "$preset" --only 60-neovim --force --yes --plain >/dev/null
assert_reviewed_state
grep -Fq 'args=--headless +Lazy! restore +Lazy! clean +qa' "$nvim_log"
phase_60_marker="$fixture_home/.local/state/j3w1zsh/phases/60-neovim.json"
[[ -f $phase_60_marker ]]

# An older installed plugin converges on an ordinary explicit package-enabled
# rerun even with a current phase marker. This proves phase 60 is in the bounded
# rolling-reconciliation set rather than being skipped by its old marker.
git -C "$plugin_root/fixture.nvim" checkout -q --detach "$fixture_nvim_old"
older_output="$(run_install install --preset "$preset" --only 60-neovim --yes --plain)"
grep -Fq '[+] Phase 60-neovim' <<<"$older_output"
if grep -Fq 'Skipping completed phase: 60-neovim' <<<"$older_output"; then
  printf 'Package-enabled install skipped Neovim reconciliation.\n' >&2
  exit 1
fi
assert_reviewed_state

# A mixed partial runtime has one missing plugin while another remains newer.
# The missing-install pass may rewrite its runtime lock from installed HEADs;
# phase 60 must reseed the reviewed lock before restore and converge both.
rm -rf -- "$plugin_root/fixture.nvim"
git -C "$plugin_root/second.nvim" checkout -q --detach "$second_nvim_newer"
run_install install --preset "$preset" --only 60-neovim --yes --plain >/dev/null
assert_reviewed_state

verify_runtime() {
  env \
    HOME="$fixture_home" \
    XDG_CONFIG_HOME="$fixture_home/.config" \
    XDG_STATE_HOME="$fixture_home/.local/state" \
    XDG_DATA_HOME="$fixture_home/.local/share" \
    XDG_CACHE_HOME="$fixture_home/.cache" \
    J3W1ZSH_REPO_ROOT="$repo_root" \
    J3W1ZSH_TEST_MODE=1 \
    J3W1ZSH_TEST_PLATFORM=termux \
    J3W1ZSH_TEST_NEOVIM_TRACKED_LOCK="$tracked_lock" \
    bash -c '
      set -Eeuo pipefail
      source "$J3W1ZSH_REPO_ROOT/scripts/lib/core/init.sh"
      j3w1zsh_neovim_verify_runtime
    '
}

assert_verify_fails() {
  local expected="$1"
  if verify_runtime >"$test_root/verify-failure.out" 2>&1; then
    printf 'Neovim verification accepted invalid state: %s\n' "$expected" >&2
    exit 1
  fi
  grep -Fq "$expected" "$test_root/verify-failure.out"
}

# Semantic equality permits formatting differences while retaining exact data.
jq -c . "$tracked_lock" >"$runtime_lock"
verify_runtime

cp -- "$runtime_lock" "$test_root/runtime-lock.valid"
printf '{not-json\n' >"$runtime_lock"
assert_verify_fails 'Runtime Neovim lock is malformed'
cp -- "$test_root/runtime-lock.valid" "$runtime_lock"

jq '."fixture.nvim".branch="main..ambiguous"' "$tracked_lock" >"$runtime_lock"
assert_verify_fails 'invalid managed plugin branch: main..ambiguous'
cp -- "$test_root/runtime-lock.valid" "$runtime_lock"

printf '{"lazy.nvim":{"branch":"main","commit":"%s"},"lazy.nvim":{"branch":"main","commit":"%s"},"fixture.nvim":{"branch":"main","commit":"%s"},"second.nvim":{"branch":"main","commit":"%s"}}\n' \
  "$lazy_nvim_reviewed" "$lazy_nvim_reviewed" "$fixture_nvim_reviewed" "$second_nvim_reviewed" >"$runtime_lock"
assert_verify_fails 'duplicate managed plugin identity: lazy.nvim'
cp -- "$test_root/runtime-lock.valid" "$runtime_lock"

mv -- "$runtime_lock" "$test_root/runtime-lock.saved"
assert_verify_fails 'Runtime Neovim lock must be a regular file'
ln -s "$test_root/runtime-lock.saved" "$runtime_lock"
assert_verify_fails 'Runtime Neovim lock must be a regular file'
unlink "$runtime_lock"
mv -- "$test_root/runtime-lock.saved" "$runtime_lock"

jq --arg commit "$fixture_nvim_newer" '."fixture.nvim".commit=$commit' "$tracked_lock" >"$runtime_lock"
assert_verify_fails 'does not semantically match'
cp -- "$tracked_lock" "$runtime_lock"

git -C "$plugin_root/fixture.nvim" checkout -q --detach "$fixture_nvim_newer"
assert_verify_fails 'does not match the reviewed lock: fixture.nvim'
git -C "$plugin_root/fixture.nvim" checkout -q --detach "$fixture_nvim_reviewed"

mv -- "$plugin_root/fixture.nvim" "$test_root/fixture-plugin.saved"
mkdir "$plugin_root/fixture.nvim"
assert_verify_fails 'not an independent Git repository: fixture.nvim'
rmdir "$plugin_root/fixture.nvim"
ln -s "$test_root/fixture-plugin.saved" "$plugin_root/fixture.nvim"
assert_verify_fails 'missing or ambiguous: fixture.nvim'
unlink "$plugin_root/fixture.nvim"
mv -- "$test_root/fixture-plugin.saved" "$plugin_root/fixture.nvim"
verify_runtime

# Phase 90 fails before its marker on a managed HEAD mismatch and succeeds only
# after the exact state is restored. Verification mode performs no acquisition.
git -C "$plugin_root/fixture.nvim" checkout -q --detach "$fixture_nvim_newer"
phase_90_marker="$fixture_home/.local/state/j3w1zsh/phases/90-verify.json"
if J3W1ZSH_TEST_VERIFY_ADAPTERS=1 run_install install --preset "$preset" --only 90-verify --yes --plain \
  >"$test_root/phase-90-mismatch.out" 2>&1; then
  printf 'Phase 90 accepted a managed Neovim plugin HEAD mismatch.\n' >&2
  exit 1
fi
grep -Fq 'does not match the reviewed lock: fixture.nvim' "$test_root/phase-90-mismatch.out"
[[ ! -e $phase_90_marker ]]
git -C "$plugin_root/fixture.nvim" checkout -q --detach "$fixture_nvim_reviewed"
J3W1ZSH_TEST_VERIFY_ADAPTERS=1 run_install install --preset "$preset" --only 90-verify --yes --plain >/dev/null
[[ -f $phase_90_marker ]]
assert_reviewed_state
git -C "$plugin_root/fixture.nvim" checkout -q --detach "$fixture_nvim_newer"
if J3W1ZSH_TEST_VERIFY_ADAPTERS=1 run_install install --preset "$preset" --only 90-verify --yes --plain \
  >"$test_root/phase-90-stale-marker.out" 2>&1; then
  printf 'Phase 90 retained success after managed Neovim state drifted.\n' >&2
  exit 1
fi
[[ ! -e $phase_90_marker ]]
git -C "$plugin_root/fixture.nvim" checkout -q --detach "$fixture_nvim_reviewed"

# Package-free phase 60 acquires nothing and cannot mark incomplete plugin state.
mv -- "$plugin_root/fixture.nvim" "$test_root/package-free-plugin.saved"
nvim_count_before="$(wc -l <"$nvim_log")"
if run_install install --preset "$preset" --only 60-neovim --no-packages --force --yes --plain \
  >"$test_root/package-free-missing.out" 2>&1; then
  printf 'Package-free phase 60 marked missing managed plugin state complete.\n' >&2
  exit 1
fi
grep -Fq 'missing or ambiguous: fixture.nvim' "$test_root/package-free-missing.out"
[[ ! -e $phase_60_marker ]]
[[ $(wc -l <"$nvim_log") == "$nvim_count_before" ]]
mv -- "$test_root/package-free-plugin.saved" "$plugin_root/fixture.nvim"

printf 'Deterministic Neovim lock reconciliation and fail-closed verification tests passed.\n'
