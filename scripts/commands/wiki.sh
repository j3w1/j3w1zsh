#!/usr/bin/env bash

j3w1zsh_wiki_publish_execute() {
  local url="$1" work="$2"
  j3w1zsh_wiki_git clone -q "$url" "$work"
  [[ -z $(git -C "$work" status --short) ]] || j3w1zsh_die "Fresh Wiki checkout is unexpectedly dirty."
  local unexpected file page allowed
  unexpected="$(find "$work" -mindepth 1 -maxdepth 1 ! -name .git -printf '%f\n' | while IFS= read -r file; do
    if [[ -f $work/$file && ! -L $work/$file && $file == *.md ]]; then
      allowed=false
      while IFS= read -r page; do
        if [[ $file == "$(j3w1zsh_wiki_page_file "$page")" ]]; then
          allowed=true
          break
        fi
      done < <(jq -r '.required_pages[]' "$(j3w1zsh_wiki_lock_file)")
      [[ $allowed == true ]] && continue
    fi
    printf '%s\n' "$file"
  done)"
  [[ -z $unexpected ]] || j3w1zsh_die "Wiki contains unexpected entries; preserve and review them before publication: $unexpected"
  while IFS= read -r page; do
    file="$(j3w1zsh_wiki_page_file "$page")"
    install -m 0644 "$J3W1ZSH_REPO_ROOT/wiki/$file" "$work/$file"
  done < <(jq -r '.required_pages[]' "$(j3w1zsh_wiki_lock_file)")
  git -C "$work" add -- '*.md'
  if ! git -C "$work" diff --cached --quiet --; then
    git -C "$work" var GIT_AUTHOR_IDENT >/dev/null 2>&1 || j3w1zsh_die "Wiki publication requires a configured Git author identity."
    git -C "$work" commit -m 'docs: publish j3w1zsh 1.0.0 wiki'
    j3w1zsh_wiki_git -C "$work" push origin HEAD
  fi
  local commit remote_head
  commit="$(git -C "$work" rev-parse HEAD)"
  remote_head="$(j3w1zsh_wiki_git ls-remote "$url" HEAD | awk 'NR==1 {print $1}')"
  [[ $commit == "$remote_head" ]] || j3w1zsh_die "Pushed Wiki commit is not the canonical Wiki HEAD."
  j3w1zsh_wiki_update_lock "$commit"
  printf 'Published Wiki commit: %s\n' "$commit"
  printf 'Updated code lock for review: %s\n' "$J3W1ZSH_REPO_ROOT/wiki-lock.json"
}

j3w1zsh_wiki_publish_command() {
  local dry_run=0
  while (($#)); do case "$1" in --dry-run) dry_run=1 ;; *) j3w1zsh_usage_error "Unknown wiki publish option: $1" ;; esac; shift; done
  j3w1zsh_wiki_validate_contract
  local url
  url="$(j3w1zsh_wiki_url)"
  if [[ $J3W1ZSH_TEST_MODE != 1 ]]; then
    [[ $(gh api user --jq .login) == j3w1 ]] || j3w1zsh_die "Wiki publication requires active GitHub account j3w1."
    [[ $(gh repo view j3w1/j3w1zsh --json viewerPermission --jq .viewerPermission) == ADMIN ]] || j3w1zsh_die "Wiki publication requires repository admin permission."
  fi
  j3w1zsh_wiki_git ls-remote "$url" HEAD >/dev/null 2>&1 || j3w1zsh_die "Canonical Wiki is not initialized. Create the first Home page in the signed-in GitHub UI, then rerun."
  if ((dry_run)); then
    local count
    count="$(jq '.required_pages | length' "$(j3w1zsh_wiki_lock_file)")"
    [[ $J3W1ZSH_OUTPUT_MODE != json ]] || { j3w1zsh_json_envelope wiki-publish ok "$(jq -cn --argjson required_pages "$count" '{dry_run:true,required_pages:$required_pages,wiki_push:false,lock_update:false}')"; return; }
    printf 'Would publish %s reviewed Wiki pages, verify the pushed OID, then update the code lock.\n' "$count"
    return 0
  fi
  j3w1zsh_confirm "Publish the complete reviewed Wiki before merge and prepare the exact code lock update?" || return 0
  j3w1zsh_ensure_dirs
  local work
  work="$J3W1ZSH_STATE_DIR/wiki/publish/$(date +%Y%m%d-%H%M%S-%N)"
  j3w1zsh_plan_reset
  j3w1zsh_plan_add wiki-publish wiki-publish direct-argv-lifecycle wiki git "$work" \
    "fast-forward the reviewed complete Wiki, verify its OID, and update the code lock" false true "" true \
    "the pushed Wiki HEAD is reachable and equals the code lock commit"
  j3w1zsh_execute_typed_callback "${J3W1ZSH_PLAN_ACTIONS[0]}" j3w1zsh_wiki_publish_execute "$url" "$work"
}

j3w1zsh_wiki_command() {
  local subcommand="${1:-help}"
  (($# == 0)) || shift
  case "$subcommand" in
  sync) j3w1zsh_wiki_sync_command "$@" ;;
  status)
    (($# == 0)) || j3w1zsh_usage_error "wiki status accepts no arguments."
    local data; data="$(j3w1zsh_wiki_status_data)"
    [[ $J3W1ZSH_OUTPUT_MODE != json ]] || { j3w1zsh_json_envelope wiki-status ok "$data"; return; }
    jq . <<<"$data"
    ;;
  context) j3w1zsh_wiki_context_command "$@" ;;
  publish) j3w1zsh_wiki_publish_command "$@" ;;
  help | -h | --help) printf 'Usage: j3w1zsh wiki sync [--latest]|status|context TOPIC|publish [--dry-run]\n' ;;
  *) j3w1zsh_usage_error "Unknown wiki command: $subcommand" ;;
  esac
}
