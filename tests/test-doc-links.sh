#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$repo_root"

failure=0
while IFS= read -r -d '' document; do
  while IFS= read -r link; do
    case "$link" in
    "" | \#* | http://* | https://* | mailto:*) continue ;;
    esac
    link="${link%%#*}"
    link="${link#<}"
    link="${link%>}"
    target="$(dirname -- "$document")/$link"
    if [[ $document == ./wiki/* && ! -e $target && -e $target.md ]]; then
      target="$target.md"
    fi
    if [[ ! -e $target ]]; then
      printf 'Broken relative documentation link: %s -> %s\n' "$document" "$link" >&2
      failure=1
    fi
  done < <(
    awk '
      /^```/ { fenced = !fenced; next }
      fenced { next }
      {
        line = $0
        gsub(/`[^`]*`/, "", line)
        print line
      }
    ' "$document" |
      grep -oE '\]\([^)]+\)' |
      sed -E 's/^\]\((.*)\)$/\1/'
  )
done < <(find . -type f -name '*.md' -not -path './.git/*' -print0)

((failure == 0))
printf 'Documentation link test passed.\n'
