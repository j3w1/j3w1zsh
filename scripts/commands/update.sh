#!/usr/bin/env bash

j3w1zsh_update_selected_preset() {
  local marker="$J3W1ZSH_STATE_DIR/phases/00-preflight.json"
  if [[ -f $marker ]]; then
    jq -r 'if (.preset_source // "") != "" then .preset_source else (.preset // "j3w1") end' "$marker"
  else
    printf 'j3w1\n'
  fi
}

j3w1zsh_update_selected_theme() {
  local manifest="$J3W1ZSH_CONFIG_DIR/generated/theme/manifest.json"
  local marker="$J3W1ZSH_STATE_DIR/phases/00-preflight.json"
  if [[ -f $manifest ]] && jq -e '.schema_version == 1 and (.id | type == "string" and length > 0)' "$manifest" >/dev/null 2>&1; then
    jq -r .id "$manifest"
  elif [[ -f $marker ]]; then
    jq -r 'if (.theme_source // "") != "" then .theme_source else (.theme // "j3w1zsh") end' "$marker"
  else
    printf 'j3w1zsh\n'
  fi
}

j3w1zsh_update_execute() {
  local identity="$1" old_canonical="$2" canonical="$3" classification="$4"
  shift 4
  if [[ $identity == old-canonical ]]; then
    j3w1zsh_git_verify_old_redirect_identity "$old_canonical" "$canonical"
    git -C "$J3W1ZSH_REPO_ROOT" remote set-url origin "$canonical"
    classification="$(j3w1zsh_git_classify_repository)"
  fi
  local tracking_remote tracking_ref counts ahead
  tracking_remote="$(jq -r .tracking_remote <<<"$classification")"
  tracking_ref="$(jq -r .tracking_ref <<<"$classification")"
  git -C "$J3W1ZSH_REPO_ROOT" fetch --prune "$tracking_remote"
  counts="$(git -C "$J3W1ZSH_REPO_ROOT" rev-list --left-right --count "HEAD...$tracking_ref")"
  read -r ahead _ <<<"$counts"
  ((ahead == 0)) || j3w1zsh_die "Current branch became ahead or divergent after fetch." "$J3W1ZSH_EXIT_PROTECTED" protected_history
  git -C "$J3W1ZSH_REPO_ROOT" merge --ff-only "$tracking_ref"
  [[ -z $(j3w1zsh_git_checkout_status) ]] || j3w1zsh_git_protected_stop "$(j3w1zsh_git_checkout_status)"
  exec env J3W1ZSH_UPDATE_AFTER_PULL=1 "$J3W1ZSH_REPO_ROOT/bin/j3w1zsh" update "$@"
}

j3w1zsh_update_add_upstream() {
  git -C "$J3W1ZSH_REPO_ROOT" remote add upstream "$1"
}

j3w1zsh_update_command() {
  local configure_upstream=0 arguments=("$@")
  while (($#)); do
    case "$1" in
    --dry-run) J3W1ZSH_DRY_RUN=1 ;;
    --yes) J3W1ZSH_ASSUME_YES=1 ;;
    --configure-upstream) configure_upstream=1 ;;
    wiki)
      (($# == 1)) || j3w1zsh_usage_error "update wiki accepts no additional arguments."
      j3w1zsh_wiki_sync_command
      return
      ;;
    -h | --help) printf 'Usage: j3w1zsh update [--dry-run] [--yes] [--configure-upstream]\n       j3w1zsh update wiki\n'; return ;;
    *) j3w1zsh_usage_error "Unknown update option: $1" ;;
    esac
    shift
  done
  export J3W1ZSH_DRY_RUN J3W1ZSH_ASSUME_YES
  if [[ ${J3W1ZSH_UPDATE_AFTER_PULL:-0} == 1 ]]; then
    [[ -z $(j3w1zsh_git_checkout_status) ]] || j3w1zsh_git_protected_stop "$(j3w1zsh_git_checkout_status)"
    local preset theme
    preset="$(j3w1zsh_update_selected_preset)"
    theme="$(j3w1zsh_update_selected_theme)"
    local install_arguments=(--preset "$preset" --theme "$theme" --force --from 20-packages)
    [[ $J3W1ZSH_ASSUME_YES != 1 ]] || install_arguments+=(--yes)
    j3w1zsh_install_command_mode update "${install_arguments[@]}"
    if [[ -f $J3W1ZSH_STATE_DIR/workspaces/active.json ]]; then
      j3w1zsh_note "Active workspace state (lifecycle was not run):"
      j3w1zsh_workspace_status_command
    fi
    return 0
  fi

  j3w1zsh_git_prepare_checkout
  local classification identity canonical old_canonical upstream_url upstream_name="" remote_oid relation data
  classification="$(j3w1zsh_git_classify_repository)"
  identity="$(jq -r .identity <<<"$classification")"
  canonical="$(j3w1zsh_git_canonical_url)"; old_canonical="$(j3w1zsh_legacy_canonical_url)"

  if [[ $identity == fork ]]; then
    if git -C "$J3W1ZSH_REPO_ROOT" remote get-url upstream >/dev/null 2>&1; then
      upstream_url="$(git -C "$J3W1ZSH_REPO_ROOT" remote get-url upstream)"
      j3w1zsh_git_is_url "$upstream_url" "$canonical" || j3w1zsh_die "Existing upstream remote is not canonical; preserving it for owner review." "$J3W1ZSH_EXIT_PROTECTED" noncanonical_upstream
      upstream_name=upstream
    elif ((configure_upstream)); then
      upstream_url="$canonical"
      upstream_name=upstream
      if [[ $J3W1ZSH_DRY_RUN != 1 ]]; then
        j3w1zsh_confirm "Add canonical upstream without changing fork origin?" || return 0
        j3w1zsh_plan_reset
        j3w1zsh_plan_add configure-upstream update direct-argv-lifecycle update git "$J3W1ZSH_REPO_ROOT/.git/config" \
          "add the verified canonical upstream without changing fork origin" false true "" true \
          "origin is unchanged and upstream equals the canonical repository"
        j3w1zsh_execute_typed_callback "${J3W1ZSH_PLAN_ACTIONS[0]}" j3w1zsh_update_add_upstream "$canonical"
      fi
    else
      j3w1zsh_warn "Fork has no canonical upstream. Re-run with --configure-upstream to add it without changing origin."
    fi
  else
    upstream_name="$(jq -r .tracking_remote <<<"$classification")"
    upstream_url="$(jq -r .tracking_url <<<"$classification")"
  fi

  local tracking_url tracking_branch
  tracking_url="$(jq -r .tracking_url <<<"$classification")"
  tracking_branch="$(jq -r .tracking_branch <<<"$classification")"
  remote_oid="$(j3w1zsh_git_remote_branch_oid "$tracking_url" "$tracking_branch")"
  [[ -n $remote_oid ]] || j3w1zsh_die "Tracked remote branch is unreachable: $tracking_branch"
  relation="$(j3w1zsh_git_relation "$tracking_url" "refs/heads/$tracking_branch" "$remote_oid")"

  local canonical_relation=null canonical_oid=""
  if [[ $identity == fork && -n $upstream_name ]]; then
    canonical_oid="$(j3w1zsh_git_remote_branch_oid "$upstream_url" main)"
    [[ -z $canonical_oid ]] || canonical_relation="$(j3w1zsh_git_relation "$upstream_url" refs/heads/main "$canonical_oid")"
  fi
  data="$(jq -cn --argjson repository "$classification" --argjson tracking_relation "$relation" --argjson canonical_relation "$canonical_relation" --arg canonical_url "$canonical" --arg upstream_name "$upstream_name" '{repository:$repository,tracking_relation:$tracking_relation,canonical_relation:$canonical_relation,canonical_url:$canonical_url,upstream_remote:(if $upstream_name=="" then null else $upstream_name end)}')"

  if [[ $J3W1ZSH_DRY_RUN == 1 ]]; then
    if [[ $J3W1ZSH_OUTPUT_MODE == json ]]; then
      j3w1zsh_json_envelope update ok "$(jq -cn --argjson data "$data" '$data + {dry_run:true,local_refs_changed:false}')"
    else
      jq -r '"Repository: " + .repository.identity + "\nBranch/upstream: " + .repository.branch + " -> " + .repository.tracking_ref + "\nTracking ahead/behind: " + (.tracking_relation.ahead|tostring) + "/" + (.tracking_relation.behind|tostring) + (if .canonical_relation == null then "" else "\nCanonical ahead/behind: " + (.canonical_relation.ahead|tostring) + "/" + (.canonical_relation.behind|tostring) end)' <<<"$data"
      j3w1zsh_log "Update preview complete; git ls-remote and disposable comparison changed no local refs."
    fi
    return 0
  fi

  if [[ $(jq -r '.tracking_relation.ahead' <<<"$data") != 0 || $(jq -r '.tracking_relation.diverged' <<<"$data") == true ]]; then
    j3w1zsh_die "Current branch is ahead or divergent; preserving unique commits for owner review." "$J3W1ZSH_EXIT_PROTECTED" protected_history
  fi
  j3w1zsh_plan_reset
  j3w1zsh_plan_add update-fast-forward update direct-argv-lifecycle update git "$J3W1ZSH_REPO_ROOT" \
    "fetch the tracked remote, fast-forward only, and relaunch the fresh executable" false false "" true \
    "HEAD equals the verified tracked remote and the checkout remains clean"
  j3w1zsh_execute_typed_callback "${J3W1ZSH_PLAN_ACTIONS[0]}" j3w1zsh_update_execute \
    "$identity" "$old_canonical" "$canonical" "$classification" "${arguments[@]}"
}
