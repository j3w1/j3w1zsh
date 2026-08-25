#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
if ! command -v pwsh >/dev/null 2>&1; then
  printf 'PowerShell parser unavailable on this host; Windows-hosted CI remains required.\n'
  exit 0
fi

pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$repo_root/tests/test-powershell.ps1"
