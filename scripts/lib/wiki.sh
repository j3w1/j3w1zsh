#!/usr/bin/env bash

j3w1zsh_wiki_lock_file() {
  if [[ $J3W1ZSH_TEST_MODE == 1 && -n ${J3W1ZSH_TEST_WIKI_LOCK:-} ]]; then
    printf '%s\n' "$J3W1ZSH_TEST_WIKI_LOCK"
  else
    printf '%s/wiki-lock.json\n' "$J3W1ZSH_REPO_ROOT"
  fi
}

j3w1zsh_wiki_url() {
  if [[ $J3W1ZSH_TEST_MODE == 1 && -n ${J3W1ZSH_TEST_WIKI_URL:-} ]]; then
    printf '%s\n' "$J3W1ZSH_TEST_WIKI_URL"
  else
    printf 'https://github.com/j3w1/j3w1zsh.wiki.git\n'
  fi
}

j3w1zsh_wiki_git() {
  if [[ $J3W1ZSH_TEST_MODE == 1 ]]; then
    git "$@"
  else
    git -c credential.helper= -c 'credential.https://github.com.helper=!gh auth git-credential' "$@"
  fi
}

j3w1zsh_wiki_page_file() {
  printf '%s.md\n' "${1// /-}"
}

j3w1zsh_wiki_validate_contract() {
  local lock
  lock="$(j3w1zsh_wiki_lock_file)"
  [[ -f $lock && ! -L $lock ]] || j3w1zsh_die "Wiki lock is not a regular file: $lock"
  jq -e '
    type == "object" and
    (keys | sort) == ["agent_context","code_version","commit","repository","required_pages","schema_version"] and
    .schema_version == 1 and .repository == "j3w1/j3w1zsh" and
    (.commit | type == "string" and length > 0) and
    (.code_version | test("^[0-9]+\\.[0-9]+\\.[0-9]+$")) and
    (.required_pages | type == "array" and length > 0 and length == (unique | length)) and
    .agent_context == "agent-context.json"
  ' "$lock" >/dev/null || j3w1zsh_die "Wiki lock has an invalid contract."
  local context
  context="$J3W1ZSH_REPO_ROOT/$(jq -r .agent_context "$lock")"
  [[ -f $context && ! -L $context ]] || j3w1zsh_die "Agent context is missing."
  jq -e '
    type == "object" and (keys | sort) == ["code_version","default_exclusions","routes","schema_version"] and
    .schema_version == 1 and (.routes | type == "object") and
    all(.routes[]; (keys | sort) == ["code_paths","exclusions","wiki_pages"] and all(.[]; type == "array"))
  ' "$context" >/dev/null || j3w1zsh_die "Agent context has an invalid contract."
  local page file
  while IFS= read -r page; do
    file="$J3W1ZSH_REPO_ROOT/wiki/$(j3w1zsh_wiki_page_file "$page")"
    [[ -s $file ]] || j3w1zsh_die "Required prepared Wiki page is missing: $page ($file)"
  done < <(jq -r '.required_pages[]' "$lock")
  while IFS= read -r page; do
    jq -e --arg page "$page" '.required_pages | index($page)' "$lock" >/dev/null || j3w1zsh_die "Agent route names an unpinned Wiki page: $page"
  done < <(jq -r '.routes[].wiki_pages[]' "$context" | LC_ALL=C sort -u)
}

j3w1zsh_wiki_commit() {
  jq -r .commit "$(j3w1zsh_wiki_lock_file)"
}

j3w1zsh_wiki_cache() {
  printf '%s/wiki/cache.git\n' "$J3W1ZSH_STATE_DIR"
}

j3w1zsh_wiki_ensure_cache() {
  local url cache
  url="$(j3w1zsh_wiki_url)"; cache="$(j3w1zsh_wiki_cache)"
  j3w1zsh_ensure_dirs
  if [[ ! -d $cache ]]; then
    j3w1zsh_wiki_git clone --bare "$url" "$cache"
  else
    local configured
    configured="$(git --git-dir="$cache" remote get-url origin)"
    [[ $configured == "$url" ]] || j3w1zsh_die "Wiki cache origin differs from the canonical Wiki URL."
  fi
  j3w1zsh_wiki_git --git-dir="$cache" fetch --prune origin '+refs/heads/*:refs/remotes/origin/*'
}

j3w1zsh_wiki_materialize_commit() {
  local commit="$1" destination="$2" cache staging
  cache="$(j3w1zsh_wiki_cache)"
  git --git-dir="$cache" cat-file -e "$commit^{commit}" 2>/dev/null || j3w1zsh_die "Wiki commit is unreachable: $commit"
  if [[ -d $destination ]]; then
    local current
    current="$(git -C "$destination" rev-parse HEAD 2>/dev/null || true)"
    [[ $current == "$commit" && -z $(git -C "$destination" status --short) ]] || j3w1zsh_die "Existing Wiki materialization is dirty or at a different commit: $destination"
    return 0
  fi
  local staging_kind
  staging_kind="wiki-checkout-$(basename -- "$(dirname -- "$destination")")"
  mkdir -p "$(dirname -- "$destination")"
  j3w1zsh_create_ephemeral_dir staging "$staging_kind"
  git -C "$staging" init -q
  git -C "$staging" remote add origin "$cache"
  git -C "$staging" fetch -q origin "$commit"
  git -C "$staging" checkout -q --detach FETCH_HEAD
  j3w1zsh_promote_ephemeral_dir "$staging" "$destination"
}

j3w1zsh_wiki_sync_command() {
  local latest=0
  while (($#)); do
    case "$1" in --latest) latest=1 ;; *) j3w1zsh_usage_error "Unknown wiki sync option: $1" ;; esac
    shift
  done
  j3w1zsh_wiki_validate_contract
  local commit
  commit="$(j3w1zsh_wiki_commit)"
  if ((latest == 0)) && [[ $commit == PENDING_PREMERGE_PUBLICATION ]]; then
    j3w1zsh_die "Wiki publication is pending; no pinned commit exists yet."
  fi
  j3w1zsh_wiki_ensure_cache
  if ((latest)); then
    [[ -t 0 || $J3W1ZSH_TEST_MODE == 1 ]] || j3w1zsh_die "wiki sync --latest is a human-only override."
    commit="$(git --git-dir="$(j3w1zsh_wiki_cache)" rev-parse refs/remotes/origin/master 2>/dev/null || git --git-dir="$(j3w1zsh_wiki_cache)" rev-parse refs/remotes/origin/main)"
  fi
  local destination="$J3W1ZSH_STATE_DIR/wiki/pinned/$commit"
  ((latest == 0)) || destination="$J3W1ZSH_STATE_DIR/wiki/latest/$commit"
  j3w1zsh_wiki_materialize_commit "$commit" "$destination"
  [[ $J3W1ZSH_OUTPUT_MODE != json ]] || { j3w1zsh_json_envelope wiki-sync ok "$(jq -cn --arg commit "$commit" --arg path "$destination" --argjson latest "$([[ $latest == 1 ]] && printf true || printf false)" '{commit:$commit,path:$path,latest_override:$latest}')"; return; }
  j3w1zsh_note "Wiki commit: $commit"
  j3w1zsh_note "Materialized at: $destination"
}

j3w1zsh_wiki_status_data() {
  j3w1zsh_wiki_validate_contract
  local commit url canonical_head local_path local_head="" dirty=false compatible=false
  commit="$(j3w1zsh_wiki_commit)"; url="$(j3w1zsh_wiki_url)"
  if ! canonical_head="$(j3w1zsh_wiki_git ls-remote "$url" HEAD 2>/dev/null | awk 'NR==1 {print $1}')"; then
    canonical_head=""
  fi
  local_path="$J3W1ZSH_STATE_DIR/wiki/pinned/$commit"
  if [[ -d $local_path/.git ]]; then
    local_head="$(git -C "$local_path" rev-parse HEAD)"
    [[ -z $(git -C "$local_path" status --short) ]] || dirty=true
  fi
  if [[ $commit =~ ^[0-9a-f]{40}$ ]]; then
    local temporary
    j3w1zsh_create_ephemeral_dir temporary wiki-status
    git -C "$temporary" init -q
    git -C "$temporary" remote add origin "$url"
    if j3w1zsh_wiki_git -C "$temporary" fetch -q --depth=1 origin "$commit"; then compatible=true; fi
    j3w1zsh_cleanup_ephemeral_dir "$temporary" || j3w1zsh_die "Failed to clean the guarded Wiki status directory."
  fi
  jq -cn --arg pinned_head "$commit" --arg canonical_head "$canonical_head" --arg local_head "$local_head" \
    --argjson dirty "$dirty" --argjson compatible "$compatible" \
    '{pinned_head:$pinned_head,canonical_head:(if $canonical_head=="" then null else $canonical_head end),local_head:(if $local_head=="" then null else $local_head end),dirty:$dirty,divergent:($local_head!="" and $local_head!=$pinned_head),compatible:$compatible}'
}

j3w1zsh_wiki_context_command() {
  (($# == 1)) || j3w1zsh_usage_error "wiki context requires exactly one TOPIC."
  local topic="$1" context="$J3W1ZSH_REPO_ROOT/agent-context.json"
  jq -e --arg topic "$topic" '.routes | has($topic)' "$context" >/dev/null || j3w1zsh_usage_error "Unknown agent context topic: $topic"
  local commit
  commit="$(j3w1zsh_wiki_commit)"
  [[ $commit =~ ^[0-9a-f]{40}$ ]] || j3w1zsh_die "Agent context requires a published pinned Wiki commit."
  j3w1zsh_wiki_ensure_cache
  local cache destination staging page file
  cache="$(j3w1zsh_wiki_cache)"
  destination="$J3W1ZSH_STATE_DIR/wiki/context/$topic/$commit"
  if [[ -d $destination ]]; then
    local expected_count actual_count local_blob pinned_blob route_actual route_expected
    expected_count="$(jq --arg topic "$topic" '.routes[$topic].wiki_pages | length + 1' "$context")"
    actual_count="$(find "$destination" -mindepth 1 -maxdepth 1 -type f | wc -l)"
    [[ $actual_count == "$expected_count" && -z $(find "$destination" -mindepth 1 -maxdepth 1 ! -type f -print -quit) ]] ||
      j3w1zsh_die "Existing routed Wiki context contains unexpected entries: $destination"
    while IFS= read -r page; do
      file="$(j3w1zsh_wiki_page_file "$page")"
      [[ -f $destination/$file && ! -L $destination/$file ]] || j3w1zsh_die "Existing routed Wiki context is incomplete: $destination/$file"
      local_blob="$(git hash-object "$destination/$file")"
      pinned_blob="$(git --git-dir="$cache" rev-parse "$commit:$file")"
      [[ $local_blob == "$pinned_blob" ]] || j3w1zsh_die "Existing routed Wiki context differs from pinned bytes: $destination/$file"
    done < <(jq -r --arg topic "$topic" '.routes[$topic].wiki_pages[]' "$context")
    route_actual="$(jq -Sc . "$destination/route.json" 2>/dev/null || true)"
    route_expected="$(jq -Sc --arg topic "$topic" '.routes[$topic]' "$context")"
    [[ $route_actual == "$route_expected" ]] || j3w1zsh_die "Existing routed Wiki route metadata differs from agent-context.json."
    j3w1zsh_note "Verified pinned context already materialized: $destination"
    return 0
  fi
  j3w1zsh_create_ephemeral_dir staging wiki-context
  while IFS= read -r page; do
    file="$(j3w1zsh_wiki_page_file "$page")"
    git --git-dir="$cache" show "$commit:$file" >"$staging/$file" || j3w1zsh_die "Pinned Wiki page is missing at $commit: $file"
  done < <(jq -r --arg topic "$topic" '.routes[$topic].wiki_pages[]' "$context")
  jq -c --arg topic "$topic" '.routes[$topic]' "$context" >"$staging/route.json"
  mkdir -p "$(dirname -- "$destination")"
  j3w1zsh_promote_ephemeral_dir "$staging" "$destination"
  j3w1zsh_note "Materialized routed context: $destination"
}

j3w1zsh_wiki_update_lock() {
  local commit="$1" lock temporary
  lock="$(j3w1zsh_wiki_lock_file)"
  temporary="$(mktemp "$J3W1ZSH_REPO_ROOT/.wiki-lock.XXXXXX")"
  jq --arg commit "$commit" '.commit=$commit' "$lock" >"$temporary"
  mv -- "$temporary" "$lock"
}
