#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
lock="$repo_root/wiki-lock.json"
commit="$(jq -r .commit "$lock")"
repository="$(jq -r .repository "$lock")"

if [[ $commit == PENDING_PREMERGE_PUBLICATION ]]; then
  [[ ${GITHUB_REPOSITORY_ID:-} == 1318126833 && ${GITHUB_EVENT_NAME:-} == pull_request &&
    ${GITHUB_REPOSITORY:-} != j3w1/j3w1zsh ]] || {
    printf 'The transitional Wiki lock is allowed only for the exact pre-rename draft-PR repository.\n' >&2
    exit 1
  }
  printf 'Wiki publication is intentionally pending on the pre-rename draft PR.\n'
  exit 0
fi

[[ $commit =~ ^[0-9a-f]{40}$ ]] || {
  printf 'Wiki lock commit is not an immutable 40-hex OID: %s\n' "$commit" >&2
  exit 1
}
url="https://github.com/$repository.wiki.git"
temporary="$(mktemp -d)"
trap 'rm -rf -- "$temporary"' EXIT
git -C "$temporary" init -q
git -C "$temporary" remote add origin "$url"
git -C "$temporary" fetch -q --depth=1 origin "$commit"
[[ $(git -C "$temporary" rev-parse FETCH_HEAD) == "$commit" ]]

while IFS= read -r page; do
  file="${page// /-}.md"
  git -C "$temporary" cat-file -e "$commit:$file" || {
    printf 'Required Wiki page is missing at %s: %s\n' "$commit" "$file" >&2
    exit 1
  }
done < <(jq -r '.required_pages[]' "$lock")

printf 'Pinned Wiki commit is reachable and contains every required page: %s\n' "$commit"
