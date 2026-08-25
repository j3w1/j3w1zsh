#!/usr/bin/env bash

# This isolated converter is the only product code that understands the former workspace shape.
j3w1zsh_workspace_v1_validate_input() {
  local file="$1"
  [[ -f $file && ! -L $file ]] || j3w1zsh_die "Legacy workspace input must be a regular non-symlink file: $file"
  jq -e '
    def exact($wanted): (keys | sort) == ($wanted | sort);
    def strings: type == "array" and length == (unique | length) and all(.[]; type == "string" and length > 0);
    def version_requirement:
      type == "object" and exact(["source","requirement"]) and
      (.source | type == "string" and length > 0) and (.requirement | type == "string" and length > 0);
    def command:
      type == "object" and exact(["argv"]) and
      (.argv | type == "array" and length > 0 and all(.[]; type == "string" and length > 0));
    type == "object" and
    exact(["$schema","schema_version","profile","platform","packages","versions","requirements","system_files","environment_guard","lifecycle","ports","capabilities"]) and
    (."$schema" | type == "string") and .schema_version == 1 and
    (.profile |
      type == "object" and exact(["id","display_name","minimum_bloody_writer_version","review_state"]) and
      (.id | type == "string" and test("^[a-z0-9][a-z0-9-]{1,62}$")) and
      (.display_name | type == "string" and length > 0 and length <= 120) and
      (.minimum_bloody_writer_version | type == "string" and test("^[0-9]+\\.[0-9]+\\.[0-9]+$")) and
      (.review_state == "approved" or .review_state == "candidate")) and
    (.platform | type == "object" and exact(["distribution","environment","wsl_version"])) and
    .platform == {distribution:"arch",environment:"wsl",wsl_version:2} and
    (.packages | type == "object" and exact(["pacman","npm_global"]) and (.pacman | strings) and (.npm_global | strings)) and
    (.versions | type == "object" and exact(["php","node","pnpm"]) and
      (.php | version_requirement) and (.node | version_requirement) and (.pnpm | version_requirement)) and
    (.requirements | type == "object" and exact(["binaries","php_extensions"]) and
      (.binaries | strings) and (.php_extensions | strings)) and
    (.system_files | type == "array" and all(.[];
      type == "object" and exact(["adapter","source","destination"]) and .adapter == "php-conf" and
      (.source | type == "string" and length > 0) and
      (.destination | type == "string" and test("^/etc/php/conf\\.d/[A-Za-z0-9._-]+\\.ini$")))) and
    (.environment_guard | type == "object" and exact(["app_env","app_url_scope","db_connection","sqlite_backup"]) and
      .app_env == "local" and .app_url_scope == "loopback" and .db_connection == "sqlite" and .sqlite_backup == true) and
    (.lifecycle | type == "object" and exact(["setup","verify","development"]) and
      (.setup | type == "array" and all(.[]; command)) and
      (.verify | type == "array" and all(.[]; command)) and (.development | command)) and
    (.ports | type == "array" and all(.[];
      type == "object" and exact(["host","port","purpose"]) and
      (.host == "127.0.0.1" or .host == "localhost" or .host == "::1") and
      (.port | type == "number" and floor == . and . >= 1 and . <= 65535) and
      (.purpose | type == "string" and length > 0 and length <= 100))) and
    (.capabilities | type == "object" and exact(["bloody_writer_base"]) and .bloody_writer_base == true)
  ' "$file" >/dev/null || j3w1zsh_die "Input is not a recognized valid workspace schema-v1 profile."
}

j3w1zsh_workspace_v1_convert_json() {
  local file="$1"
  jq --arg schema "https://github.com/j3w1/j3w1zsh/blob/main/schemas/workspace-profile-v2.schema.json" '
    {
      "$schema":$schema,
      schema_version:2,
      workspace:{
        id:.profile.id,
        display_name:.profile.display_name,
        minimum_j3w1zsh_version:"1.0.0",
        review_state:"candidate"
      },
      targets:{
        wsl:{
          packages:{pacman:.packages.pacman,npm_global:.packages.npm_global,pip_user:[]},
          runtime_requirements:[
            {adapter:"php",source:.versions.php.source,requirement:.versions.php.requirement},
            {adapter:"node",source:.versions.node.source,requirement:.versions.node.requirement},
            {adapter:"pnpm",source:.versions.pnpm.source,requirement:.versions.pnpm.requirement}
          ],
          requirements:{binaries:.requirements.binaries,extensions:.requirements.php_extensions},
          managed_files:[.system_files[] | {adapter:.adapter,source:.source,destination:.destination}],
          environment_guard:.environment_guard,
          lifecycle:.lifecycle,
          ports:.ports,
          capabilities:{j3w1zsh_base:true}
        }
      }
    }
  ' "$file"
}

j3w1zsh_workspace_v1_report_json() {
  jq -cn '{
    schema_version:1,
    transformed:[
      "profile to workspace","minimum product version field","WSL platform to targets.wsl",
      "versions to runtime_requirements","system_files to managed_files","base capability name"
    ],
    defaulted:["workspace.review_state=candidate","packages.pip_user=[]","minimum_j3w1zsh_version=1.0.0"],
    omitted:["no credentials, .env bytes, SQLite bytes, histories, caches, machine identity, or private evidence imported"],
    unresolved:["human review of every target, package, managed destination, lifecycle argv, port, and capability is required"]
  }'
}

j3w1zsh_workspace_v1_migrate_command() {
  local input="" output="" dry_run=0
  while (($#)); do
    case "$1" in
    --output) shift; (($#)) || j3w1zsh_usage_error "--output requires a path."; output="$1" ;;
    --dry-run) dry_run=1 ;;
    --*) j3w1zsh_usage_error "Unknown workspace migrate option: $1" ;;
    *) [[ -z $input ]] || j3w1zsh_usage_error "workspace migrate accepts one OLD_FILE."; input="$1" ;;
    esac
    shift
  done
  [[ -n $input ]] || j3w1zsh_usage_error "workspace migrate requires OLD_FILE."
  [[ -n $output ]] || output="$(dirname -- "$input")/j3w1zsh.workspace.json"
  j3w1zsh_workspace_v1_validate_input "$input"
  local converted report
  converted="$(j3w1zsh_workspace_v1_convert_json "$input")"
  report="$(j3w1zsh_workspace_v1_report_json)"
  local validation_file
  validation_file="$(mktemp "${TMPDIR:-/tmp}/j3w1zsh-workspace-v2-validate.XXXXXX")"
  printf '%s\n' "$converted" >"$validation_file"
  j3w1zsh_workspace_validate_structural "$validation_file"
  rm -- "$validation_file"
  if ((dry_run)); then
    if [[ $J3W1ZSH_OUTPUT_MODE == json ]]; then
      j3w1zsh_json_envelope workspace-migrate ok "$(jq -cn --arg output "$output" --argjson profile "$converted" --argjson report "$report" '{dry_run:true,output:$output,profile:$profile,report:$report}')"
    else
      jq . <<<"$converted"
      printf '\nTransformation report:\n'
      jq . <<<"$report"
    fi
    return 0
  fi
  [[ ! -e $output && ! -L $output ]] || j3w1zsh_die "Refusing to overwrite workspace migration output: $output"
  local report_path="$output.migration-report.json" temporary
  [[ ! -e $report_path && ! -L $report_path ]] || j3w1zsh_die "Refusing to overwrite workspace migration report: $report_path"
  mkdir -p "$(dirname -- "$output")"
  temporary="$(mktemp "${TMPDIR:-/tmp}/j3w1zsh-workspace-migrate.XXXXXX")"
  jq . <<<"$converted" >"$temporary"
  chmod 600 "$temporary"
  mv -- "$temporary" "$output"
  temporary="$(mktemp "${TMPDIR:-/tmp}/j3w1zsh-workspace-report.XXXXXX")"
  jq . <<<"$report" >"$temporary"
  chmod 600 "$temporary"
  mv -- "$temporary" "$report_path"
  j3w1zsh_log "Wrote candidate workspace profile: $output"
  j3w1zsh_note "Transformation report: $report_path"
  j3w1zsh_warn "Human review, approval, and a clean Git commit are required before apply."
}
