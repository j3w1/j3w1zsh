#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$repo_root"

patterns=(
  '-----BEGIN ([A-Z ]+ )?PRIVATE KEY-----'
  'github_pat_[A-Za-z0-9_]+'
  'gh[opsu]_[A-Za-z0-9]{20,}'
  'sk-[A-Za-z0-9_-]{20,}'
  '(api[_-]?key|access[_-]?token|client[_-]?secret)[[:space:]]*=[[:space:]]*["'\''][^"'\'']+'
  '/home/j3w1'
  '/mnt/c/Users/iqbal'
  'C:\\Users\\iqbal'
  'id_ed25519_github_[A-Za-z0-9_-]+'
)

failure=0
pattern=""
for pattern in "${patterns[@]}"; do
  if rg --no-ignore --hidden --glob '!.git' --glob '!.git/**' --glob '!tests/security-scan.sh' -n -i -e "$pattern" .; then
    printf 'Security scan matched forbidden pattern: %s\n' "$pattern" >&2
    failure=1
  fi
done

if find . -type f \
  \( -name 'auth.json' -o -name 'hosts.yml' -o -name 'id_ed25519*' -o -name '*.sqlite' \) \
  -not -path './.git/*' | grep -q .; then
  printf 'Security scan found a forbidden credential/state filename.\n' >&2
  find . -type f \
    \( -name 'auth.json' -o -name 'hosts.yml' -o -name 'id_ed25519*' -o -name '*.sqlite' \) \
    -not -path './.git/*' >&2
  failure=1
fi

((failure == 0))
printf 'Security scan passed.\n'
