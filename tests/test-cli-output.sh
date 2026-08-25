#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
test_root="$(mktemp -d)"
trap 'rm -rf -- "$test_root"' EXIT
home="$test_root/home"
mkdir -p "$home"
run_cli() {
  env HOME="$home" XDG_STATE_HOME="$home/.local/state" XDG_CONFIG_HOME="$home/.config" XDG_CACHE_HOME="$home/.cache" \
    J3W1ZSH_TEST_MODE=1 J3W1ZSH_TEST_PLATFORM=termux "$repo_root/bin/j3w1zsh" "$@"
}

platform="$(run_cli platform --json)"
[[ $(wc -l <<<"$platform") == 1 ]]
jq -e '.schema_version==1 and .command=="platform" and .status=="ok" and .data.id=="termux"' <<<"$platform" >/dev/null

error_file="$test_root/error.json"
set +e
run_cli invalid --json 2>"$error_file"
code=$?
set -e
[[ $code == 2 && $(wc -l <"$error_file") == 1 ]]
jq -e '.command=="invalid" and .status=="error" and .error.code=="invalid_arguments"' "$error_file" >/dev/null

set +e
run_cli install --json --plain 2>"$error_file"
code=$?
set -e
[[ $code == 2 ]]
jq -e '.command=="install" and .status=="error" and .error.code=="invalid_arguments"' "$error_file" >/dev/null

set +e
NO_COLOR=1 run_cli --color=always invalid 2>"$test_root/always"
always_code=$?
NO_COLOR=1 run_cli invalid 2>"$test_root/auto"
auto_code=$?
run_cli --plain --color=always invalid 2>"$test_root/plain"
plain_code=$?
set -e
[[ $always_code == 2 && $auto_code == 2 && $plain_code == 2 ]]
grep -q $'\033' "$test_root/always"
if grep -q $'\033' "$test_root/auto" || grep -q $'\033' "$test_root/plain"; then
  printf 'Automatic or plain output emitted unexpected ANSI.\n' >&2
  exit 1
fi
grep -q '^\[x\] ' "$test_root/plain"

narrow="$(COLUMNS=50 run_cli install --preset minimal --no-packages --yes --plain)"
grep -qx 'j3w1zsh' <<<"$narrow"
grep -q 'one shell. every machine. zero compromise.' <<<"$narrow"
if grep -q '┌' <<<"$narrow"; then
  printf 'Narrow output used the wide banner.\n' >&2
  exit 1
fi
package_free_status="$(run_cli status --json)"
jq -e '(.data.phases[] | select(.phase=="20-packages") | .state)=="complete"' <<<"$package_free_status" >/dev/null

if run_cli list >/dev/null 2>&1; then
  printf 'The forbidden list alias was accepted.\n' >&2
  exit 1
fi
if run_cli platform -- --json >/dev/null 2>&1; then
  printf 'A global option after -- was incorrectly consumed.\n' >&2
  exit 1
fi

fake_bin="$test_root/bin"
argv_log="$test_root/argv.log"
mkdir -p "$fake_bin"
cat >"$fake_bin/nvim" <<'EOF'
#!/usr/bin/env bash
printf '<%s>\n' "$@" >"$J3W1ZSH_ARGV_LOG"
EOF
cat >"$fake_bin/tmux" <<'EOF'
#!/usr/bin/env bash
printf '<%s>\n' "$@" >"$J3W1ZSH_ARGV_LOG"
EOF
chmod +x "$fake_bin/nvim" "$fake_bin/tmux"
literal_target="$test_root/must-not-execute"
literal_path="\$(touch $literal_target)"
PATH="$fake_bin:$PATH" J3W1ZSH_ARGV_LOG="$argv_log" run_cli edit "$literal_path"
grep -Fqx '<-->' "$argv_log"
grep -Fqx "<\$(touch $literal_target)>" "$argv_log"
[[ ! -e $literal_target ]]
PATH="$fake_bin:$PATH" J3W1ZSH_ARGV_LOG="$argv_log" run_cli edit -- --plain
grep -Fqx '<-->' "$argv_log"
grep -Fqx '<--plain>' "$argv_log"
PATH="$fake_bin:$PATH" J3W1ZSH_ARGV_LOG="$argv_log" run_cli attach exact.session
grep -Fqx '<new-session>' "$argv_log"
grep -Fqx '<-A>' "$argv_log"
grep -Fqx '<-s>' "$argv_log"
grep -Fqx '<exact.session>' "$argv_log"
if PATH="$fake_bin:$PATH" run_cli attach 'bad/session' >/dev/null 2>&1; then
  printf 'Attach accepted an invalid session name.\n' >&2
  exit 1
fi

printf 'Global option order, stable JSON errors, color precedence, plain output, and narrow layout tests passed.\n'
