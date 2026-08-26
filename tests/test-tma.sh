#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
test_root="$(mktemp -d)"
real_tmux="$(command -v tmux || true)"
real_tmux_socket=""
cleanup() {
  if [[ -n $real_tmux && -n $real_tmux_socket ]]; then
    "$real_tmux" -L "$real_tmux_socket" kill-server >/dev/null 2>&1 || true
  fi
  rm -rf -- "$test_root"
}
trap cleanup EXIT
mkdir -p "$test_root/bin"

export TMA_FAKE_STATE="$test_root/state"
export TMA_FAKE_LOG="$test_root/log"
export TMA_FAKE_FORMAT="$test_root/format"
printf 'j3w1zsh-smoke\tdetached\nsecond.attached\tattached\nops_session\tdetached\n' >"$TMA_FAKE_STATE"
: >"$TMA_FAKE_LOG"

apply_fake_tmux="$test_root/bin/tmux"
cp "$repo_root/tests/fixtures/fake-tmux.sh" "$apply_fake_tmux"
chmod +x "$apply_fake_tmux"

tma="$repo_root/dotfiles/local-bin/.local/bin/tma"
fake_dotted_target="\$1"
help_output="$(PATH="$test_root/bin:$PATH" "$tma" --help)"
grep -q 'Ctrl-X' <<<"$help_output"
grep -q 'confirmation' <<<"$help_output"
grep -q 'Termux on Android' <<<"$help_output"
grep -q 'j3w1zsh' <<<"$help_output"

session_rows="$(PATH="$test_root/bin:$PATH" "$tma" --list)"
[[ $(grep -o $'\t' <<<"$session_rows" | wc -l) == 9 ]]
if grep -Fq '\t' <<<"$session_rows" || grep -Fq '\t' "$TMA_FAKE_FORMAT"; then
  printf 'tma emitted literal backslash-t characters instead of tab delimiters.\n' >&2
  exit 1
fi
[[ $(grep -o $'\t' "$TMA_FAKE_FORMAT" | wc -l) == 3 ]]
grep -Fqx $'j3w1zsh-smoke\t1 window(s)\tdetached\tcreated now' <<<"$session_rows"
grep -Fqx $'second.attached\t1 window(s)\tattached\tcreated now' <<<"$session_rows"

PATH="$test_root/bin:$PATH" "$tma" ops_session
grep -qx 'attach =ops_session' "$TMA_FAKE_LOG"
PATH="$test_root/bin:$PATH" "$tma" second.attached
grep -Fqx "attach $fake_dotted_target" "$TMA_FAKE_LOG"
TMUX=active PATH="$test_root/bin:$PATH" "$tma" second.attached
grep -Fqx "switch $fake_dotted_target" "$TMA_FAKE_LOG"

cat >"$test_root/bin/fzf" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

binding=""
for argument in "$@"; do
  case "$argument" in
  --bind=*) binding="${argument#--bind=}" ;;
  esac
done
mapfile -t rows
case "${TMA_FAKE_FZF_MODE:-select}" in
cancel) exit 130 ;;
select | kill) ;;
*) exit 2 ;;
esac
selection=""
for row in "${rows[@]}"; do
  [[ ${row%%$'\t'*} != "$TMA_FAKE_FZF_SELECTION" ]] || selection="$row"
done
[[ -n $selection ]] || exit 3
if [[ ${TMA_FAKE_FZF_MODE:-select} == kill ]]; then
  [[ $binding == *'ctrl-x:execute('*' --kill {1})+reload('* ]]
  printf 'y' | "$TMA_TEST_TMA" --kill "${selection%%$'\t'*}" >/dev/null
  exit 130
fi
printf '%s\n' "$selection"
EOF
chmod +x "$test_root/bin/fzf"

interactive_wrapper="$test_root/interactive-tma.sh"
cat >"$interactive_wrapper" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
export PATH=$(printf '%q' "$test_root/bin:$PATH")
export TMA_FAKE_STATE=$(printf '%q' "$TMA_FAKE_STATE")
export TMA_FAKE_LOG=$(printf '%q' "$TMA_FAKE_LOG")
export TMA_FAKE_FORMAT=$(printf '%q' "$TMA_FAKE_FORMAT")
export TMA_TEST_TMA=$(printf '%q' "$tma")
exec $(printf '%q' "$tma")
EOF
chmod +x "$interactive_wrapper"

TMA_FAKE_FZF_MODE=select TMA_FAKE_FZF_SELECTION=j3w1zsh-smoke \
  timeout 20 script -qefc "$interactive_wrapper" /dev/null >/dev/null
grep -qx 'attach =j3w1zsh-smoke' "$TMA_FAKE_LOG"
TMA_FAKE_FZF_MODE=select TMA_FAKE_FZF_SELECTION=second.attached \
  timeout 20 script -qefc "$interactive_wrapper" /dev/null >/dev/null
grep -Fqx "attach $fake_dotted_target" "$TMA_FAKE_LOG"

log_lines_before="$(wc -l <"$TMA_FAKE_LOG")"
TMA_FAKE_FZF_MODE=cancel TMA_FAKE_FZF_SELECTION=j3w1zsh-smoke \
  timeout 20 script -qefc "$interactive_wrapper" /dev/null >/dev/null
[[ $(wc -l <"$TMA_FAKE_LOG") == "$log_lines_before" ]]

TMA_FAKE_FZF_MODE=kill TMA_FAKE_FZF_SELECTION=second.attached \
  timeout 20 script -qefc "$interactive_wrapper" /dev/null >/dev/null
grep -Fqx "kill $fake_dotted_target" "$TMA_FAKE_LOG"
if awk -F '\t' '$1 == "second.attached" { found=1 } END { exit !found }' "$TMA_FAKE_STATE"; then
  printf 'Ctrl-X did not kill the exact selected session.\n' >&2
  exit 1
fi

kill_count_before="$(grep -c '^kill ' "$TMA_FAKE_LOG")"
printf 'n' | PATH="$test_root/bin:$PATH" "$tma" --kill ops_session >/dev/null
awk -F '\t' '$1 == "ops_session" { found=1 } END { exit !found }' "$TMA_FAKE_STATE"
if [[ $(grep -c '^kill ' "$TMA_FAKE_LOG") != "$kill_count_before" ]]; then
  printf 'Declined kill changed the tmux fixture.\n' >&2
  exit 1
fi

printf 'y' | PATH="$test_root/bin:$PATH" "$tma" --kill ops_session >/dev/null
grep -qx 'kill =ops_session' "$TMA_FAKE_LOG"

if printf 'y' | PATH="$test_root/bin:$PATH" "$tma" --kill missing >/dev/null 2>&1; then
  printf 'tma accepted a missing exact session target.\n' >&2
  exit 1
fi

if [[ -n $real_tmux ]]; then
  real_tmux_socket="j3w1zsh-tma-test-$$"
  "$real_tmux" -f /dev/null -L "$real_tmux_socket" new-session -d -s real.one
  "$real_tmux" -L "$real_tmux_socket" new-session -d -s real-two
  real_bin="$test_root/real-bin"
  mkdir -p "$real_bin"
  cat >"$real_bin/tmux" <<EOF
#!/usr/bin/env bash
exec $(printf '%q' "$real_tmux") -L $(printf '%q' "$real_tmux_socket") "\$@"
EOF
  chmod +x "$real_bin/tmux"
  real_rows="$(PATH="$real_bin:$PATH" "$tma" --list)"
  [[ $(grep -o $'\t' <<<"$real_rows" | wc -l) == 6 ]]
  if grep -Fq '\t' <<<"$real_rows"; then
    printf 'Real tmux serialized literal backslash-t characters.\n' >&2
    exit 1
  fi
  grep -q $'^real.one\t1 window(s)\tdetached\tcreated ' <<<"$real_rows"
  grep -q $'^real-two\t1 window(s)\tdetached\tcreated ' <<<"$real_rows"
  printf 'n' | PATH="$real_bin:$PATH" "$tma" --kill real.one >/dev/null
  real_names="$("$real_tmux" -L "$real_tmux_socket" list-sessions -F '#{session_name}')"
  grep -Fxq 'real.one' <<<"$real_names"
  printf 'y' | PATH="$real_bin:$PATH" "$tma" --kill real.one >/dev/null
  real_names="$("$real_tmux" -L "$real_tmux_socket" list-sessions -F '#{session_name}')"
  if grep -Fxq 'real.one' <<<"$real_names"; then
    printf 'tma did not kill the exact dotted real-tmux session.\n' >&2
    exit 1
  fi
  "$real_tmux" -L "$real_tmux_socket" has-session -t '=real-two'
fi

printf 'tma real-tab serialization, picker parsing, cancellation, multi-client attach, and exact confirmed-kill tests passed.\n'
