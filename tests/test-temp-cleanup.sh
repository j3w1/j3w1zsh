#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
test_root="$(mktemp -d)"
trap 'rm -rf -- "$test_root"' EXIT

home="$test_root/home"
runtime_tmp="$test_root/runtime-tmp"
mkdir -p "$home" "$runtime_tmp"

# shellcheck disable=SC2030
(
  trap - EXIT
  export HOME="$home"
  export TMPDIR="$runtime_tmp"
  export XDG_STATE_HOME="$home/.local/state"
  export XDG_CONFIG_HOME="$home/.config"
  export XDG_CACHE_HOME="$home/.cache"
  export J3W1ZSH_REPO_ROOT="$repo_root"
  export J3W1ZSH_TEST_MODE=1
  # shellcheck source=scripts/lib/core/init.sh
  source "$repo_root/scripts/lib/core/init.sh"

  guarded=""
  j3w1zsh_create_ephemeral_dir guarded update-relation
  mkdir -p "$guarded/.git/objects/pack"
  printf 'pack\n' >"$guarded/.git/objects/pack/test.pack"
  chmod 400 "$guarded/.git/objects/pack/test.pack"
  j3w1zsh_cleanup_ephemeral_dir "$guarded"
  [[ ! -e $guarded && ! -L $guarded ]]

  arbitrary="$test_root/arbitrary-user-owned"
  mkdir -p "$arbitrary"
  printf 'preserve\n' >"$arbitrary/sentinel"
  if j3w1zsh_cleanup_ephemeral_dir "$arbitrary" 2>/dev/null; then
    printf 'Unguarded arbitrary directory was accepted for cleanup.\n' >&2
    exit 1
  fi
  [[ -f $arbitrary/sentinel ]]

  j3w1zsh_create_ephemeral_dir guarded update-relation
  original="$guarded.original"
  mv -- "$guarded" "$original"
  ln -s -- "$arbitrary" "$guarded"
  if j3w1zsh_cleanup_ephemeral_dir "$guarded" 2>/dev/null; then
    printf 'Symlink substitution was accepted for cleanup.\n' >&2
    exit 1
  fi
  [[ -f $arbitrary/sentinel ]]
  rm -- "$guarded"
  mv -- "$original" "$guarded"
  j3w1zsh_cleanup_ephemeral_dir "$guarded"

  j3w1zsh_create_ephemeral_dir guarded update-relation
  chmod 600 "$guarded/.j3w1zsh-ephemeral"
  printf 'forged\n' >"$guarded/.j3w1zsh-ephemeral"
  chmod 400 "$guarded/.j3w1zsh-ephemeral"
  if j3w1zsh_cleanup_ephemeral_dir "$guarded" 2>/dev/null; then
    printf 'Invalid ownership marker was accepted for cleanup.\n' >&2
    exit 1
  fi
  chmod 600 "$guarded/.j3w1zsh-ephemeral"
  printf 'j3w1zsh:%s:update-relation\n' "$BASHPID" >"$guarded/.j3w1zsh-ephemeral"
  chmod 400 "$guarded/.j3w1zsh-ephemeral"
  j3w1zsh_cleanup_ephemeral_dir "$guarded"
)

failure_tmp="$test_root/failure-tmp"
mkdir -p "$failure_tmp"
set +e
# shellcheck disable=SC2031
(
  trap - EXIT
  export HOME="$home"
  export TMPDIR="$failure_tmp"
  export XDG_STATE_HOME="$home/.local/state"
  export XDG_CONFIG_HOME="$home/.config"
  export XDG_CACHE_HOME="$home/.cache"
  export J3W1ZSH_REPO_ROOT="$repo_root"
  export J3W1ZSH_TEST_MODE=1
  # shellcheck source=scripts/lib/core/init.sh
  source "$repo_root/scripts/lib/core/init.sh"
  intermediate=""
  j3w1zsh_create_ephemeral_dir intermediate update-relation
  mkdir -p "$intermediate/.git/objects/pack"
  printf 'pack\n' >"$intermediate/.git/objects/pack/failure.pack"
  chmod 400 "$intermediate/.git/objects/pack/failure.pack"
  false
)
failure_status=$?
set -e
[[ $failure_status != 0 ]]
[[ -z $(find "$failure_tmp" -mindepth 1 -maxdepth 1 -name 'j3w1zsh-update-relation.*' -print -quit) ]]

recursive_pattern='rm[[:space:]]+-r(f)?[[:space:]]'
mapfile -t actual_cleanup_files < <(
  rg -l --glob '*.sh' \
    -e "^[[:space:]]*$recursive_pattern" \
    -e "\\|\\|[[:space:]]*$recursive_pattern" \
    -e "trap[[:space:]].*$recursive_pattern" \
    "$repo_root" | sed "s#^$repo_root/##" | LC_ALL=C sort
)
mapfile -t allowed_cleanup_files < <(tail -n +2 "$repo_root/tests/recursive-cleanup-allowlist.tsv" | cut -f1 | LC_ALL=C sort)
[[ $(printf '%s\n' "${actual_cleanup_files[@]}") == "$(printf '%s\n' "${allowed_cleanup_files[@]}")" ]] || {
  printf 'Recursive cleanup file inventory differs from the explicit allowlist.\n' >&2
  printf 'Actual:\n%s\nAllowed:\n%s\n' "${actual_cleanup_files[*]}" "${allowed_cleanup_files[*]}" >&2
  exit 1
}

while IFS=$'\t' read -r path expected_count classification reason; do
  [[ $path != path ]] || continue
  [[ $classification == ephemeral-script-owned || $classification == persistent-product-derived ||
    $classification == arbitrary-user-owned || $classification == test-fixture ]]
  [[ -n $reason ]]
  actual_count="$(rg -c --glob '*.sh' \
    -e "^[[:space:]]*$recursive_pattern" \
    -e "\\|\\|[[:space:]]*$recursive_pattern" \
    -e "trap[[:space:]].*$recursive_pattern" \
    "$repo_root/$path")"
  [[ $actual_count == "$expected_count" ]] || {
    printf 'Recursive cleanup count changed for %s: expected %s, found %s.\n' "$path" "$expected_count" "$actual_count" >&2
    exit 1
  }
done <"$repo_root/tests/recursive-cleanup-allowlist.tsv"

mapfile -t production_mktemp_dirs < <(rg -n --glob '*.sh' 'mktemp[[:space:]]+-d' "$repo_root/scripts")
[[ ${#production_mktemp_dirs[@]} == 2 ]]
[[ ${production_mktemp_dirs[0]} == *scripts/legacy/migrate-to-j3w1zsh.sh* || ${production_mktemp_dirs[1]} == *scripts/legacy/migrate-to-j3w1zsh.sh* ]]
[[ ${production_mktemp_dirs[0]} == *scripts/lib/core/filesystem.sh* || ${production_mktemp_dirs[1]} == *scripts/lib/core/filesystem.sh* ]]

mapfile -t production_forced_removals < <(rg -n --glob '*.sh' 'rm[[:space:]]+-rf[[:space:]]' "$repo_root/scripts")
[[ ${#production_forced_removals[@]} == 2 ]]
[[ ${production_forced_removals[0]} == *scripts/legacy/migrate-to-j3w1zsh.sh* || ${production_forced_removals[1]} == *scripts/legacy/migrate-to-j3w1zsh.sh* ]]
[[ ${production_forced_removals[0]} == *scripts/lib/core/filesystem.sh* || ${production_forced_removals[1]} == *scripts/lib/core/filesystem.sh* ]]

printf 'Guarded runtime cleanup, failure cleanup, symlink/marker rejection, and recursive-removal policy tests passed.\n'
