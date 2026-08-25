#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
test_root="$(mktemp -d)"
trap 'rm -rf -- "$test_root"' EXIT

seed="$test_root/seed"
canonical="$test_root/canonical.git"
mkdir -p "$seed"
(
  cd "$repo_root"
  tar --exclude=.git -cf - .
) | tar -C "$seed" -xf -
git -C "$seed" init -q -b main
git -C "$seed" config user.name 'Update Tests'
git -C "$seed" config user.email 'tests@example.invalid'
git -C "$seed" add .
git -C "$seed" commit -q -m 'fixture: updater v1'
v1="$(git -C "$seed" rev-parse HEAD)"
printf 'fresh executable reached v2\n' >"$seed/update-v2-marker.txt"
git -C "$seed" add update-v2-marker.txt
git -C "$seed" commit -q -m 'fixture: updater v2'
v2="$(git -C "$seed" rev-parse HEAD)"
git clone -q --bare "$seed" "$canonical"

create_checkout() {
  local name="$1" remote="${2:-$canonical}"
  local checkout="$test_root/$name"
  git clone -q "$remote" "$checkout"
  git -C "$checkout" checkout -q -B main "$v1"
  git -C "$checkout" branch --set-upstream-to=origin/main main >/dev/null
  printf '%s\n' "$checkout"
}

run_update() {
  local checkout="$1" home="$2"; shift 2
  mkdir -p "$home"
  env \
    HOME="$home" \
    XDG_STATE_HOME="$home/.local/state" \
    XDG_CONFIG_HOME="$home/.config" \
    XDG_CACHE_HOME="$home/.cache" \
    J3W1ZSH_TEST_MODE=1 \
    J3W1ZSH_TEST_PLATFORM=wsl \
    J3W1ZSH_TEST_CANONICAL_URL="$canonical" \
    J3W1ZSH_TEST_OLD_CANONICAL_URL="$test_root/former.git" \
    "$checkout/bin/j3w1zsh" update "$@"
}

# Dry-run uses remote inspection without changing refs, state, checkout, or trust.
dry_checkout="$(create_checkout dry-checkout)"
dry_home="$test_root/dry-home"
refs_before="$(git -C "$dry_checkout" show-ref)"
head_before="$(git -C "$dry_checkout" rev-parse HEAD)"
dry_json="$(run_update "$dry_checkout" "$dry_home" --dry-run --json)"
jq -e --arg v1 "$v1" --arg v2 "$v2" '.status == "ok" and .data.dry_run == true and .data.local_refs_changed == false and .data.tracking_relation.local_oid == $v1 and .data.tracking_relation.remote_oid == $v2 and .data.tracking_relation.behind == 1' <<<"$dry_json" >/dev/null
[[ $(git -C "$dry_checkout" show-ref) == "$refs_before" ]]
[[ $(git -C "$dry_checkout" rev-parse HEAD) == "$head_before" ]]
[[ ! -e $dry_home/.local/state/j3w1zsh ]]

# Real execution fast-forwards only, relaunches the fresh executable, and reconciles base state.
fast_checkout="$(create_checkout fast-checkout)"
fast_home="$test_root/fast-home"
run_update "$fast_checkout" "$fast_home" --yes >/dev/null
[[ $(git -C "$fast_checkout" rev-parse HEAD) == "$v2" ]]
[[ -f $fast_checkout/update-v2-marker.txt ]]
[[ -f $fast_home/.local/state/j3w1zsh/phases/90-verify.json ]]
[[ -L $fast_home/.local/bin/j3w1zsh ]]

# Post-pull reconciliation preserves an explicitly selected custom preset and user theme.
selection_checkout="$(create_checkout selection-checkout)"
selection_home="$test_root/selection-home"
mkdir -p "$selection_home/.config/j3w1zsh/themes/custom"
jq '.id="custom-selection" | .theme="custom"' "$selection_checkout/presets/minimal.json" >"$selection_home/custom-preset.json"
jq '.id="custom" | .display_name="Custom update fixture"' "$selection_checkout/themes/j3w1zsh/theme.json" \
  >"$selection_home/.config/j3w1zsh/themes/custom/theme.json"
env \
  HOME="$selection_home" \
  XDG_STATE_HOME="$selection_home/.local/state" \
  XDG_CONFIG_HOME="$selection_home/.config" \
  XDG_CACHE_HOME="$selection_home/.cache" \
  J3W1ZSH_TEST_MODE=1 \
  J3W1ZSH_TEST_PLATFORM=wsl \
  "$selection_checkout/bin/j3w1zsh" install --preset "$selection_home/custom-preset.json" --theme custom --yes --plain >/dev/null
run_update "$selection_checkout" "$selection_home" --yes >/dev/null
jq -e '.preset == "custom-selection" and .theme == "custom" and .preset_source == $source' \
  --arg source "$selection_home/custom-preset.json" \
  "$selection_home/.local/state/j3w1zsh/phases/90-verify.json" >/dev/null

# Exact generated runtime drift is byte- and patch-preserved, then repaired before fast-forward.
generated_checkout="$(create_checkout generated-checkout)"
generated_home="$test_root/generated-home"
printf '{"generated":"local-runtime"}\n' >"$generated_checkout/dotfiles/nvim/.config/nvim/lazy-lock.json"
run_update "$generated_checkout" "$generated_home" --yes >/dev/null
recovery="$(find "$generated_home/.local/state/j3w1zsh/update-recovery" -mindepth 1 -maxdepth 1 -type d | head -n1)"
grep -q local-runtime "$recovery/generated-drift.patch"
grep -q local-runtime "$recovery/files/dotfiles/nvim/.config/nvim/lazy-lock.json"
[[ -z $(git -C "$generated_checkout" status --short) ]]

assert_checkout_protected() {
  local kind="$1" checkout home result
  checkout="$(create_checkout "protected-$kind")"
  home="$test_root/home-$kind"
  case "$kind" in
  dirty) printf 'authored\n' >>"$checkout/README.md" ;;
  staged) printf 'staged\n' >>"$checkout/README.md"; git -C "$checkout" add README.md ;;
  untracked) printf 'untracked\n' >"$checkout/private.txt" ;;
  deleted) rm -- "$checkout/README.md" ;;
  renamed) git -C "$checkout" mv README.md renamed.md ;;
  esac
  set +e
  run_update "$checkout" "$home" --yes >/dev/null 2>&1
  result=$?
  set -e
  [[ $result == 21 ]] || { printf '%s checkout exited %s instead of 21.\n' "$kind" "$result" >&2; exit 1; }
  [[ $(git -C "$checkout" rev-parse HEAD) == "$v1" ]]
  [[ ! -e $home/.local/state/j3w1zsh ]]
}

assert_checkout_protected dirty
assert_checkout_protected staged
assert_checkout_protected untracked
assert_checkout_protected deleted
assert_checkout_protected renamed

# Ahead history is preserved and never reset, rebased, or merged.
ahead_checkout="$(create_checkout ahead-checkout)"
git -C "$ahead_checkout" config user.name 'Update Tests'
git -C "$ahead_checkout" config user.email 'tests@example.invalid'
printf 'unique\n' >"$ahead_checkout/unique.txt"
git -C "$ahead_checkout" add unique.txt
git -C "$ahead_checkout" commit -q -m 'fixture: unique fork commit'
ahead_oid="$(git -C "$ahead_checkout" rev-parse HEAD)"
set +e
run_update "$ahead_checkout" "$test_root/ahead-home" --yes >/dev/null 2>&1
ahead_result=$?
set -e
[[ $ahead_result == 21 ]]
[[ $(git -C "$ahead_checkout" rev-parse HEAD) == "$ahead_oid" ]]

# Fork configuration adds canonical upstream only with confirmation and never changes origin.
fork_work="$test_root/fork-work"
fork_remote="$test_root/fork.git"
git clone -q "$canonical" "$fork_work"
git -C "$fork_work" config user.name 'Update Tests'
git -C "$fork_work" config user.email 'tests@example.invalid'
printf 'fork-only\n' >"$fork_work/fork.txt"
git -C "$fork_work" add fork.txt
git -C "$fork_work" commit -q -m 'fixture: fork-only commit'
git clone -q --bare "$fork_work" "$fork_remote"
fork_checkout="$test_root/fork-checkout"
git clone -q "$fork_remote" "$fork_checkout"
origin_before="$(git -C "$fork_checkout" remote get-url origin)"
mkdir -p "$test_root/fork-home"
env HOME="$test_root/fork-home" XDG_STATE_HOME="$test_root/fork-home/.local/state" XDG_CONFIG_HOME="$test_root/fork-home/.config" XDG_CACHE_HOME="$test_root/fork-home/.cache" \
  J3W1ZSH_TEST_MODE=1 J3W1ZSH_TEST_PLATFORM=wsl J3W1ZSH_TEST_CANONICAL_URL="$canonical" J3W1ZSH_TEST_OLD_CANONICAL_URL="$test_root/former.git" \
  "$fork_checkout/bin/j3w1zsh" update --configure-upstream --yes >/dev/null
[[ $(git -C "$fork_checkout" remote get-url origin) == "$origin_before" ]]
[[ $(git -C "$fork_checkout" remote get-url upstream) == "$canonical" ]]
[[ -f $fork_checkout/fork.txt ]]

# The known former canonical URL is corrected only after old/new repository identity matches.
git clone -q --bare "$seed" "$test_root/former.git"
old_checkout="$(create_checkout old-checkout "$test_root/former.git")"
old_home="$test_root/old-home"
run_update "$old_checkout" "$old_home" --yes >/dev/null
[[ $(git -C "$old_checkout" remote get-url origin) == "$canonical" ]]
[[ $(git -C "$old_checkout" rev-parse HEAD) == "$v2" ]]

# Disposable remote comparison fetches enough immutable history to classify long-lived forks.
deep_seed="$test_root/deep-seed"
deep_local="$test_root/deep-local"
deep_remote="$test_root/deep.git"
git init -q -b main "$deep_seed"
git -C "$deep_seed" config user.name 'Update Tests'
git -C "$deep_seed" config user.email 'tests@example.invalid'
git -C "$deep_seed" commit -q --allow-empty -m 'fixture: deep root'
git clone -q "$deep_seed" "$deep_local"
for index in $(seq 1 120); do
  git -C "$deep_seed" commit -q --allow-empty -m "fixture: deep $index"
done
deep_tip="$(git -C "$deep_seed" rev-parse HEAD)"
git clone -q --bare "$deep_seed" "$deep_remote"
deep_relation="$({
  J3W1ZSH_REPO_ROOT="$deep_local"
  J3W1ZSH_TEST_MODE=1
  source "$repo_root/scripts/lib/core/git.sh"
  j3w1zsh_git_relation "$deep_remote" refs/heads/main "$deep_tip"
})"
jq -e '.ahead == 0 and .behind == 120 and .diverged == false' <<<"$deep_relation" >/dev/null

printf 'Update dry-run, selection, full-history relation, fast-forward, relaunch, generated repair, protected state, fork, and redirect tests passed.\n'
