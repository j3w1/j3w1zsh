#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
test_root="$(mktemp -d)"
trap 'rm -rf -- "$test_root"' EXIT

while IFS= read -r route_path; do
  [[ -e $repo_root/$route_path ]] || {
    printf 'Agent route points to a missing code path: %s\n' "$route_path" >&2
    exit 1
  }
done < <(jq -r '.routes[].code_paths[]' "$repo_root/agent-context.json" | LC_ALL=C sort -u)

# The prepared source contains every exact required page and no broken internal page link.
while IFS= read -r page; do
  file="${page// /-}.md"
  [[ -s $repo_root/wiki/$file ]] || { printf 'Missing required Wiki page: %s\n' "$file" >&2; exit 1; }
done < <(jq -r '.required_pages[]' "$repo_root/wiki-lock.json")

while IFS=$'\t' read -r source link; do
  case "$link" in http://* | https://* | mailto:* | \#* | '') continue ;; esac
  target="${link%%#*}"
  target="${target%.md}.md"
  [[ -f $repo_root/wiki/$target ]] || { printf 'Broken Wiki link in %s: %s\n' "$source" "$link" >&2; exit 1; }
done < <(
  for source in "$repo_root"/wiki/*.md; do
    while IFS= read -r link; do
      printf '%s\t%s\n' "$(basename -- "$source")" "$link"
    done < <((grep -oE '\]\([^)]+\)' "$source" || true) | sed -E 's/^\]\((.*)\)$/\1/')
  done
)

wiki_seed="$test_root/wiki-seed"
wiki_remote="$test_root/wiki.git"
mkdir -p "$wiki_seed"
cp "$repo_root"/wiki/*.md "$wiki_seed/"
git -C "$wiki_seed" init -q -b main
git -C "$wiki_seed" config user.name 'Wiki Tests'
git -C "$wiki_seed" config user.email 'tests@example.invalid'
git -C "$wiki_seed" add .
git -C "$wiki_seed" commit -q -m 'fixture: pinned wiki'
wiki_oid="$(git -C "$wiki_seed" rev-parse HEAD)"
git clone -q --bare "$wiki_seed" "$wiki_remote"

lock="$test_root/wiki-lock.json"
jq --arg commit "$wiki_oid" '.commit=$commit' "$repo_root/wiki-lock.json" >"$lock"
home="$test_root/home"
mkdir -p "$home"
run_wiki() {
  env HOME="$home" XDG_STATE_HOME="$home/.local/state" XDG_CONFIG_HOME="$home/.config" XDG_CACHE_HOME="$home/.cache" \
    J3W1ZSH_TEST_MODE=1 J3W1ZSH_TEST_PLATFORM=wsl J3W1ZSH_TEST_WIKI_URL="$wiki_remote" J3W1ZSH_TEST_WIKI_LOCK="$lock" \
    "$repo_root/bin/j3w1zsh" "$@"
}

sync_json="$(run_wiki wiki sync --json)"
jq -e --arg oid "$wiki_oid" '.status == "ok" and .data.commit == $oid and .data.latest_override == false' <<<"$sync_json" >/dev/null
materialized="$home/.local/state/j3w1zsh/wiki/pinned/$wiki_oid"
[[ $(git -C "$materialized" rev-parse HEAD) == "$wiki_oid" ]]
[[ -z $(git -C "$materialized" status --short) ]]

status_json="$(run_wiki wiki status --json)"
jq -e --arg oid "$wiki_oid" '.data.pinned_head == $oid and .data.local_head == $oid and .data.canonical_head == $oid and .data.compatible == true and .data.dirty == false' <<<"$status_json" >/dev/null

run_wiki wiki context workspace >/dev/null
context="$home/.local/state/j3w1zsh/wiki/context/workspace/$wiki_oid"
[[ -f $context/Workspace-Profiles-and-Schema-v2.md ]]
[[ -f $context/j3w1zsh-plan.md ]]
[[ -f $context/Security-Model.md ]]
[[ -f $context/route.json ]]
[[ $(find "$context" -maxdepth 1 -type f | wc -l) == 4 ]]
printf 'tampered context\n' >>"$context/Security-Model.md"
if run_wiki wiki context workspace >/dev/null 2>&1; then
  printf 'Dirty routed Wiki context was accepted as pinned.\n' >&2
  exit 1
fi
grep -q 'tampered context' "$context/Security-Model.md"

printf 'local edit\n' >>"$materialized/Home.md"
if run_wiki wiki sync >/dev/null 2>&1; then
  printf 'Dirty pinned Wiki materialization was overwritten.\n' >&2
  exit 1
fi

unreachable_lock="$test_root/unreachable-lock.json"
jq '.commit="1111111111111111111111111111111111111111"' "$lock" >"$unreachable_lock"
if env HOME="$test_root/unreachable-home" XDG_STATE_HOME="$test_root/unreachable-home/.local/state" XDG_CONFIG_HOME="$test_root/unreachable-home/.config" XDG_CACHE_HOME="$test_root/unreachable-home/.cache" \
  J3W1ZSH_TEST_MODE=1 J3W1ZSH_TEST_PLATFORM=wsl J3W1ZSH_TEST_WIKI_URL="$wiki_remote" J3W1ZSH_TEST_WIKI_LOCK="$unreachable_lock" \
  "$repo_root/bin/j3w1zsh" wiki sync >/dev/null 2>&1; then
  printf 'Unreachable Wiki lock unexpectedly synchronized.\n' >&2
  exit 1
fi

# Publication starts from an initialized Home-only Wiki, pushes first, verifies, then updates the test lock.
publish_seed="$test_root/publish-seed"
publish_remote="$test_root/publish.git"
mkdir -p "$publish_seed"
printf '# Seed Home\n' >"$publish_seed/Home.md"
git -C "$publish_seed" init -q -b main
git -C "$publish_seed" config user.name 'Wiki Tests'
git -C "$publish_seed" config user.email 'tests@example.invalid'
git -C "$publish_seed" add Home.md
git -C "$publish_seed" commit -q -m 'Initialize Home'
git clone -q --bare "$publish_seed" "$publish_remote"
publish_lock="$test_root/publish-lock.json"
cp "$repo_root/wiki-lock.json" "$publish_lock"
publish_home="$test_root/publish-home"
mkdir -p "$publish_home"
env HOME="$publish_home" XDG_STATE_HOME="$publish_home/.local/state" XDG_CONFIG_HOME="$publish_home/.config" XDG_CACHE_HOME="$publish_home/.cache" \
  GIT_AUTHOR_NAME='Wiki Tests' GIT_AUTHOR_EMAIL='tests@example.invalid' GIT_COMMITTER_NAME='Wiki Tests' GIT_COMMITTER_EMAIL='tests@example.invalid' \
  J3W1ZSH_ASSUME_YES=1 J3W1ZSH_TEST_MODE=1 J3W1ZSH_TEST_PLATFORM=wsl J3W1ZSH_TEST_WIKI_URL="$publish_remote" J3W1ZSH_TEST_WIKI_LOCK="$publish_lock" \
  "$repo_root/bin/j3w1zsh" wiki publish >/dev/null
published_oid="$(git --git-dir="$publish_remote" rev-parse HEAD)"
[[ $(jq -r .commit "$publish_lock") == "$published_oid" ]]
for required in Home.md _Sidebar.md _Footer.md Screenshot-and-Showcase-Guide.md; do
  git --git-dir="$publish_remote" cat-file -e "$published_oid:$required"
done

# Publishing the already complete Wiki is an idempotent no-op, including required page names
# whose canonical filenames contain meaningful hyphens.
env HOME="$publish_home" XDG_STATE_HOME="$publish_home/.local/state" XDG_CONFIG_HOME="$publish_home/.config" XDG_CACHE_HOME="$publish_home/.cache" \
  GIT_AUTHOR_NAME='Wiki Tests' GIT_AUTHOR_EMAIL='tests@example.invalid' GIT_COMMITTER_NAME='Wiki Tests' GIT_COMMITTER_EMAIL='tests@example.invalid' \
  J3W1ZSH_ASSUME_YES=1 J3W1ZSH_TEST_MODE=1 J3W1ZSH_TEST_PLATFORM=wsl J3W1ZSH_TEST_WIKI_URL="$publish_remote" J3W1ZSH_TEST_WIKI_LOCK="$publish_lock" \
  "$repo_root/bin/j3w1zsh" wiki publish >/dev/null
[[ $(git --git-dir="$publish_remote" rev-parse HEAD) == "$published_oid" ]]
[[ $(jq -r .commit "$publish_lock") == "$published_oid" ]]
git --git-dir="$publish_remote" cat-file -e "$published_oid:Workspace-v1-to-v2-Migration.md"

grep -q 'based on the pinned OID' "$repo_root/wiki/Maintenance-and-Releases.md"

printf 'Wiki pin, sync, status, routing, dirty preservation, publication, pages, and links tests passed.\n'
