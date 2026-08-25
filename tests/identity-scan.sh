#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$repo_root"
allowlist=tests/identity-allowlist.json
jq -e '
  type=="object" and (keys|sort)==(["paths","patterns","schema_version","wiki_paths"]|sort) and
  .schema_version==1 and (.patterns|type=="array" and length>0) and
  (.paths|type=="array" and length==(unique|length)) and
  (.wiki_paths|type=="array" and length==(unique|length))
' "$allowlist" >/dev/null
pattern="$(jq -r '.patterns | join("|")' "$allowlist")"

failure=0
while IFS= read -r matched; do
  path="${matched#./}"
  if ! jq -e --arg path "$path" '.paths | index($path)' "$allowlist" >/dev/null; then
    printf 'Former identity outside the exact migration allowlist: %s\n' "$path" >&2
    failure=1
  fi
  if [[ $path == wiki/* ]] && ! jq -e --arg path "$path" '.wiki_paths | index($path)' "$allowlist" >/dev/null; then
    printf 'Former identity on a non-migration Wiki page: %s\n' "$path" >&2
    failure=1
  fi
done < <(rg -l -i --hidden --glob '!.git/**' -e "$pattern" . | LC_ALL=C sort)

while IFS= read -r path; do
  [[ -e $path || -L $path ]] || {
    printf 'Stale identity allowlist path: %s\n' "$path" >&2
    failure=1
  }
done < <(jq -r '.paths[]' "$allowlist")

while IFS= read -r path; do
  if grep -Eiq "$pattern" <<<"$path"; then
    printf 'Former identity remains in an active filename or directory: %s\n' "$path" >&2
    failure=1
  fi
done < <(find . -path ./.git -prune -o -print | sed 's#^\./##')

((failure == 0))
printf 'Current identity content, filename, directory, and Wiki allowlist scan passed.\n'
