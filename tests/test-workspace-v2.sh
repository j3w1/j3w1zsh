#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
test_root="$(mktemp -d)"
trap 'rm -rf -- "$test_root"' EXIT

project="$test_root/project"
home="$test_root/home"
fake_bin="$test_root/fake-bin"
mkdir -p "$project/config" "$home" "$fake_bin"
printf '24.0.0\n' >"$project/.node-version"
printf '%s\n' '{"packageManager":"pnpm@11.0.0","scripts":{"dev":"node dev"}}' >"$project/package.json"
printf 'managed workspace bytes\n' >"$project/config/example.conf"
printf '// tracked setup entrypoint\n' >"$project/setup"
printf '// tracked verification entrypoint\n' >"$project/verify"
printf '// tracked development entrypoint\n' >"$project/dev"

profile="$project/j3w1zsh.workspace.json"
jq -n '{
  "$schema":"https://github.com/j3w1/j3w1zsh/blob/main/schemas/workspace-profile-v2.schema.json",
  schema_version:2,
  workspace:{id:"test-project",display_name:"Test project",minimum_j3w1zsh_version:"1.0.0",review_state:"approved"},
  targets:{
    wsl:{
      packages:{pacman:[],npm_global:[],pip_user:[]},
      runtime_requirements:[{adapter:"node",source:".node-version",requirement:"24.0.0"}],
      requirements:{binaries:["node"],extensions:[]},
      managed_files:[{adapter:"home-file",source:"config/example.conf",destination:".config/example/config.conf"}],
      environment_guard:{app_env:"local",app_url_scope:"loopback",db_connection:"none",sqlite_backup:false},
      lifecycle:{setup:[{argv:["node","setup","$(touch should-not-exist)"]}],verify:[{argv:["node","verify"]}],development:{argv:["node","dev"]}},
      ports:[{host:"127.0.0.1",port:8080,purpose:"development"}],
      capabilities:{j3w1zsh_base:true}
    },
    termux:{
      packages:{pkg:[],npm_global:[],pip_user:[]},
      runtime_requirements:[{adapter:"node",source:".node-version",requirement:"24.0.0"}],
      requirements:{binaries:["node"],extensions:[]},
      managed_files:[{adapter:"home-file",source:"config/example.conf",destination:".config/example/config.conf"}],
      environment_guard:{app_env:"local",app_url_scope:"loopback",db_connection:"none",sqlite_backup:false},
      lifecycle:{setup:[{argv:["node","setup"]}],verify:[{argv:["node","verify"]}],development:{argv:["node","dev"]}},
      ports:[{host:"localhost",port:8080,purpose:"development"}],
      capabilities:{j3w1zsh_base:true,remote_host:"optional"}
    }
  }
}' >"$profile"

git -C "$project" init -q -b main
git -C "$project" config user.name 'Workspace Tests'
git -C "$project" config user.email 'tests@example.invalid'
git -C "$project" add .
git -C "$project" commit -q -m 'fixture: approved workspace v2'

command_log="$test_root/commands.log"
cat >"$fake_bin/node" <<'EOF'
#!/usr/bin/env bash
if [[ ${1:-} == --version ]]; then
  printf 'v24.0.0\n'
  exit 0
fi
printf '<%s>' "$@" >>"$J3W1ZSH_TEST_COMMAND_LOG"
printf '\n' >>"$J3W1ZSH_TEST_COMMAND_LOG"
if [[ ${J3W1ZSH_TEST_FAIL_SETUP:-0} == 1 && ${1:-} == setup ]]; then
  exit 42
fi
EOF
chmod +x "$fake_bin/node"

run_wsl() {
  env \
    HOME="$home" \
    XDG_STATE_HOME="$home/.local/state" \
    XDG_CONFIG_HOME="$home/.config" \
    XDG_CACHE_HOME="$home/.cache" \
    PATH="$fake_bin:$PATH" \
    J3W1ZSH_TEST_MODE=1 \
    J3W1ZSH_TEST_PLATFORM=wsl \
    J3W1ZSH_TEST_COMMAND_LOG="$command_log" \
    "$repo_root/bin/j3w1zsh" "$@"
}

validate_output="$(run_wsl workspace validate "$profile")"
grep -q 'structurally valid (approved)' <<<"$validate_output"
plan_json="$(run_wsl workspace plan "$profile" --json)"
jq -e '.status == "ok" and .data.review_state == "approved" and (.data.actions | map(.kind) | index("direct-argv-lifecycle"))' <<<"$plan_json" >/dev/null

dry_state="$test_root/dry-state"
dry_output="$(
  env HOME="$home" XDG_STATE_HOME="$dry_state" XDG_CONFIG_HOME="$home/.config" XDG_CACHE_HOME="$home/.cache" \
    PATH="$fake_bin:$PATH" J3W1ZSH_TEST_MODE=1 J3W1ZSH_TEST_PLATFORM=wsl J3W1ZSH_TEST_COMMAND_LOG="$command_log" \
    "$repo_root/bin/j3w1zsh" workspace apply "$profile" --dry-run --json
)"
jq -e '.command == "workspace-apply" and .data.dry_run == true and (.data.actions | length > 0)' <<<"$dry_output" >/dev/null
[[ ! -e $dry_state ]]
untracked_approved="$test_root/untracked-approved.json"
cp -- "$profile" "$untracked_approved"
if run_wsl workspace apply "$untracked_approved" --dry-run >/dev/null 2>&1; then
  printf 'Approved but untracked workspace unexpectedly passed apply dry-run.\n' >&2
  exit 1
fi

printf '// uncommitted lifecycle bytes\n' >>"$project/setup"
if run_wsl workspace apply "$profile" --dry-run >/dev/null 2>&1; then
  printf 'Approved workspace accepted a dirty lifecycle indirection file.\n' >&2
  exit 1
fi
git -C "$project" restore -- setup
mv -- "$project/setup" "$project/setup.tracked"
ln -s setup.tracked "$project/setup"
if run_wsl workspace apply "$profile" --dry-run >/dev/null 2>&1; then
  printf 'Approved workspace accepted a symlinked lifecycle indirection file.\n' >&2
  exit 1
fi
rm -- "$project/setup"
mv -- "$project/setup.tracked" "$project/setup"

run_wsl workspace apply "$profile" --yes >/dev/null
[[ -f $home/.config/example/config.conf ]]
cmp -s "$project/config/example.conf" "$home/.config/example/config.conf"
[[ ! -e $project/should-not-exist ]]
# The assertion below intentionally checks a literal shell expression.
# shellcheck disable=SC2016
grep -Fq '<setup><$(touch should-not-exist)>' "$command_log"
grep -Fq '<verify>' "$command_log"

# A managed destination symlink is backed up and replaced without following it.
outside_file="$test_root/outside-managed-file"
printf 'outside sentinel\n' >"$outside_file"
rm -- "$home/.config/example/config.conf"
ln -s "$outside_file" "$home/.config/example/config.conf"
run_wsl workspace apply "$profile" --yes --force >/dev/null
[[ -f $home/.config/example/config.conf && ! -L $home/.config/example/config.conf ]]
cmp -s "$project/config/example.conf" "$home/.config/example/config.conf"
grep -q '^outside sentinel$' "$outside_file"

digest="$(sha256sum "$profile" | awk '{print $1}')"
generation="$home/.local/state/j3w1zsh/workspaces/test-project/$digest/wsl"
[[ ! -e $generation/phases/workspace-packages.json ]]
for phase in workspace-managed-files workspace-setup workspace-verify; do
  [[ -f $generation/phases/$phase.json ]]
  jq -e --arg commit "$(git -C "$project" rev-parse HEAD)" '.project_commit == $commit' "$generation/phases/$phase.json" >/dev/null
done
[[ -f $generation/trust.json ]]
[[ $(stat -c %a "$generation/trust.json") == 600 ]]
status_json="$(run_wsl workspace status --json)"
jq -e '
  .data.workspace_id == "test-project" and
  (.data.phases[] | select(.phase == "workspace-packages") | .state) == "unselected" and
  ([.data.phases[] | select(.phase != "workspace-packages") | .state] | all(. == "complete"))
' <<<"$status_json" >/dev/null
run_wsl workspace resume --yes >/dev/null
active_record="$home/.local/state/j3w1zsh/workspaces/active.json"
mv -- "$active_record" "$active_record.saved"
ln -s "$profile" "$active_record"
if run_wsl workspace status --json >/dev/null 2>&1 || run_wsl workspace resume --yes >/dev/null 2>&1; then
  printf 'Workspace status or resume followed a symlinked active-state record.\n' >&2
  exit 1
fi
rm -- "$active_record"
mv -- "$active_record.saved" "$active_record"

# A changed committed manifest creates a new platform-keyed generation and preserves failed state.
jq '.workspace.display_name="Changed test project"' "$profile" >"$profile.next"
mv -- "$profile.next" "$profile"
git -C "$project" add "$profile"
git -C "$project" commit -q -m 'test: new manifest generation'
new_digest="$(sha256sum "$profile" | awk '{print $1}')"
if J3W1ZSH_TEST_FAIL_SETUP=1 run_wsl workspace apply "$profile" --yes >/dev/null 2>&1; then
  printf 'Failed lifecycle command unexpectedly marked the workspace complete.\n' >&2
  exit 1
fi
new_generation="$home/.local/state/j3w1zsh/workspaces/test-project/$new_digest/wsl"
[[ -f $new_generation/phases/workspace-managed-files.json ]]
[[ ! -e $new_generation/phases/workspace-setup.json ]]
run_wsl workspace apply "$profile" --yes >/dev/null
[[ -f $new_generation/phases/workspace-verify.json ]]

expect_rejected() {
  local label="$1" expression="$2"
  local bad="$test_root/$label.json"
  jq "$expression" "$profile" >"$bad"
  if run_wsl workspace validate "$bad" >/dev/null 2>&1; then
    printf 'Invalid workspace unexpectedly passed: %s\n' "$label" >&2
    exit 1
  fi
}
expect_rejected unknown-key '.targets.wsl.unexpected=true'
expect_rejected shell-wrapper '.targets.wsl.lifecycle.setup[0].argv=["sh","-c","touch bad"]'
expect_rejected env-wrapper '.targets.wsl.lifecycle.setup[0].argv=["env","node","setup"]'
expect_rejected executable-path '.targets.wsl.lifecycle.setup[0].argv[0]="/usr/bin/node"'
expect_rejected control-character '.targets.wsl.lifecycle.setup[0].argv[1]="bad\nargument"'
expect_rejected traversal-argument '.targets.wsl.lifecycle.setup[0].argv=["node","../outside.js"]'
expect_rejected inline-eval '.targets.wsl.lifecycle.setup[0].argv=["node","--eval","process.exit(0)"]'
expect_rejected absolute-home '.targets.wsl.managed_files[0].destination="/tmp/bad"'

env_target="$test_root/environment-target"
printf 'APP_ENV=production\n' >"$env_target"
ln -s "$env_target" "$project/.env"
if run_wsl workspace apply "$profile" --yes --force >/dev/null 2>&1; then
  printf 'Workspace apply accepted a symlinked environment guard.\n' >&2
  exit 1
fi
rm -- "$project/.env"

missing_wsl="$test_root/missing-wsl.json"
jq 'del(.targets.wsl)' "$profile" >"$missing_wsl"
run_wsl workspace validate "$missing_wsl" >/dev/null
if run_wsl workspace plan "$missing_wsl" >/dev/null 2>&1; then
  printf 'Workspace plan unexpectedly inherited an undeclared WSL target.\n' >&2
  exit 1
fi

candidate="$test_root/candidate.json"
jq '.workspace.review_state="candidate"' "$profile" >"$candidate"
run_wsl workspace validate "$candidate" >/dev/null
run_wsl workspace plan "$candidate" >/dev/null
candidate_top_plan="$(run_wsl plan "$candidate" --json)"
jq -e '.status == "ok" and .data.workspace != null and any(.data.actions[]; .source_layer == "workspace")' <<<"$candidate_top_plan" >/dev/null
candidate_state="$test_root/candidate-state"
if env HOME="$home" XDG_STATE_HOME="$candidate_state" XDG_CONFIG_HOME="$home/.config" XDG_CACHE_HOME="$home/.cache" \
  PATH="$fake_bin:$PATH" J3W1ZSH_TEST_MODE=1 J3W1ZSH_TEST_PLATFORM=wsl J3W1ZSH_TEST_COMMAND_LOG="$command_log" \
  "$repo_root/bin/j3w1zsh" workspace apply "$candidate" --yes >/dev/null 2>&1; then
  printf 'Candidate workspace unexpectedly applied.\n' >&2
  exit 1
fi
[[ ! -e $candidate_state ]]

# Termux accepts only its explicit user-level target and rejects system adapters before state.
termux_home="$test_root/termux-home"
mkdir -p "$termux_home"
run_termux() {
  env HOME="$termux_home" XDG_STATE_HOME="$termux_home/.local/state" XDG_CONFIG_HOME="$termux_home/.config" XDG_CACHE_HOME="$termux_home/.cache" \
    PATH="$fake_bin:$PATH" J3W1ZSH_TEST_MODE=1 J3W1ZSH_TEST_PLATFORM=termux J3W1ZSH_TEST_COMMAND_LOG="$command_log" \
    "$repo_root/bin/j3w1zsh" "$@"
}
run_termux workspace apply "$profile" --yes >/dev/null
[[ -f $termux_home/.config/example/config.conf ]]
bad_termux="$test_root/bad-termux.json"
jq '.targets.termux.managed_files[0].adapter="php-conf" | .targets.termux.managed_files[0].destination="/etc/php/conf.d/bad.ini"' "$profile" >"$bad_termux"
bad_termux_state="$test_root/bad-termux-state"
if env HOME="$termux_home" XDG_STATE_HOME="$bad_termux_state" XDG_CONFIG_HOME="$termux_home/.config" XDG_CACHE_HOME="$termux_home/.cache" \
  PATH="$fake_bin:$PATH" J3W1ZSH_TEST_MODE=1 J3W1ZSH_TEST_PLATFORM=termux J3W1ZSH_TEST_COMMAND_LOG="$command_log" \
  "$repo_root/bin/j3w1zsh" workspace apply "$bad_termux" --yes >/dev/null 2>&1; then
  printf 'Hostile Termux adapter unexpectedly applied.\n' >&2
  exit 1
fi
[[ ! -e $bad_termux_state ]]

# The isolated v1 converter emits a candidate and a transformation report only.
legacy="$test_root/workspace-v1.json"
jq -n '{
  "$schema":"https://example.invalid/workspace-v1.json",schema_version:1,
  profile:{id:"legacy-project",display_name:"Legacy project",minimum_bloody_writer_version:"0.3.0",review_state:"approved"},
  platform:{distribution:"arch",environment:"wsl",wsl_version:2},
  packages:{pacman:[],npm_global:[]},
  versions:{php:{source:".php-version",requirement:"8.5"},node:{source:".node-version",requirement:"24.0.0"},pnpm:{source:"package.json",requirement:"11.0.0"}},
  requirements:{binaries:[],php_extensions:[]},system_files:[],
  environment_guard:{app_env:"local",app_url_scope:"loopback",db_connection:"sqlite",sqlite_backup:true},
  lifecycle:{setup:[],verify:[],development:{argv:["node","dev"]}},ports:[],capabilities:{bloody_writer_base:true}
}' >"$legacy"
converted="$test_root/converted.json"
run_wsl workspace migrate "$legacy" --output "$converted" >/dev/null
jq -e '.schema_version == 2 and .workspace.review_state == "candidate" and (.targets | keys == ["wsl"])' "$converted" >/dev/null
jq -e '.unresolved | length > 0' "$converted.migration-report.json" >/dev/null
if run_wsl workspace migrate "$legacy" --output "$converted" >/dev/null 2>&1; then
  printf 'Workspace converter unexpectedly overwrote output.\n' >&2
  exit 1
fi
invalid_legacy="$test_root/invalid-workspace-v1.json"
jq '.unexpected="must reject"' "$legacy" >"$invalid_legacy"
if run_wsl workspace migrate "$invalid_legacy" --output "$test_root/invalid-converted.json" >/dev/null 2>&1; then
  printf 'Workspace converter accepted a schema-v1 document with an unknown key.\n' >&2
  exit 1
fi
[[ ! -e $test_root/invalid-converted.json && ! -e $test_root/invalid-converted.json.migration-report.json ]]

scan="$test_root/scanned.json"
run_wsl workspace scan --project "$project" --output "$scan" --target arch --target termux >/dev/null
jq -e '.workspace.review_state == "candidate" and (.targets | keys == ["arch","termux"])' "$scan" >/dev/null
if run_wsl workspace scan --project "$project" --output "$scan" --target wsl >/dev/null 2>&1; then
  printf 'Workspace scanner unexpectedly overwrote output.\n' >&2
  exit 1
fi

printf 'Workspace v2, platform separation, trust, lifecycle, resume, and converter tests passed.\n'
