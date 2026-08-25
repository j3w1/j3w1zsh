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

# A real disposable fetch leaves non-writable pack/index/reverse-index objects, yet JSON/non-TTY
# and human/TTY dry-runs complete without prompting, mutating local refs, or changing local state.
command -v script >/dev/null
command -v timeout >/dev/null
real_git="$(command -v git)"
packed_seed="$test_root/packed-seed"
packed_remote="$test_root/packed.git"
packed_checkout="$test_root/packed-checkout"
git clone -q "$seed" "$packed_seed"
git -C "$packed_seed" config user.name 'Update Pack Tests'
git -C "$packed_seed" config user.email 'tests@example.invalid'
git clone -q --bare "$packed_seed" "$packed_remote"
git clone -q "$packed_remote" "$packed_checkout"
mkdir -p "$packed_seed/pack-payload"
for index in $(seq 1 8); do
  dd if=/dev/urandom of="$packed_seed/pack-payload/$index.bin" bs=131072 count=1 status=none
done
git -C "$packed_seed" add pack-payload
git -C "$packed_seed" commit -q -m 'fixture: force fetched pack data'
packed_v3="$(git -C "$packed_seed" rev-parse HEAD)"
git -C "$packed_seed" push -q "$packed_remote" main
packed_local="$(git -C "$packed_checkout" rev-parse HEAD)"
[[ $packed_local != "$packed_v3" ]]

git_wrapper_dir="$test_root/git-wrapper"
pack_evidence="$test_root/non-writable-pack-evidence.tsv"
mkdir -p "$git_wrapper_dir"
cat >"$git_wrapper_dir/git" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
"$J3W1ZSH_TEST_REAL_GIT" "$@"
status=$?
((status == 0)) || exit "$status"

is_fetch=0
for argument in "$@"; do
  [[ $argument != fetch ]] || is_fetch=1
done
if ((is_fetch == 1)) && [[ ${1:-} == -C ]]; then
  case "${2:-}" in
  "$TMPDIR"/j3w1zsh-update-relation.*)
    pack_dir="$2/.git/objects/pack"
    for extension in pack idx rev; do
      object="$(find "$pack_dir" -maxdepth 1 -type f -name "*.$extension" -print -quit)"
      [[ -n $object ]] || {
        printf 'Expected fetched .%s object was not created in %s.\n' "$extension" "$pack_dir" >&2
        exit 97
      }
    done
    find "$pack_dir" -maxdepth 1 -type f \( -name '*.pack' -o -name '*.idx' -o -name '*.rev' \) -exec chmod a-w -- {} +
    for extension in pack idx rev; do
      while IFS= read -r object; do
        printf '%s\t%s\n' "$extension" "$(stat -c %A -- "$object")" >>"$J3W1ZSH_TEST_PACK_EVIDENCE"
      done < <(find "$pack_dir" -maxdepth 1 -type f -name "*.$extension" -print)
    done
    ;;
  esac
fi
EOF
chmod +x "$git_wrapper_dir/git"

probe_home="$test_root/probe-home"
probe_tmp="$test_root/probe-tmp"
mkdir -p \
  "$probe_home/.local/state/j3w1zsh/phases" \
  "$probe_home/.local/state/j3w1zsh/packages/repairs" \
  "$probe_home/.local/state/j3w1zsh/migrations/recovery-one" \
  "$probe_home/.local/state/j3w1zsh/migrations/recovery-two" \
  "$probe_home/.local/state/j3w1zsh/manual" \
  "$probe_tmp"
printf '{"phase":"historical-false-20"}\n' >"$probe_home/.local/state/j3w1zsh/phases/20-packages.json"
printf '{"packages":["pnpm","stylua"]}\n' >"$probe_home/.local/state/j3w1zsh/packages/provenance.json"
printf 'unresolved corepack checkpoint\n' >"$probe_home/.local/state/j3w1zsh/manual/pnpm-corepack"
printf 'preserve recovery one\n' >"$probe_home/.local/state/j3w1zsh/migrations/recovery-one/journal"
printf 'preserve recovery two\n' >"$probe_home/.local/state/j3w1zsh/migrations/recovery-two/journal"

snapshot_tree() {
  local root="$1"
  {
    find "$root" -mindepth 1 -printf '%P\t%y\t%m\t%s\t%l\n' | LC_ALL=C sort
    find "$root" -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum
  } | sha256sum | awk '{print $1}'
}

probe_state_before="$(snapshot_tree "$probe_home")"
probe_refs_before="$(git -C "$packed_checkout" show-ref)"
probe_config_before="$(sha256sum "$packed_checkout/.git/config" | awk '{print $1}')"
probe_head_before="$(git -C "$packed_checkout" rev-parse HEAD)"
probe_status_before="$(git -C "$packed_checkout" status --porcelain=v1 --untracked-files=all)"
probe_environment=(
  HOME="$probe_home"
  XDG_STATE_HOME="$probe_home/.local/state"
  XDG_CONFIG_HOME="$probe_home/.config"
  XDG_CACHE_HOME="$probe_home/.cache"
  TMPDIR="$probe_tmp"
  PATH="$git_wrapper_dir:$PATH"
  J3W1ZSH_TEST_MODE=1
  J3W1ZSH_TEST_PLATFORM=wsl
  J3W1ZSH_TEST_CANONICAL_URL="$packed_remote"
  J3W1ZSH_TEST_OLD_CANONICAL_URL="$test_root/former.git"
  J3W1ZSH_TEST_REAL_GIT="$real_git"
  J3W1ZSH_TEST_PACK_EVIDENCE="$pack_evidence"
  GIT_CONFIG_COUNT=2
  GIT_CONFIG_KEY_0=fetch.unpackLimit
  GIT_CONFIG_VALUE_0=1
  GIT_CONFIG_KEY_1=pack.writeReverseIndex
  GIT_CONFIG_VALUE_1=true
)

probe_json_file="$test_root/probe-nontty.json"
probe_nontty_stderr="$test_root/probe-nontty.stderr"
timeout 20 env "${probe_environment[@]}" "$packed_checkout/bin/j3w1zsh" update --dry-run --json \
  </dev/null >"$probe_json_file" 2>"$probe_nontty_stderr"
jq -e --arg local "$packed_local" --arg remote "$packed_v3" '
  .status == "ok" and .data.dry_run == true and .data.local_refs_changed == false and
  .data.tracking_relation.local_oid == $local and .data.tracking_relation.remote_oid == $remote and
  .data.tracking_relation.ahead == 0 and .data.tracking_relation.behind == 1 and
  .data.tracking_relation.diverged == false
' "$probe_json_file" >/dev/null
if rg -i 'remove write-protected|\[[yn]/[yn]\]|confirmation' "$probe_json_file" "$probe_nontty_stderr"; then
  printf 'Non-TTY update dry-run emitted an interactive cleanup prompt.\n' >&2
  exit 1
fi
[[ -z $(find "$probe_tmp" -mindepth 1 -maxdepth 1 -type d -name 'j3w1zsh-update-relation.*' -print -quit) ]]

probe_tty_transcript="$test_root/probe-tty.transcript"
probe_tty_stdout="$test_root/probe-tty.stdout"
probe_tty_stderr="$test_root/probe-tty.stderr"
probe_tty_command=(env "${probe_environment[@]}" "$packed_checkout/bin/j3w1zsh" update --dry-run)
printf -v probe_tty_shell '%q ' "${probe_tty_command[@]}"
timeout 20 script -qefc "$probe_tty_shell" "$probe_tty_transcript" </dev/null >"$probe_tty_stdout" 2>"$probe_tty_stderr"
rg -q 'Update preview complete' "$probe_tty_transcript" "$probe_tty_stdout"
if rg -i 'remove write-protected|\[[yn]/[yn]\]|confirmation' "$probe_tty_transcript" "$probe_tty_stdout" "$probe_tty_stderr"; then
  printf 'TTY update dry-run emitted an interactive cleanup prompt.\n' >&2
  exit 1
fi
[[ -z $(find "$probe_tmp" -mindepth 1 -maxdepth 1 -type d -name 'j3w1zsh-update-relation.*' -print -quit) ]]

for extension in pack idx rev; do
  awk -F '\t' -v extension="$extension" '
    $1 == extension { seen=1; if ($2 ~ /w/) bad=1 }
    END { exit !(seen == 1 && bad != 1) }
  ' "$pack_evidence"
done
[[ $(git -C "$packed_checkout" rev-parse HEAD) == "$probe_head_before" ]]
[[ $(git -C "$packed_checkout" show-ref) == "$probe_refs_before" ]]
[[ $(sha256sum "$packed_checkout/.git/config" | awk '{print $1}') == "$probe_config_before" ]]
[[ $(git -C "$packed_checkout" status --porcelain=v1 --untracked-files=all) == "$probe_status_before" ]]
[[ $(snapshot_tree "$probe_home") == "$probe_state_before" ]]
[[ $(find "$probe_home/.local/state/j3w1zsh/migrations" -mindepth 1 -maxdepth 1 -type d | wc -l) == 2 ]]

# A fork with a canonical upstream uses the same guarded comparison path without changing origin,
# upstream, refs, state, or the deliberately divergent fork commit.
fork_probe_work="$test_root/fork-probe-work"
fork_probe_remote="$test_root/fork-probe.git"
fork_probe_checkout="$test_root/fork-probe-checkout"
git clone -q "$packed_checkout" "$fork_probe_work"
git -C "$fork_probe_work" config user.name 'Update Fork Probe'
git -C "$fork_probe_work" config user.email 'tests@example.invalid'
printf 'fork probe\n' >"$fork_probe_work/fork-probe.txt"
git -C "$fork_probe_work" add fork-probe.txt
git -C "$fork_probe_work" commit -q -m 'fixture: fork probe commit'
git clone -q --bare "$fork_probe_work" "$fork_probe_remote"
git clone -q "$fork_probe_remote" "$fork_probe_checkout"
git -C "$fork_probe_checkout" remote add upstream "$packed_remote"
fork_probe_head="$(git -C "$fork_probe_checkout" rev-parse HEAD)"
fork_probe_origin="$(git -C "$fork_probe_checkout" remote get-url origin)"
fork_probe_refs="$(git -C "$fork_probe_checkout" show-ref)"
fork_probe_home="$test_root/fork-probe-home"
mkdir -p "$fork_probe_home"
fork_probe_json="$test_root/fork-probe.json"
timeout 20 env \
  HOME="$fork_probe_home" XDG_STATE_HOME="$fork_probe_home/.local/state" XDG_CONFIG_HOME="$fork_probe_home/.config" XDG_CACHE_HOME="$fork_probe_home/.cache" \
  TMPDIR="$probe_tmp" PATH="$git_wrapper_dir:$PATH" J3W1ZSH_TEST_MODE=1 J3W1ZSH_TEST_PLATFORM=wsl \
  J3W1ZSH_TEST_CANONICAL_URL="$packed_remote" J3W1ZSH_TEST_OLD_CANONICAL_URL="$test_root/former.git" \
  J3W1ZSH_TEST_REAL_GIT="$real_git" J3W1ZSH_TEST_PACK_EVIDENCE="$pack_evidence" \
  GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_0=fetch.unpackLimit GIT_CONFIG_VALUE_0=1 GIT_CONFIG_KEY_1=pack.writeReverseIndex GIT_CONFIG_VALUE_1=true \
  "$fork_probe_checkout/bin/j3w1zsh" update --dry-run --json </dev/null >"$fork_probe_json"
jq -e '
  .status == "ok" and .data.local_refs_changed == false and .data.repository.identity == "fork" and
  .data.tracking_relation.ahead == 0 and .data.tracking_relation.behind == 0 and
  .data.canonical_relation.ahead == 1 and .data.canonical_relation.behind == 1 and
  .data.canonical_relation.diverged == true
' "$fork_probe_json" >/dev/null
[[ $(git -C "$fork_probe_checkout" rev-parse HEAD) == "$fork_probe_head" ]]
[[ $(git -C "$fork_probe_checkout" remote get-url origin) == "$fork_probe_origin" ]]
[[ $(git -C "$fork_probe_checkout" remote get-url upstream) == "$packed_remote" ]]
[[ $(git -C "$fork_probe_checkout" show-ref) == "$fork_probe_refs" ]]
[[ -z $(find "$probe_tmp" -mindepth 1 -maxdepth 1 -type d -name 'j3w1zsh-update-relation.*' -print -quit) ]]
[[ ! -e $fork_probe_home/.local/state/j3w1zsh ]]

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
  trap - EXIT
  J3W1ZSH_REPO_ROOT="$deep_local"
  J3W1ZSH_TEST_MODE=1
  J3W1ZSH_STATE_DIR="$test_root/deep-state"
  J3W1ZSH_CONFIG_DIR="$test_root/deep-config"
  J3W1ZSH_EXIT_FAILURE=1
  # shellcheck source=scripts/lib/core/filesystem.sh
  source "$repo_root/scripts/lib/core/filesystem.sh"
  source "$repo_root/scripts/lib/core/git.sh"
  j3w1zsh_git_relation "$deep_remote" refs/heads/main "$deep_tip"
})"
jq -e '.ahead == 0 and .behind == 120 and .diverged == false' <<<"$deep_relation" >/dev/null

printf 'Update prompt-free guarded dry-run, TTY/non-TTY, fork/canonical relation, selection, full-history, fast-forward, relaunch, generated repair, protected state, and redirect tests passed.\n'
