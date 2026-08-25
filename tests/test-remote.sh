#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
test_root="$(mktemp -d)"
trap 'rm -rf -- "$test_root"' EXIT
home="$test_root/home"
fake_bin="$test_root/bin"
mkdir -p "$home" "$fake_bin"

run_termux() {
  env HOME="$home" XDG_STATE_HOME="$home/.local/state" XDG_CONFIG_HOME="$home/.config" XDG_CACHE_HOME="$home/.cache" \
    PATH="$fake_bin:$PATH" J3W1ZSH_TEST_MODE=1 J3W1ZSH_TEST_PLATFORM=termux \
    "$repo_root/bin/j3w1zsh" "$@"
}

run_termux remote configure-client --host dev.tail.example --user alice >/dev/null
settings="$home/.config/j3w1zsh/settings.zsh"
grep -qx "export J3W1ZSH_REMOTE_HOST='dev.tail.example'" "$settings"
grep -qx "export J3W1ZSH_REMOTE_USER='alice'" "$settings"
grep -qx "export J3W1ZSH_REMOTE_ATTACH_COMMAND='/home/alice/.local/bin/tma'" "$settings"
status="$(run_termux remote status --json)"
jq -e '.command=="remote-status" and .status=="ok" and .data.configured==true and .data.host=="dev.tail.example" and .data.user=="alice"' <<<"$status" >/dev/null

before="$(sha256sum "$settings")"
if run_termux remote configure-client --host 'bad;host' --user alice >/dev/null 2>&1; then
  printf 'Hostile remote host token was accepted.\n' >&2
  exit 1
fi
[[ $(sha256sum "$settings") == "$before" ]]

cat >"$fake_bin/ssh" <<'EOF'
#!/usr/bin/env bash
printf '%q ' "$@" >"$J3W1ZSH_TEST_SSH_LOG"
printf '\n' >>"$J3W1ZSH_TEST_SSH_LOG"
EOF
chmod +x "$fake_bin/ssh"
export J3W1ZSH_TEST_SSH_LOG="$test_root/ssh.log"
run_termux remote attach work >/dev/null
grep -Fqx -- '-t -- alice@dev.tail.example /home/alice/.local/bin/tma work ' "$J3W1ZSH_TEST_SSH_LOG"

if env HOME="$home" J3W1ZSH_TEST_MODE=1 J3W1ZSH_TEST_PLATFORM=termux \
  "$repo_root/bin/j3w1zsh" remote setup-host >/dev/null 2>&1; then
  printf 'Termux unexpectedly accepted remote host setup.\n' >&2
  exit 1
fi
env HOME="$home" J3W1ZSH_TEST_MODE=1 J3W1ZSH_TEST_PLATFORM=arch \
  "$repo_root/bin/j3w1zsh" remote setup-host >/dev/null
env HOME="$home" J3W1ZSH_TEST_MODE=1 J3W1ZSH_TEST_PLATFORM=wsl \
  "$repo_root/bin/j3w1zsh" remote setup-host >/dev/null

printf 'Remote host/client routing, strict settings, direct SSH argv, and platform tests passed.\n'
