#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$repo_root"

printf 'Checking Bash syntax...\n'
while IFS= read -r -d '' file; do
  bash -n "$file"
done < <(find . -path ./.git -prune -o -type f -name '*.sh' -print0)

printf 'Checking Zsh syntax...\n'
zsh -n dotfiles/zsh/.zshrc dotfiles/zsh/settings.zsh.example

printf 'Running ShellCheck...\n'
mapfile -d '' shell_files < <(find . -path ./.git -prune -o -type f -name '*.sh' -print0)
shellcheck -x "${shell_files[@]}"

printf 'Parsing strict JSON artifacts...\n'
while IFS= read -r -d '' file; do
  jq empty "$file"
done < <(find . -path ./.git -prune -o -type f -name '*.json' -print0)
jq -e '.schema_version == 1 and .id == "j3w1"' presets/j3w1.json >/dev/null
jq -e '.schema_version == 1 and .id == "minimal"' presets/minimal.json >/dev/null
jq -e '.schema_version == 1 and .id == "j3w1zsh" and (.ansi | length == 16)' themes/j3w1zsh/theme.json >/dev/null
jq -e '.properties.schema_version.const == 2' schemas/workspace-profile-v2.schema.json >/dev/null
jq -e '.properties.schema_version.const == 1' schemas/preset-v1.schema.json schemas/theme-v1.schema.json >/dev/null

printf 'Checking executable product and test entrypoints...\n'
expected_executables=(
  install.sh
  bin/j3w1zsh
  scripts/bootstrap-root.sh
  scripts/legacy/migrate-to-j3w1zsh.sh
  scripts/render-brand.py
  scripts/update-neovim-lock.sh
  dotfiles/local-bin/.local/bin/j3w1zsh-clipboard-copy
  dotfiles/local-bin/.local/bin/tma
)
while IFS= read -r test_file; do
  expected_executables+=("$test_file")
done < <(find tests -maxdepth 1 -type f -name '*.sh' -print | LC_ALL=C sort)
for file in "${expected_executables[@]}"; do
  [[ -x $file ]] || {
    printf 'Expected executable bit: %s\n' "$file" >&2
    exit 1
  }
done

printf 'Checking brand source and generated derivative...\n'
[[ -s assets/brand/j3w1zsh.svg && -s assets/brand/j3w1zsh.png ]]
python3 scripts/render-brand.py --check

printf 'Checking migration bootstrap checksum...\n'
(cd scripts/legacy && sha256sum -c ../../checksums/migrate-to-j3w1zsh.sha256)

tests/security-scan.sh
tests/identity-scan.sh
tests/test-doc-links.sh
tests/test-foundation.sh
tests/test-linker.sh
tests/test-cli-output.sh
tests/test-platform-contract.sh
tests/test-packages-themes.sh
tests/test-package-execution.sh
tests/test-temp-cleanup.sh
tests/test-terminal-contract.sh
tests/test-remote.sh
tests/test-tma.sh
tests/test-zsh-prompt.sh
tests/test-powershell.sh
tests/test-workspace-v2.sh
tests/test-legacy-migration.sh
tests/test-update-v1.sh
tests/test-wiki.sh

printf 'Checking whitespace...\n'
git diff --check

printf 'All tests passed.\n'
