#!/usr/bin/env bash

if [[ -n ${J3W1ZSH_WORKSPACE_V2_LOADED:-} ]]; then
  return 0
fi
readonly J3W1ZSH_WORKSPACE_V2_LOADED=1
readonly J3W1ZSH_WORKSPACE_MAX_BYTES=1048576
readonly J3W1ZSH_WORKSPACE_EXECUTABLES='["composer","pnpm","npm","node","php","python","python3","pytest","cargo","go","make","just","bundle"]'
readonly J3W1ZSH_WORKSPACE_PHASES=(workspace-packages workspace-managed-files workspace-setup workspace-verify)

J3W1ZSH_WORKSPACE_FILE=""
J3W1ZSH_WORKSPACE_ROOT=""
J3W1ZSH_WORKSPACE_ID=""
J3W1ZSH_WORKSPACE_DIGEST=""
J3W1ZSH_WORKSPACE_GENERATION=""
J3W1ZSH_WORKSPACE_COMMIT=""

j3w1zsh_workspace_usage() {
  cat <<'EOF'
Usage:
  j3w1zsh workspace scan --project DIR --output FILE [--target arch|wsl|termux ...]
  j3w1zsh workspace validate FILE
  j3w1zsh workspace plan FILE [--json]
  j3w1zsh workspace audit FILE [--json]
  j3w1zsh workspace apply FILE [--yes] [--dry-run] [--force]
  j3w1zsh workspace status [--json]
  j3w1zsh workspace resume [--yes] [--dry-run] [--force]
  j3w1zsh workspace migrate OLD_FILE [--output FILE] [--dry-run]

Candidate profiles validate structurally and may be planned. Only an approved,
tracked, committed-clean profile and its tracked referenced sources can be trusted
and applied to the explicitly declared current platform target.
EOF
}

j3w1zsh_workspace_semver_at_least() {
  local current="$1" required="$2"
  [[ $current =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && $required =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
  [[ $(printf '%s\n%s\n' "$required" "$current" | sort -V | tail -n1) == "$current" ]]
}

j3w1zsh_workspace_path_token() {
  local value="$1" label="$2"
  [[ -n $value && $value != /* && $value != *$'\n'* && $value != *$'\r'* ]] ||
    j3w1zsh_die "$label must be a relative path."
  case "/$value/" in
  */../* | */./*) j3w1zsh_die "$label contains traversal: $value" ;;
  esac
}

j3w1zsh_workspace_validate_commands() {
  local file="$1" platform="$2" command_json executable argument
  local argv=()
  while IFS= read -r command_json; do
    jq -e --argjson allowed "$J3W1ZSH_WORKSPACE_EXECUTABLES" '
      (.argv | type == "array" and length > 0) and
      all(.argv[]; type == "string" and length > 0 and (test("[\u0000-\u001F\u007F]") | not)) and
      (.argv[0] as $executable | ($executable | test("^[A-Za-z0-9][A-Za-z0-9._+-]*$")) and (($allowed | index($executable)) != null))
    ' <<<"$command_json" >/dev/null || j3w1zsh_die "Lifecycle entries require a supported unqualified executable and control-free direct argv."
    executable="$(jq -r '.argv[0]' <<<"$command_json")"
    mapfile -t argv < <(jq -r '.argv[]' <<<"$command_json")
    case "$executable" in
    sh | bash | zsh | dash | fish | ksh | env | sudo | doas | su | command | systemctl | service)
      j3w1zsh_die "Lifecycle executable is forbidden: $executable"
      ;;
    esac
    case "$executable:${argv[1]:-}" in
    node:-e | node:--eval | node:-p | node:--print | php:-r | python:-c | python3:-c)
      j3w1zsh_die "Inline interpreter evaluation is forbidden in workspace lifecycle: $executable ${argv[1]}"
      ;;
    esac
    for argument in "${argv[@]:1}"; do
      case "/$argument/" in
      */../*) j3w1zsh_die "Lifecycle arguments cannot contain path traversal: $argument" ;;
      esac
      case "\\$argument\\" in
      *\\..\\*) j3w1zsh_die "Lifecycle arguments cannot contain path traversal: $argument" ;;
      esac
      case "$argument" in
      /* | \~ | \~/* | *=/* | *=\~ | *=\~/*)
        j3w1zsh_die "Lifecycle arguments cannot name an absolute or home-relative path: $argument"
        ;;
      esac
    done
    if [[ $platform == termux ]] && jq -e '[.argv[] | select(. == "sudo" or . == "doas" or . == "su" or . == "systemctl" or . == "service")] | length > 0' <<<"$command_json" >/dev/null; then
      j3w1zsh_die "Termux lifecycle cannot invoke privilege or system-service tokens."
    fi
  done < <(jq -c --arg platform "$platform" '.targets[$platform].lifecycle | .setup[],.verify[],.development' "$file")
}

j3w1zsh_workspace_check_exact_keys() {
  local file="$1"
  jq -e '
    def exact($allowed): ((keys - $allowed) | length) == 0 and (($allowed - keys) | length) == 0;
    exact(["$schema","schema_version","targets","workspace"]) and
    (.workspace | exact(["display_name","id","minimum_j3w1zsh_version","review_state"])) and
    (.targets | type == "object" and length >= 1 and all(keys[]; . == "arch" or . == "wsl" or . == "termux")) and
    all(.targets[];
      exact(["capabilities","environment_guard","lifecycle","managed_files","packages","ports","requirements","runtime_requirements"]) and
      (.requirements | exact(["binaries","extensions"])) and
      (.environment_guard | exact(["app_env","app_url_scope","db_connection","sqlite_backup"])) and
      (.lifecycle | exact(["development","setup","verify"])) and
      ([.lifecycle.setup[],.lifecycle.verify[],.lifecycle.development] | all(exact(["argv"]))) and
      ([.runtime_requirements[]] | all(exact(["adapter","requirement","source"]))) and
      ([.managed_files[]] | all(exact(["adapter","destination","source"]))) and
      ([.ports[]] | all(exact(["host","port","purpose"])))
    )
  ' "$file" >/dev/null || j3w1zsh_die "Workspace profile contains missing or unknown keys."
}

j3w1zsh_workspace_validate_target() {
  local file="$1" platform="$2"
  jq -e --arg platform "$platform" '
    .targets[$platform] as $target |
    ($target | type == "object") and
    ($target.runtime_requirements | type == "array" and all(.[];
      (.adapter == "php" or .adapter == "node" or .adapter == "pnpm") and
      (.source | type == "string" and length > 0) and
      (.requirement | type == "string" and length > 0))) and
    ($target.requirements.binaries | type == "array" and length == (unique | length) and all(.[]; type == "string" and test("^[A-Za-z0-9@._+:-]+$"))) and
    ($target.requirements.extensions | type == "array" and length == (unique | length) and all(.[]; type == "string" and test("^[A-Za-z0-9@._+:-]+$"))) and
    ($target.managed_files | type == "array" and all(.[];
      (.adapter == "home-file" or .adapter == "php-conf") and
      (.source | type == "string" and length > 0) and
      (.destination | type == "string" and length > 0))) and
    ($target.environment_guard.app_env == "local") and
    ($target.environment_guard.app_url_scope == "loopback") and
    ($target.environment_guard.db_connection == "sqlite" or $target.environment_guard.db_connection == "none") and
    ($target.environment_guard.sqlite_backup | type == "boolean") and
    ($target.lifecycle.setup | type == "array") and
    ($target.lifecycle.verify | type == "array") and
    ($target.lifecycle.development.argv | type == "array" and length > 0) and
    ($target.ports | type == "array" and all(.[];
      (.host == "127.0.0.1" or .host == "localhost" or .host == "::1") and
      (.port | type == "number" and . >= 1 and . <= 65535) and
      (.purpose | type == "string" and length > 0))) and
    ($target.capabilities.j3w1zsh_base == true)
  ' "$file" >/dev/null || j3w1zsh_die "Workspace target has invalid values: $platform"

  if [[ $platform == termux ]]; then
    jq -e '.targets.termux.packages | (keys | sort) == ["npm_global","pip_user","pkg"]' "$file" >/dev/null ||
      j3w1zsh_die "Termux target permits only pkg, npm_global, and pip_user package arrays."
    jq -e '.targets.termux.capabilities | (keys | sort) == ["j3w1zsh_base","remote_host"] and (.remote_host == "none" or .remote_host == "optional" or .remote_host == "required")' "$file" >/dev/null ||
      j3w1zsh_die "Termux target requires bounded remote_host capability metadata."
    jq -e 'all(.targets.termux.managed_files[]; .adapter == "home-file" and (.destination | startswith("/") | not))' "$file" >/dev/null ||
      j3w1zsh_die "Termux managed files must use home-file with relative destinations."
  else
    jq -e --arg platform "$platform" '.targets[$platform].packages | (keys | sort) == ["npm_global","pacman","pip_user"]' "$file" >/dev/null ||
      j3w1zsh_die "$platform target permits only pacman, npm_global, and pip_user package arrays."
    jq -e --arg platform "$platform" '.targets[$platform].capabilities | keys == ["j3w1zsh_base"]' "$file" >/dev/null ||
      j3w1zsh_die "$platform target has unknown capabilities."
    jq -e --arg platform "$platform" 'all(.targets[$platform].managed_files[];
      if .adapter == "php-conf" then (.destination | test("^/etc/php/conf\\.d/[A-Za-z0-9._-]+\\.ini$"))
      else (.destination | startswith("/") | not) end)' "$file" >/dev/null ||
      j3w1zsh_die "$platform target contains an unsupported managed destination."
  fi

  jq -e --arg platform "$platform" 'all(.targets[$platform].packages[]; type == "array" and length == (unique | length) and all(.[]; type == "string" and test("^[A-Za-z0-9@._+:-]+$")))' "$file" >/dev/null ||
    j3w1zsh_die "$platform package arrays contain invalid or duplicate names."
  j3w1zsh_workspace_validate_commands "$file" "$platform"
}

j3w1zsh_workspace_validate_structural() {
  local requested="$1"
  [[ -n $requested ]] || j3w1zsh_die "A workspace profile path is required."
  [[ -f $requested && ! -L $requested ]] || j3w1zsh_die "Workspace profile must be a regular non-symlink file: $requested"
  local size
  size="$(wc -c <"$requested")"
  ((size <= J3W1ZSH_WORKSPACE_MAX_BYTES)) || j3w1zsh_die "Workspace profile exceeds $J3W1ZSH_WORKSPACE_MAX_BYTES bytes."
  jq -e 'type == "object"' "$requested" >/dev/null 2>&1 || j3w1zsh_die "Workspace profile is malformed JSON."
  j3w1zsh_workspace_check_exact_keys "$requested"
  jq -e '
    .schema_version == 2 and
    (."$schema" | type == "string" and length > 0) and
    (.workspace.id | test("^[a-z0-9][a-z0-9-]{1,62}$")) and
    (.workspace.display_name | type == "string" and length > 0 and length <= 120) and
    (.workspace.minimum_j3w1zsh_version | test("^[0-9]+\\.[0-9]+\\.[0-9]+$")) and
    (.workspace.review_state == "candidate" or .workspace.review_state == "approved")
  ' "$requested" >/dev/null || j3w1zsh_die "Workspace profile v2 has invalid top-level values."
  local platform
  while IFS= read -r platform; do
    j3w1zsh_workspace_validate_target "$requested" "$platform"
  done < <(jq -r '.targets | keys[]' "$requested")
  local minimum
  minimum="$(jq -r '.workspace.minimum_j3w1zsh_version' "$requested")"
  j3w1zsh_workspace_semver_at_least "$J3W1ZSH_VERSION" "$minimum" ||
    j3w1zsh_die "Workspace requires j3w1zsh $minimum or newer; current version is $J3W1ZSH_VERSION."
}

j3w1zsh_workspace_require_platform_target() {
  local file="$1"
  [[ $J3W1ZSH_PLATFORM =~ ^(arch|wsl|termux)$ ]] || j3w1zsh_die "Workspace operations require a supported platform."
  jq -e --arg platform "$J3W1ZSH_PLATFORM" '.targets | has($platform)' "$file" >/dev/null ||
    j3w1zsh_die "Workspace does not declare an explicit $J3W1ZSH_PLATFORM target."
}

j3w1zsh_workspace_require_tracked_source() {
  local root="$1" source="$2" label="$3"
  j3w1zsh_workspace_path_token "$source" "$label"
  [[ -f $root/$source && ! -L $root/$source ]] || j3w1zsh_die "$label must reference a regular non-symlink project file: $source"
  local resolved
  resolved="$(readlink -f -- "$root/$source")"
  case "$resolved" in "$root"/*) ;; *) j3w1zsh_die "$label escapes the project: $source" ;; esac
  git -C "$root" ls-files --error-unmatch -- "$source" >/dev/null 2>&1 || j3w1zsh_die "$label must be tracked: $source"
  git -C "$root" diff --quiet HEAD -- "$source" || j3w1zsh_die "$label has uncommitted bytes: $source"
  git -C "$root" diff --cached --quiet HEAD -- "$source" || j3w1zsh_die "$label has staged bytes: $source"
}

j3w1zsh_workspace_require_lifecycle_sources() {
  local root="$1" file="$2" command_json executable source argument
  local argv=()
  while IFS= read -r command_json; do
    mapfile -t argv < <(jq -r '.argv[]' <<<"$command_json")
    executable="${argv[0]}"
    source=""
    case "$executable" in
    composer) source=composer.json ;;
    npm | pnpm) source=package.json ;;
    make) source=Makefile ;;
    just) source=justfile ;;
    bundle) source=Gemfile ;;
    cargo) source=Cargo.toml ;;
    go) source=go.mod ;;
    node | php | python | python3)
      if [[ -n ${argv[1]:-} && ${argv[1]} != -* ]]; then
        source="${argv[1]}"
      fi
      ;;
    esac
    [[ -z $source ]] || j3w1zsh_workspace_require_tracked_source "$root" "$source" "$executable lifecycle source"
    for argument in "${argv[@]:1}"; do
      if [[ -e $root/$argument || -L $root/$argument ]]; then
        j3w1zsh_workspace_require_tracked_source "$root" "$argument" "$executable lifecycle path"
      fi
    done
  done < <(jq -c --arg platform "$J3W1ZSH_PLATFORM" '.targets[$platform].lifecycle | .setup[],.verify[],.development' "$file")
}

j3w1zsh_workspace_bind() {
  local requested="$1" require_tracked="${2:-0}"
  j3w1zsh_workspace_validate_structural "$requested"
  j3w1zsh_workspace_require_platform_target "$requested"
  requested="$(readlink -f -- "$requested")"
  local root="" relative="" commit=untracked
  root="$(git -C "$(dirname -- "$requested")" rev-parse --show-toplevel 2>/dev/null || true)"
  if [[ $require_tracked == 1 ]]; then
    [[ -n $root ]] || j3w1zsh_die "Approved apply requires a Git-tracked workspace profile."
    root="$(readlink -f -- "$root")"
    case "$requested" in "$root"/*) ;; *) j3w1zsh_die "Workspace profile resolves outside its Git project." ;; esac
    relative="${requested#"$root"/}"
    git -C "$root" ls-files --error-unmatch -- "$relative" >/dev/null 2>&1 || j3w1zsh_die "Workspace profile must be tracked by Git: $relative"
    git -C "$root" diff --quiet HEAD -- "$relative" || j3w1zsh_die "Workspace profile has uncommitted bytes."
    git -C "$root" diff --cached --quiet HEAD -- "$relative" || j3w1zsh_die "Workspace profile has staged bytes."
    commit="$(git -C "$root" rev-parse HEAD)"
    local source adapter requirement derived
    while IFS=$'\t' read -r source adapter requirement; do
      j3w1zsh_workspace_require_tracked_source "$root" "$source" "runtime requirement source"
      case "$adapter" in
      php | node) derived="$(tr -d '[:space:]' <"$root/$source")" ;;
      pnpm) derived="$(jq -r '.packageManager // "" | sub("^pnpm@";"")' "$root/$source")" ;;
      *) j3w1zsh_die "Unsupported runtime adapter: $adapter" ;;
      esac
      [[ $derived == "$requirement" ]] || j3w1zsh_die "$adapter requirement does not match tracked source $source."
    done < <(jq -r --arg platform "$J3W1ZSH_PLATFORM" '.targets[$platform].runtime_requirements[] | [.source,.adapter,.requirement] | @tsv' "$requested")
    while IFS= read -r source; do
      j3w1zsh_workspace_require_tracked_source "$root" "$source" "managed-file source"
    done < <(jq -r --arg platform "$J3W1ZSH_PLATFORM" '.targets[$platform].managed_files[].source' "$requested")
    j3w1zsh_workspace_require_lifecycle_sources "$root" "$requested"
  else
    [[ -n $root ]] || root="$(dirname -- "$requested")"
    root="$(readlink -f -- "$root")"
  fi

  J3W1ZSH_WORKSPACE_FILE="$requested"
  J3W1ZSH_WORKSPACE_ROOT="$root"
  J3W1ZSH_WORKSPACE_ID="$(jq -r '.workspace.id' "$requested")"
  J3W1ZSH_WORKSPACE_DIGEST="$(sha256sum "$requested" | awk '{print $1}')"
  J3W1ZSH_WORKSPACE_GENERATION="$J3W1ZSH_STATE_DIR/workspaces/$J3W1ZSH_WORKSPACE_ID/$J3W1ZSH_WORKSPACE_DIGEST/$J3W1ZSH_PLATFORM"
  J3W1ZSH_WORKSPACE_COMMIT="$commit"
  export J3W1ZSH_WORKSPACE_FILE J3W1ZSH_WORKSPACE_ROOT J3W1ZSH_WORKSPACE_ID
  export J3W1ZSH_WORKSPACE_DIGEST J3W1ZSH_WORKSPACE_GENERATION J3W1ZSH_WORKSPACE_COMMIT
}

j3w1zsh_workspace_plan_json() {
  local file="$1"
  local resolved_file
  [[ -f $file && ! -L $file ]] || j3w1zsh_die "Workspace profile must be a regular non-symlink file: $file"
  resolved_file="$(readlink -f -- "$file")"
  if [[ ${J3W1ZSH_WORKSPACE_FILE:-} != "$resolved_file" ]]; then
    j3w1zsh_workspace_bind "$resolved_file" 0
  fi
  local platform="$J3W1ZSH_PLATFORM" actions='[]' manager package_count item
  manager="$(j3w1zsh_package_manager_for_platform)"
  for manager in "$manager" npm_global pip_user; do
    package_count="$(jq --arg platform "$platform" --arg manager "$manager" '.targets[$platform].packages[$manager] | length' "$file")"
    ((package_count == 0)) || actions="$(jq -cn --argjson actions "$actions" --arg id "workspace-$manager" --arg platform "$platform" --arg manager "$manager" --arg reason "reconcile $package_count workspace-declared packages" '$actions + [{id:$id,phase:"workspace-packages",kind:"package-operation",platform:$platform,source_layer:"workspace",package_manager:$manager,managed_destination:null,reason:$reason,requires_privilege:($manager=="pacman"),requires_confirmation:true,user_owned_checkpoint:null,mutation:true,verification_rule:"named workspace packages are installed"}]')"
  done
  while IFS= read -r item; do
    actions="$(jq -cn --argjson actions "$actions" --argjson item "$item" --arg platform "$platform" '$actions + [{id:("managed-file-" + (($actions|length)|tostring)),phase:"workspace-managed-files",kind:"file-reconciliation",platform:$platform,source_layer:"workspace",package_manager:null,managed_destination:$item.destination,reason:("reconcile " + $item.adapter + " from tracked " + $item.source),requires_privilege:($item.adapter=="php-conf"),requires_confirmation:false,user_owned_checkpoint:null,mutation:true,verification_rule:"destination bytes match the tracked source"}]')"
  done < <(jq -c --arg platform "$platform" '.targets[$platform].managed_files[]' "$file")
  while IFS= read -r item; do
    actions="$(jq -cn --argjson actions "$actions" --argjson item "$item" --arg platform "$platform" '$actions + [{id:("setup-" + (($actions|length)|tostring)),phase:"workspace-setup",kind:"direct-argv-lifecycle",platform:$platform,source_layer:"workspace",package_manager:null,managed_destination:null,reason:("run approved direct argv: " + ($item.argv|join(" "))),requires_privilege:false,requires_confirmation:true,user_owned_checkpoint:null,mutation:true,verification_rule:"direct argv exits zero"}]')"
  done < <(jq -c --arg platform "$platform" '.targets[$platform].lifecycle.setup[]' "$file")
  actions="$(jq -cn --argjson actions "$actions" --arg platform "$platform" '$actions + [{id:"workspace-verify",phase:"workspace-verify",kind:"verification",platform:$platform,source_layer:"workspace",package_manager:null,managed_destination:null,reason:"verify declared binaries, runtimes, files, guards, and direct argv",requires_privilege:false,requires_confirmation:false,user_owned_checkpoint:null,mutation:false,verification_rule:"all selected workspace requirements pass"}]')"
  printf '%s\n' "$actions"
}

j3w1zsh_workspace_phase_marker() {
  printf '%s/phases/%s.json\n' "$J3W1ZSH_WORKSPACE_GENERATION" "$1"
}

j3w1zsh_workspace_phase_done() {
  local marker
  marker="$(j3w1zsh_workspace_phase_marker "$1")"
  [[ -f $marker ]] || return 1
  jq -e --arg phase "$1" --arg digest "$J3W1ZSH_WORKSPACE_DIGEST" --arg platform "$J3W1ZSH_PLATFORM" \
    '.schema_version == 1 and .phase == $phase and .manifest_sha256 == $digest and .platform == $platform' "$marker" >/dev/null 2>&1
}

j3w1zsh_workspace_mark_phase() {
  local phase="$1" marker temporary
  [[ $J3W1ZSH_DRY_RUN == 1 ]] && return 0
  marker="$(j3w1zsh_workspace_phase_marker "$phase")"
  mkdir -p "$(dirname -- "$marker")"
  temporary="$(mktemp "$J3W1ZSH_WORKSPACE_GENERATION/phases/.${phase}.XXXXXX")"
  jq -cn --argjson schema_version 1 --arg phase "$phase" --arg platform "$J3W1ZSH_PLATFORM" \
    --arg manifest_sha256 "$J3W1ZSH_WORKSPACE_DIGEST" --arg project_commit "$J3W1ZSH_WORKSPACE_COMMIT" \
    --arg completed_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{schema_version:$schema_version,phase:$phase,platform:$platform,manifest_sha256:$manifest_sha256,project_commit:$project_commit,completed_at:$completed_at}' >"$temporary"
  chmod 600 "$temporary"
  mv -- "$temporary" "$marker"
}

j3w1zsh_workspace_write_active() {
  [[ $J3W1ZSH_DRY_RUN == 1 ]] && return 0
  local active="$J3W1ZSH_STATE_DIR/workspaces/active.json" temporary
  mkdir -p "$(dirname -- "$active")"
  temporary="$(mktemp "$J3W1ZSH_STATE_DIR/workspaces/.active.XXXXXX")"
  jq -cn --arg id "$J3W1ZSH_WORKSPACE_ID" --arg manifest "$J3W1ZSH_WORKSPACE_FILE" \
    --arg manifest_sha256 "$J3W1ZSH_WORKSPACE_DIGEST" --arg platform "$J3W1ZSH_PLATFORM" \
    '{schema_version:1,workspace_id:$id,manifest:$manifest,manifest_sha256:$manifest_sha256,platform:$platform}' >"$temporary"
  chmod 600 "$temporary"
  mv -- "$temporary" "$active"
}

j3w1zsh_workspace_validate_active_record() {
  local active="$J3W1ZSH_STATE_DIR/workspaces/active.json"
  [[ -e $active || -L $active ]] || return 3
  [[ -f $active && ! -L $active ]] || j3w1zsh_die "Active workspace state must be a regular non-symlink file."
  jq -e '
    type == "object" and
    (keys | sort) == ["manifest","manifest_sha256","platform","schema_version","workspace_id"] and
    .schema_version == 1 and
    (.workspace_id | type == "string" and test("^[a-z0-9][a-z0-9-]{1,62}$")) and
    (.manifest | type == "string" and length > 0) and
    (.manifest_sha256 | type == "string" and test("^[0-9a-f]{64}$")) and
    (.platform == "arch" or .platform == "wsl" or .platform == "termux")
  ' "$active" >/dev/null 2>&1 || j3w1zsh_die "Active workspace state is malformed or contains unknown fields."
}

j3w1zsh_workspace_write_trust() {
  [[ $J3W1ZSH_DRY_RUN == 1 ]] && return 0
  mkdir -p "$J3W1ZSH_WORKSPACE_GENERATION"
  local trust="$J3W1ZSH_WORKSPACE_GENERATION/trust.json" temporary
  temporary="$(mktemp "$J3W1ZSH_WORKSPACE_GENERATION/.trust.XXXXXX")"
  jq -cn --argjson schema_version 1 --arg manifest "$J3W1ZSH_WORKSPACE_FILE" \
    --arg manifest_sha256 "$J3W1ZSH_WORKSPACE_DIGEST" --arg platform "$J3W1ZSH_PLATFORM" \
    --arg project_commit "$J3W1ZSH_WORKSPACE_COMMIT" --arg trusted_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{schema_version:$schema_version,manifest:$manifest,manifest_sha256:$manifest_sha256,platform:$platform,project_commit:$project_commit,trusted_at:$trusted_at}' >"$temporary"
  chmod 600 "$temporary"
  mv -- "$temporary" "$trust"
}

j3w1zsh_workspace_read_env_value() {
  local file="$1" key="$2"
  awk -v wanted="$key" '
    /^[[:space:]]*#/ { next }
    index($0, "=") == 0 { next }
    {
      name=substr($0,1,index($0,"=")-1)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", name)
      if (name != wanted) next
      value=substr($0,index($0,"=")+1)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      if ((substr(value,1,1) == "\"" && substr(value,length(value),1) == "\"") ||
          (substr(value,1,1) == "\047" && substr(value,length(value),1) == "\047")) {
        value=substr(value,2,length(value)-2)
      }
      print value
      exit
    }
  ' "$file"
}

j3w1zsh_workspace_guard_environment() {
  local guard env_file="$J3W1ZSH_WORKSPACE_ROOT/.env"
  guard="$(jq -c --arg platform "$J3W1ZSH_PLATFORM" '.targets[$platform].environment_guard' "$J3W1ZSH_WORKSPACE_FILE")"
  [[ -f $env_file && ! -L $env_file ]] || return 0
  local app_env app_url db_connection
  app_env="$(j3w1zsh_workspace_read_env_value "$env_file" APP_ENV)"
  app_url="$(j3w1zsh_workspace_read_env_value "$env_file" APP_URL)"
  db_connection="$(j3w1zsh_workspace_read_env_value "$env_file" DB_CONNECTION)"
  [[ -z $app_env || $app_env == local ]] || j3w1zsh_die "Workspace .env APP_ENV must be local."
  if [[ -n $app_url ]]; then
    [[ $app_url =~ ^https?://(127\.0\.0\.1|localhost|\[::1\])(:[0-9]+)?(/|$) ]] ||
      j3w1zsh_die "Workspace .env APP_URL must use a loopback host."
  fi
  case "$(jq -r .db_connection <<<"$guard")" in
  sqlite) [[ -z $db_connection || $db_connection == sqlite ]] || j3w1zsh_die "Workspace .env DB_CONNECTION must be sqlite." ;;
  none) [[ -z $db_connection ]] || j3w1zsh_die "Workspace does not permit a database connection." ;;
  esac
}

j3w1zsh_workspace_validate_local_inputs() {
  local env_file="$J3W1ZSH_WORKSPACE_ROOT/.env"
  [[ ! -e $env_file && ! -L $env_file ]] ||
    [[ -f $env_file && ! -L $env_file ]] || j3w1zsh_die "Workspace .env must be a regular non-symlink file."
  j3w1zsh_workspace_guard_environment
  if jq -e --arg platform "$J3W1ZSH_PLATFORM" '.targets[$platform].environment_guard.sqlite_backup == true' "$J3W1ZSH_WORKSPACE_FILE" >/dev/null; then
    local sqlite="$J3W1ZSH_WORKSPACE_ROOT/database/database.sqlite"
    [[ ! -e $sqlite && ! -L $sqlite ]] ||
      [[ -f $sqlite && ! -L $sqlite ]] || j3w1zsh_die "Workspace SQLite input must be a regular non-symlink file."
  fi
}

j3w1zsh_workspace_backup_sqlite() {
  jq -e --arg platform "$J3W1ZSH_PLATFORM" '.targets[$platform].environment_guard.sqlite_backup == true' "$J3W1ZSH_WORKSPACE_FILE" >/dev/null || return 0
  local database="$J3W1ZSH_WORKSPACE_ROOT/database/database.sqlite"
  [[ ! -e $database && ! -L $database ]] ||
    [[ -f $database && ! -L $database ]] || j3w1zsh_die "Workspace SQLite input must be a regular non-symlink file."
  [[ -f $database ]] || return 0
  local backup="$J3W1ZSH_WORKSPACE_GENERATION/backups/sqlite/database.sqlite.before-setup"
  [[ -e $backup ]] && return 0
  mkdir -p "$(dirname -- "$backup")"
  cp -p -- "$database" "$backup"
  chmod 600 "$backup"
}

j3w1zsh_workspace_packages_phase() {
  local manager packages_json
  manager="$(j3w1zsh_package_manager_for_platform)"
  J3W1ZSH_PACKAGE_LAYER="workspace"
  J3W1ZSH_PACKAGE_PLAN_DIGEST="$(j3w1zsh_workspace_plan_json "$J3W1ZSH_WORKSPACE_FILE" | sha256sum | awk '{print $1}')"
  export J3W1ZSH_PACKAGE_LAYER J3W1ZSH_PACKAGE_PLAN_DIGEST
  for manager in "$manager" npm_global pip_user; do
    packages_json="$(jq -c --arg platform "$J3W1ZSH_PLATFORM" --arg manager "$manager" '.targets[$platform].packages[$manager]' "$J3W1ZSH_WORKSPACE_FILE")"
    j3w1zsh_install_package_set "$manager" "$packages_json"
  done
  unset J3W1ZSH_PACKAGE_LAYER
  unset J3W1ZSH_PACKAGE_PLAN_DIGEST
}

j3w1zsh_workspace_effective_destination() {
  local adapter="$1" destination="$2"
  case "$adapter" in
  home-file)
    j3w1zsh_workspace_path_token "$destination" "home-file destination"
    printf '%s/%s\n' "$HOME" "$destination"
    ;;
  php-conf)
    [[ $J3W1ZSH_PLATFORM != termux ]] || j3w1zsh_die "Termux cannot use the php-conf adapter."
    if [[ -n ${J3W1ZSH_WORKSPACE_ETC_ROOT:-} ]]; then
      printf '%s%s\n' "${J3W1ZSH_WORKSPACE_ETC_ROOT%/}" "$destination"
    else
      printf '%s\n' "$destination"
    fi
    ;;
  *) j3w1zsh_die "Unsupported managed-file adapter: $adapter" ;;
  esac
}

j3w1zsh_workspace_managed_files_phase() {
  local adapter source destination effective backup relative
  while IFS=$'\t' read -r adapter source destination; do
    effective="$(j3w1zsh_workspace_effective_destination "$adapter" "$destination")"
    if [[ $adapter == home-file ]]; then
      j3w1zsh_validate_home_target "$effective"
      relative="home/$destination"
    else
      relative="system/${destination#/}"
      [[ ! -L $effective ]] || j3w1zsh_die "System managed destination must not be a symlink: $destination"
      [[ ! -e $effective || -f $effective ]] || j3w1zsh_die "System managed destination must be a regular file: $destination"
    fi
    if [[ -e $effective || -L $effective ]]; then
      if cmp -s -- "$J3W1ZSH_WORKSPACE_ROOT/$source" "$effective"; then
        continue
      fi
      backup="$J3W1ZSH_WORKSPACE_GENERATION/backups/managed-files/$relative"
      if [[ ! -e $backup && ! -L $backup ]]; then
        mkdir -p "$(dirname -- "$backup")"
        cp -a -- "$effective" "$backup"
      fi
      if [[ $adapter == home-file ]]; then
        if [[ -d $effective && ! -L $effective ]]; then
          rm -r -- "$effective"
        else
          rm -f -- "$effective"
        fi
      fi
    fi
    if [[ $adapter == php-conf && -z ${J3W1ZSH_WORKSPACE_ETC_ROOT:-} ]]; then
      sudo install -D -m 0644 "$J3W1ZSH_WORKSPACE_ROOT/$source" "$effective"
    else
      install -D -m 0644 "$J3W1ZSH_WORKSPACE_ROOT/$source" "$effective"
    fi
  done < <(jq -r --arg platform "$J3W1ZSH_PLATFORM" '.targets[$platform].managed_files[] | [.adapter,.source,.destination] | @tsv' "$J3W1ZSH_WORKSPACE_FILE")
}

j3w1zsh_workspace_run_commands() {
  local expression="$1" command_json argv=()
  while IFS= read -r command_json; do
    mapfile -t argv < <(jq -r '.argv[]' <<<"$command_json")
    ((${#argv[@]})) || j3w1zsh_die "Workspace lifecycle command is empty."
    (cd -- "$J3W1ZSH_WORKSPACE_ROOT" && env TMPDIR="${TMPDIR:-/tmp}" "${argv[@]}")
  done < <(jq -c --arg platform "$J3W1ZSH_PLATFORM" --arg expression "$expression" '.targets[$platform].lifecycle[$expression][]' "$J3W1ZSH_WORKSPACE_FILE")
}

j3w1zsh_workspace_runtime_actual() {
  local adapter="$1"
  case "$adapter" in
  php) php -r 'printf("%s.%s", PHP_MAJOR_VERSION, PHP_MINOR_VERSION);' ;;
  node) node --version | sed 's/^v//' ;;
  pnpm) pnpm --version ;;
  esac
}

j3w1zsh_workspace_verify_phase() {
  j3w1zsh_workspace_guard_environment
  local binary extension adapter requirement actual source destination effective
  while IFS= read -r binary; do
    command -v "$binary" >/dev/null 2>&1 || j3w1zsh_die "Workspace binary is missing: $binary"
  done < <(jq -r --arg platform "$J3W1ZSH_PLATFORM" '.targets[$platform].requirements.binaries[]' "$J3W1ZSH_WORKSPACE_FILE")
  while IFS= read -r extension; do
    php -m | grep -Fxiq -- "$extension" || j3w1zsh_die "Workspace PHP extension is missing: $extension"
  done < <(jq -r --arg platform "$J3W1ZSH_PLATFORM" '.targets[$platform].requirements.extensions[]' "$J3W1ZSH_WORKSPACE_FILE")
  while IFS=$'\t' read -r adapter requirement; do
    actual="$(j3w1zsh_workspace_runtime_actual "$adapter")"
    [[ $actual == "$requirement" ]] || j3w1zsh_die "Workspace runtime mismatch for $adapter: expected $requirement, found $actual"
  done < <(jq -r --arg platform "$J3W1ZSH_PLATFORM" '.targets[$platform].runtime_requirements[] | [.adapter,.requirement] | @tsv' "$J3W1ZSH_WORKSPACE_FILE")
  while IFS=$'\t' read -r source adapter destination; do
    effective="$(j3w1zsh_workspace_effective_destination "$adapter" "$destination")"
    cmp -s -- "$J3W1ZSH_WORKSPACE_ROOT/$source" "$effective" || j3w1zsh_die "Managed destination differs from source: $destination"
  done < <(jq -r --arg platform "$J3W1ZSH_PLATFORM" '.targets[$platform].managed_files[] | [.source,.adapter,.destination] | @tsv' "$J3W1ZSH_WORKSPACE_FILE")
  j3w1zsh_workspace_run_commands verify
}

j3w1zsh_workspace_execute_phase() {
  case "$1" in
  workspace-packages) j3w1zsh_workspace_packages_phase ;;
  workspace-managed-files) j3w1zsh_workspace_managed_files_phase ;;
  workspace-setup)
    j3w1zsh_workspace_guard_environment
    j3w1zsh_workspace_backup_sqlite
    j3w1zsh_workspace_run_commands setup
    ;;
  workspace-verify) j3w1zsh_workspace_verify_phase ;;
  *) j3w1zsh_die "Unknown workspace execution phase: $1" ;;
  esac
}

j3w1zsh_workspace_execute() {
  local force="$1" phase actions action
  actions="$(j3w1zsh_workspace_plan_json "$J3W1ZSH_WORKSPACE_FILE")"
  for phase in "${J3W1ZSH_WORKSPACE_PHASES[@]}"; do
    if [[ $force != 1 ]] && j3w1zsh_workspace_phase_done "$phase"; then
      j3w1zsh_note "Skipping completed workspace phase: $phase"
      continue
    fi
    j3w1zsh_log "Workspace phase $phase"
    action="$(jq -c --arg phase "$phase" '[.[] | select(.phase == $phase)][0] // empty' <<<"$actions")"
    if [[ -z $action ]]; then
      j3w1zsh_note "Workspace phase is unselected: $phase"
      continue
    fi
    j3w1zsh_execute_typed_callback "$action" j3w1zsh_workspace_execute_phase "$phase"
    j3w1zsh_workspace_mark_phase "$phase"
  done
  j3w1zsh_workspace_write_active
  local development
  development="$(jq -r --arg platform "$J3W1ZSH_PLATFORM" '.targets[$platform].lifecycle.development.argv | @sh' "$J3W1ZSH_WORKSPACE_FILE")"
  j3w1zsh_note "Development command (display only; never started automatically): $development"
}

j3w1zsh_workspace_validate_command() {
  (($# == 1)) || j3w1zsh_usage_error "workspace validate requires exactly one FILE."
  j3w1zsh_workspace_validate_structural "$1"
  local state
  state="$(jq -r '.workspace.review_state' "$1")"
  if [[ $J3W1ZSH_OUTPUT_MODE == json ]]; then
    j3w1zsh_json_envelope workspace-validate ok "$(jq -cn --arg file "$(readlink -f -- "$1")" --arg review_state "$state" '{file:$file,review_state:$review_state,structurally_valid:true,apply_eligible:($review_state=="approved")}')"
  else
    j3w1zsh_log "Workspace profile is structurally valid ($state)."
    [[ $state == approved ]] || j3w1zsh_warn "Candidate profiles can be planned but cannot be applied."
  fi
}

j3w1zsh_workspace_plan_command() {
  (($# == 1)) || j3w1zsh_usage_error "workspace plan requires exactly one FILE."
  local actions file id digest review_state
  j3w1zsh_workspace_bind "$1" 0
  file="$J3W1ZSH_WORKSPACE_FILE"
  id="$J3W1ZSH_WORKSPACE_ID"
  digest="$J3W1ZSH_WORKSPACE_DIGEST"
  review_state="$(jq -r .workspace.review_state "$file")"
  actions="$(j3w1zsh_workspace_plan_json "$file")"
  if [[ $J3W1ZSH_OUTPUT_MODE == json ]]; then
    j3w1zsh_json_envelope workspace-plan ok "$(jq -cn --arg file "$file" --arg id "$id" --arg digest "$digest" --arg platform "$J3W1ZSH_PLATFORM" --arg review_state "$review_state" --argjson actions "$actions" '{file:$file,workspace_id:$id,manifest_sha256:$digest,platform:$platform,review_state:$review_state,actions:$actions}')"
  else
    printf 'Workspace plan: %s\nManifest SHA-256: %s\nPlatform: %s\n\n' "$id" "$digest" "$J3W1ZSH_PLATFORM"
    jq -r '.[] | "  " + .phase + "  " + .kind + "  " + .reason + (if .mutation then " [mutation]" else " [read-only]" end)' <<<"$actions"
  fi
}

j3w1zsh_workspace_apply_command() {
  local file="" force=0
  while (($#)); do
    case "$1" in
    --yes) J3W1ZSH_ASSUME_YES=1 ;;
    --dry-run) J3W1ZSH_DRY_RUN=1 ;;
    --force) force=1 ;;
    --*) j3w1zsh_usage_error "Unknown workspace apply option: $1" ;;
    *) [[ -z $file ]] || j3w1zsh_usage_error "workspace apply accepts exactly one FILE."; file="$1" ;;
    esac
    shift
  done
  [[ -n $file ]] || j3w1zsh_usage_error "workspace apply requires a FILE."
  export J3W1ZSH_ASSUME_YES J3W1ZSH_DRY_RUN
  j3w1zsh_workspace_validate_structural "$file"
  j3w1zsh_workspace_require_platform_target "$file"
  if [[ $(jq -r '.workspace.review_state' "$file") != approved ]]; then
    j3w1zsh_die "Candidate workspace profiles cannot be applied. Review, approve, and commit the profile first."
  fi
  # Dry-run and execution enforce the same tracked-source and local-input boundary.
  j3w1zsh_workspace_bind "$file" 1
  j3w1zsh_workspace_validate_local_inputs
  if [[ $J3W1ZSH_DRY_RUN == 1 ]]; then
    if [[ $J3W1ZSH_OUTPUT_MODE == json ]]; then
      local resolved_file actions id digest
      resolved_file="$(readlink -f -- "$file")"
      id="$(jq -r .workspace.id "$resolved_file")"
      digest="$(sha256sum "$resolved_file" | awk '{print $1}')"
      actions="$(j3w1zsh_workspace_plan_json "$resolved_file")"
      j3w1zsh_json_envelope workspace-apply ok "$(jq -cn --arg file "$resolved_file" --arg id "$id" --arg digest "$digest" --arg platform "$J3W1ZSH_PLATFORM" --argjson actions "$actions" '{dry_run:true,file:$file,workspace_id:$id,manifest_sha256:$digest,platform:$platform,actions:$actions}')"
    else
      j3w1zsh_workspace_plan_command "$file"
    fi
    return 0
  fi
  # Every hostile-input and target escape check above occurs before state or packages can mutate.
  printf 'Workspace: %s\nPlatform target: %s\nManifest SHA-256: %s\nProject commit: %s\n' \
    "$J3W1ZSH_WORKSPACE_ID" "$J3W1ZSH_PLATFORM" "$J3W1ZSH_WORKSPACE_DIGEST" "$J3W1ZSH_WORKSPACE_COMMIT"
  j3w1zsh_confirm "Trust and apply exactly this committed workspace generation?" || return 0
  j3w1zsh_ensure_dirs
  j3w1zsh_workspace_write_trust
  j3w1zsh_workspace_execute "$force"
  [[ $J3W1ZSH_OUTPUT_MODE != json ]] || j3w1zsh_json_envelope workspace-apply ok "$(jq -cn --arg id "$J3W1ZSH_WORKSPACE_ID" --arg digest "$J3W1ZSH_WORKSPACE_DIGEST" --arg platform "$J3W1ZSH_PLATFORM" '{workspace_id:$id,manifest_sha256:$digest,platform:$platform}')"
}

j3w1zsh_workspace_audit_data() {
  local file="$1"
  j3w1zsh_workspace_bind "$file" 0
  local checks='[]' status=ok manager package installed binary extension adapter requirement actual source destination effective
  manager="$(j3w1zsh_package_manager_for_platform)"
  for manager in "$manager" npm_global pip_user; do
    while IFS= read -r package; do
      installed=false
      j3w1zsh_package_is_installed "$manager" "$package" && installed=true
      [[ $installed == true ]] || status=error
      checks="$(jq -cn --argjson checks "$checks" --arg kind package --arg name "$manager:$package" --argjson ok "$installed" '$checks + [{kind:$kind,name:$name,ok:$ok}]')"
    done < <(jq -r --arg platform "$J3W1ZSH_PLATFORM" --arg manager "$manager" '.targets[$platform].packages[$manager][]' "$file")
  done
  while IFS= read -r binary; do
    installed=false; command -v "$binary" >/dev/null 2>&1 && installed=true; [[ $installed == true ]] || status=error
    checks="$(jq -cn --argjson checks "$checks" --arg kind binary --arg name "$binary" --argjson ok "$installed" '$checks + [{kind:$kind,name:$name,ok:$ok}]')"
  done < <(jq -r --arg platform "$J3W1ZSH_PLATFORM" '.targets[$platform].requirements.binaries[]' "$file")
  while IFS= read -r extension; do
    installed=false; command -v php >/dev/null 2>&1 && php -m | grep -Fxiq -- "$extension" && installed=true; [[ $installed == true ]] || status=error
    checks="$(jq -cn --argjson checks "$checks" --arg kind extension --arg name "$extension" --argjson ok "$installed" '$checks + [{kind:$kind,name:$name,ok:$ok}]')"
  done < <(jq -r --arg platform "$J3W1ZSH_PLATFORM" '.targets[$platform].requirements.extensions[]' "$file")
  while IFS=$'\t' read -r adapter requirement; do
    actual="$(j3w1zsh_workspace_runtime_actual "$adapter" 2>/dev/null || true)"
    installed=false; [[ $actual == "$requirement" ]] && installed=true; [[ $installed == true ]] || status=error
    checks="$(jq -cn --argjson checks "$checks" --arg kind runtime --arg name "$adapter" --arg expected "$requirement" --arg actual "$actual" --argjson ok "$installed" '$checks + [{kind:$kind,name:$name,expected:$expected,actual:$actual,ok:$ok}]')"
  done < <(jq -r --arg platform "$J3W1ZSH_PLATFORM" '.targets[$platform].runtime_requirements[] | [.adapter,.requirement] | @tsv' "$file")
  while IFS=$'\t' read -r source adapter destination; do
    effective="$(j3w1zsh_workspace_effective_destination "$adapter" "$destination")"
    installed=false; cmp -s -- "$J3W1ZSH_WORKSPACE_ROOT/$source" "$effective" && installed=true; [[ $installed == true ]] || status=error
    checks="$(jq -cn --argjson checks "$checks" --arg kind managed-file --arg name "$destination" --argjson ok "$installed" '$checks + [{kind:$kind,name:$name,ok:$ok}]')"
  done < <(jq -r --arg platform "$J3W1ZSH_PLATFORM" '.targets[$platform].managed_files[] | [.source,.adapter,.destination] | @tsv' "$file")
  jq -cn --arg status "$status" --arg id "$J3W1ZSH_WORKSPACE_ID" --arg digest "$J3W1ZSH_WORKSPACE_DIGEST" --argjson checks "$checks" '{status:$status,workspace_id:$id,manifest_sha256:$digest,checks:$checks}'
}

j3w1zsh_workspace_audit_command() {
  (($# == 1)) || j3w1zsh_usage_error "workspace audit requires exactly one FILE."
  local data status
  data="$(j3w1zsh_workspace_audit_data "$1")"
  status="$(jq -r .status <<<"$data")"
  if [[ $J3W1ZSH_OUTPUT_MODE == json ]]; then
    j3w1zsh_json_envelope workspace-audit "$status" "$data"
  else
    jq -r '.checks[] | (if .ok then "[ok] " else "[missing] " end) + .kind + " " + .name' <<<"$data"
  fi
  [[ $status == ok ]]
}

j3w1zsh_workspace_status_data() {
  local active="$J3W1ZSH_STATE_DIR/workspaces/active.json"
  local active_state=0
  j3w1zsh_workspace_validate_active_record || active_state=$?
  [[ $active_state != 3 ]] || { printf 'null\n'; return 0; }
  ((active_state == 0)) || return "$active_state"
  local file platform stored_id stored_digest phases='[]' phase state actions
  file="$(jq -r .manifest "$active")"
  platform="$(jq -r .platform "$active")"
  stored_id="$(jq -r .workspace_id "$active")"
  stored_digest="$(jq -r .manifest_sha256 "$active")"
  [[ $platform == "$J3W1ZSH_PLATFORM" ]] || j3w1zsh_die "Active workspace belongs to platform $platform, not $J3W1ZSH_PLATFORM."
  j3w1zsh_workspace_bind "$file" 0
  [[ $stored_id == "$J3W1ZSH_WORKSPACE_ID" && $stored_digest == "$J3W1ZSH_WORKSPACE_DIGEST" ]] ||
    j3w1zsh_die "Active workspace manifest changed; apply and trust a new committed generation explicitly."
  actions="$(j3w1zsh_workspace_plan_json "$file")"
  for phase in "${J3W1ZSH_WORKSPACE_PHASES[@]}"; do
    if ! jq -e --arg phase "$phase" 'any(.[]; .phase == $phase)' <<<"$actions" >/dev/null; then
      state=unselected
    else
      state=pending
      j3w1zsh_workspace_phase_done "$phase" && state=complete
    fi
    phases="$(jq -cn --argjson phases "$phases" --arg phase "$phase" --arg state "$state" '$phases + [{phase:$phase,state:$state}]')"
  done
  jq -cn --arg id "$J3W1ZSH_WORKSPACE_ID" --arg manifest "$file" --arg digest "$J3W1ZSH_WORKSPACE_DIGEST" --arg platform "$platform" --argjson phases "$phases" '{workspace_id:$id,manifest:$manifest,manifest_sha256:$digest,platform:$platform,phases:$phases}'
}

j3w1zsh_workspace_status_command() {
  (($# == 0)) || j3w1zsh_usage_error "workspace status accepts no arguments."
  local data
  data="$(j3w1zsh_workspace_status_data)"
  if [[ $J3W1ZSH_OUTPUT_MODE == json ]]; then
    j3w1zsh_json_envelope workspace-status ok "$data"
  elif [[ $data == null ]]; then
    printf 'No active workspace.\n'
  else
    jq -r '"Active workspace: " + .workspace_id + "\nManifest SHA-256: " + .manifest_sha256 + "\nPlatform: " + .platform + "\n" + ([.phases[] | .phase + "\t" + .state] | join("\n"))' <<<"$data"
  fi
}

j3w1zsh_workspace_resume_command() {
  local force=0
  while (($#)); do
    case "$1" in --yes) J3W1ZSH_ASSUME_YES=1 ;; --dry-run) J3W1ZSH_DRY_RUN=1 ;; --force) force=1 ;; *) j3w1zsh_usage_error "Unknown workspace resume option: $1" ;; esac
    shift
  done
  local active="$J3W1ZSH_STATE_DIR/workspaces/active.json"
  local active_state=0
  j3w1zsh_workspace_validate_active_record || active_state=$?
  [[ $active_state != 3 ]] || j3w1zsh_die "No active workspace can be resumed."
  ((active_state == 0)) || return "$active_state"
  local file digest platform
  file="$(jq -r .manifest "$active")"; digest="$(jq -r .manifest_sha256 "$active")"; platform="$(jq -r .platform "$active")"
  [[ $platform == "$J3W1ZSH_PLATFORM" ]] || j3w1zsh_die "Active workspace belongs to platform $platform."
  j3w1zsh_workspace_bind "$file" 1
  j3w1zsh_workspace_validate_local_inputs
  [[ $digest == "$J3W1ZSH_WORKSPACE_DIGEST" ]] || j3w1zsh_die "Active workspace manifest changed; run workspace apply to trust a new generation."
  [[ $J3W1ZSH_DRY_RUN != 1 ]] || { j3w1zsh_workspace_plan_command "$file"; return 0; }
  [[ -f $J3W1ZSH_WORKSPACE_GENERATION/trust.json ]] || j3w1zsh_die "Active workspace trust record is missing."
  j3w1zsh_workspace_execute "$force"
}

j3w1zsh_workspace_scan_target_json() {
  local platform="$1" project="$2"
  local runtime='[]' requirement
  if [[ -f $project/.php-version && ! -L $project/.php-version ]]; then
    requirement="$(tr -d '[:space:]' <"$project/.php-version")"
    runtime="$(jq -cn --argjson runtime "$runtime" --arg requirement "$requirement" '$runtime + [{adapter:"php",source:".php-version",requirement:$requirement}]')"
  fi
  if [[ -f $project/.node-version && ! -L $project/.node-version ]]; then
    requirement="$(tr -d '[:space:]' <"$project/.node-version")"
    runtime="$(jq -cn --argjson runtime "$runtime" --arg requirement "$requirement" '$runtime + [{adapter:"node",source:".node-version",requirement:$requirement}]')"
  fi
  if [[ -f $project/package.json && ! -L $project/package.json ]]; then
    requirement="$(jq -r '.packageManager // "" | select(startswith("pnpm@")) | sub("^pnpm@";"")' "$project/package.json" 2>/dev/null || true)"
    [[ -z $requirement ]] || runtime="$(jq -cn --argjson runtime "$runtime" --arg requirement "$requirement" '$runtime + [{adapter:"pnpm",source:"package.json",requirement:$requirement}]')"
  fi
  local development='{"argv":["make"]}'
  if [[ -f $project/package.json ]] && jq -e '.scripts.dev | type == "string"' "$project/package.json" >/dev/null 2>&1; then
    development='{"argv":["pnpm","run","dev"]}'
  fi
  if [[ $platform == termux ]]; then
    jq -cn --argjson runtime "$runtime" --argjson development "$development" '{
      packages:{pkg:[],npm_global:[],pip_user:[]},runtime_requirements:$runtime,
      requirements:{binaries:[],extensions:[]},managed_files:[],
      environment_guard:{app_env:"local",app_url_scope:"loopback",db_connection:"none",sqlite_backup:false},
      lifecycle:{setup:[],verify:[],development:$development},ports:[],
      capabilities:{j3w1zsh_base:true,remote_host:"optional"}
    }'
  else
    jq -cn --argjson runtime "$runtime" --argjson development "$development" '{
      packages:{pacman:[],npm_global:[],pip_user:[]},runtime_requirements:$runtime,
      requirements:{binaries:[],extensions:[]},managed_files:[],
      environment_guard:{app_env:"local",app_url_scope:"loopback",db_connection:"none",sqlite_backup:false},
      lifecycle:{setup:[],verify:[],development:$development},ports:[],
      capabilities:{j3w1zsh_base:true}
    }'
  fi
}

j3w1zsh_workspace_scan_command() {
  local project="" output="" targets='[]'
  while (($#)); do
    case "$1" in
    --project) shift; (($#)) || j3w1zsh_usage_error "--project requires a directory."; project="$1" ;;
    --output) shift; (($#)) || j3w1zsh_usage_error "--output requires a file."; output="$1" ;;
    --target)
      shift; (($#)) || j3w1zsh_usage_error "--target requires arch, wsl, or termux."
      [[ $1 =~ ^(arch|wsl|termux)$ ]] || j3w1zsh_usage_error "Invalid scan target: $1"
      targets="$(jq -cn --argjson targets "$targets" --arg target "$1" '$targets + [$target] | unique')"
      ;;
    *) j3w1zsh_usage_error "Unknown workspace scan option: $1" ;;
    esac
    shift
  done
  [[ -n $project && -n $output ]] || j3w1zsh_usage_error "workspace scan requires --project DIR and --output FILE."
  [[ -d $project ]] || j3w1zsh_die "Project directory does not exist: $project"
  [[ ! -e $output && ! -L $output ]] || j3w1zsh_die "Refusing to overwrite workspace scan output: $output"
  (($(jq length <<<"$targets") > 0)) || targets="$(jq -cn --arg target "$J3W1ZSH_PLATFORM" '[$target]')"
  if jq -e 'any(.[]; . == "unsupported" or . == "wsl1")' <<<"$targets" >/dev/null; then
    j3w1zsh_die "A scan target must be arch, wsl, or termux."
  fi
  project="$(readlink -f -- "$project")"
  local id display target target_json targets_json='{}'
  display="$(basename -- "$project")"
  id="$(tr '[:upper:]' '[:lower:]' <<<"$display" | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g')"
  [[ ${#id} -ge 2 ]] || id=workspace
  while IFS= read -r target; do
    target_json="$(j3w1zsh_workspace_scan_target_json "$target" "$project")"
    targets_json="$(jq -cn --argjson targets "$targets_json" --arg target "$target" --argjson value "$target_json" '$targets + {($target):$value}')"
  done < <(jq -r '.[]' <<<"$targets")
  local document temporary
  document="$(jq -cn --arg schema "https://github.com/j3w1/j3w1zsh/blob/main/schemas/workspace-profile-v2.schema.json" --arg id "$id" --arg display "$display" --argjson targets "$targets_json" '{"$schema":$schema,schema_version:2,workspace:{id:$id,display_name:$display,minimum_j3w1zsh_version:"1.0.0",review_state:"candidate"},targets:$targets}')"
  local validation_file
  validation_file="$(mktemp "${TMPDIR:-/tmp}/j3w1zsh-workspace-validate.XXXXXX")"
  printf '%s\n' "$document" >"$validation_file"
  j3w1zsh_workspace_validate_structural "$validation_file"
  rm -- "$validation_file"
  mkdir -p "$(dirname -- "$output")"
  temporary="$(mktemp "${TMPDIR:-/tmp}/j3w1zsh-workspace-scan.XXXXXX")"
  jq . <<<"$document" >"$temporary"
  chmod 600 "$temporary"
  mv -- "$temporary" "$output"
  j3w1zsh_log "Wrote new candidate workspace profile: $output"
  j3w1zsh_warn "Review every target and exclusion, commit the file, then explicitly approve it before apply."
}

j3w1zsh_workspace_command() {
  local subcommand="${1:-help}"
  (($# == 0)) || shift
  case "$subcommand" in
  scan) j3w1zsh_workspace_scan_command "$@" ;;
  validate) j3w1zsh_workspace_validate_command "$@" ;;
  plan) j3w1zsh_workspace_plan_command "$@" ;;
  audit) j3w1zsh_workspace_audit_command "$@" ;;
  apply) j3w1zsh_workspace_apply_command "$@" ;;
  status) j3w1zsh_workspace_status_command "$@" ;;
  resume) j3w1zsh_workspace_resume_command "$@" ;;
  migrate) j3w1zsh_workspace_v1_migrate_command "$@" ;;
  help | -h | --help) j3w1zsh_workspace_usage ;;
  *) j3w1zsh_usage_error "Unknown workspace command: $subcommand" ;;
  esac
}
