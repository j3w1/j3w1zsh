#!/usr/bin/env bash

j3w1zsh_package_manager_for_platform() {
  case "$J3W1ZSH_PLATFORM" in
  arch | wsl) printf 'pacman\n' ;;
  termux) printf 'pkg\n' ;;
  *) return 1 ;;
  esac
}

j3w1zsh_validate_package_overrides() {
  local file="$1"
  jq -e '
    type == "object" and (keys | sort) == ["additions","exclusions","schema_version"] and
    .schema_version == 1 and
    ([.additions,.exclusions] | all(
      type == "object" and
      (all(keys[]; . == "pacman" or . == "pkg" or . == "npm_global" or . == "pip_user")) and
      all(.[]; type == "array" and length == (unique | length) and all(.[]; type == "string" and test("^[A-Za-z0-9@._+:-]+$")))
    ))
  ' "$file" >/dev/null || j3w1zsh_die "Invalid package override schema: $file"
}

j3w1zsh_package_overrides_file() {
  printf '%s/packages.json\n' "$J3W1ZSH_CONFIG_DIR"
}

j3w1zsh_core_packages_json() {
  case "$J3W1ZSH_PLATFORM:$1" in
  arch:pacman | wsl:pacman | termux:pkg) jq -cn '["bash","coreutils","git","jq"]' ;;
  *) jq -cn '[]' ;;
  esac
}

j3w1zsh_required_packages_json() {
  local manager="$1"
  local required='[]' package
  case "$J3W1ZSH_PLATFORM:$manager" in
  arch:pacman | wsl:pacman | termux:pkg) required="$(j3w1zsh_core_packages_json "$manager")" ;;
  *) printf '[]\n'; return 0 ;;
  esac
  local feature_packages='[]'
  j3w1zsh_preset_has_feature shell && feature_packages="$(jq -cn --argjson value "$feature_packages" '$value + ["curl","zsh"]')"
  j3w1zsh_preset_has_feature tmux && feature_packages="$(jq -cn --argjson value "$feature_packages" '$value + ["fzf","tmux"]')"
  j3w1zsh_preset_has_feature neovim && feature_packages="$(jq -cn --argjson value "$feature_packages" '$value + ["fd","neovim","ripgrep"]')"
  j3w1zsh_preset_has_feature remote && feature_packages="$(jq -cn --argjson value "$feature_packages" '$value + ["openssh"]')"
  j3w1zsh_preset_has_feature host-theme && feature_packages="$(jq -cn --argjson value "$feature_packages" '$value + ["curl"]')"
  j3w1zsh_preset_has_feature workspace && feature_packages="$(jq -cn --argjson value "$feature_packages" '$value + ["git","jq"]')"
  if j3w1zsh_preset_has_feature github; then
    package=github-cli
    [[ $J3W1ZSH_PLATFORM != termux ]] || package=gh
    feature_packages="$(jq -cn --argjson value "$feature_packages" --arg package "$package" '$value + ["openssh",$package]')"
  fi
  if j3w1zsh_preset_has_feature codex && [[ $J3W1ZSH_PLATFORM == wsl ]]; then
    feature_packages="$(jq -cn --argjson value "$feature_packages" '$value + ["curl"]')"
  fi
  jq -cn --argjson required "$required" --argjson features "$feature_packages" '$required + $features | unique | sort'
}

j3w1zsh_packages_for_manager_json() {
  local manager="$1"
  local platform="$J3W1ZSH_PLATFORM"
  local base overrides additions exclusions protected
  base="$(jq -c --arg platform "$platform" --arg manager "$manager" '.platforms[$platform][$manager] // []' "$J3W1ZSH_RESOLVED_PRESET_PATH")"
  overrides="$(j3w1zsh_package_overrides_file)"
  additions='[]'
  exclusions='[]'
  if [[ -f $overrides ]]; then
    [[ ! -L $overrides ]] || j3w1zsh_die "Package overrides must not be a symlink: $overrides"
    j3w1zsh_validate_package_overrides "$overrides"
    additions="$(jq -c --arg manager "$manager" '.additions[$manager] // []' "$overrides")"
    exclusions="$(jq -c --arg manager "$manager" '.exclusions[$manager] // []' "$overrides")"
  fi
  protected="$(j3w1zsh_required_packages_json "$manager")"
  if jq -en --argjson protected "$protected" --argjson exclusions "$exclusions" '$protected - ($protected - $exclusions) | length > 0' >/dev/null; then
    local invalid
    invalid="$(jq -cn --argjson protected "$protected" --argjson exclusions "$exclusions" '$protected - ($protected - $exclusions) | join(", ")')"
    [[ $invalid == '""' ]] || j3w1zsh_die "Package exclusions cannot remove core or selected-feature requirements: ${invalid:1:${#invalid}-2}"
  fi
  jq -cn --argjson base "$base" --argjson additions "$additions" --argjson exclusions "$exclusions" --argjson protected "$protected" \
    '$base + $additions + $protected | unique | . - $exclusions | sort'
}

j3w1zsh_package_declaring_layers_json() {
  local manager="$1" package="$2"
  local explicit_layer="${J3W1ZSH_PACKAGE_LAYER:-}"
  local layers='[]' overrides required core
  if jq -e --arg platform "$J3W1ZSH_PLATFORM" --arg manager "$manager" --arg package "$package" \
    '.platforms[$platform][$manager] // [] | index($package)' "$J3W1ZSH_RESOLVED_PRESET_PATH" >/dev/null; then
    layers="$(jq -cn --argjson layers "$layers" '$layers + ["preset"]')"
  fi
  core="$(j3w1zsh_core_packages_json "$manager")"
  required="$(j3w1zsh_required_packages_json "$manager")"
  if jq -e --arg package "$package" 'index($package)' <<<"$core" >/dev/null; then
    layers="$(jq -cn --argjson layers "$layers" '$layers + ["core"]')"
  elif jq -e --arg package "$package" 'index($package)' <<<"$required" >/dev/null; then
    layers="$(jq -cn --argjson layers "$layers" '$layers + ["preset"]')"
  fi
  overrides="$(j3w1zsh_package_overrides_file)"
  if [[ -f $overrides ]] && jq -e --arg manager "$manager" --arg package "$package" '.additions[$manager] // [] | index($package)' "$overrides" >/dev/null; then
    layers="$(jq -cn --argjson layers "$layers" '$layers + ["user"]')"
  fi
  [[ -z $explicit_layer ]] || layers="$(jq -cn --argjson layers "$layers" --arg layer "$explicit_layer" '$layers + [$layer]')"
  jq -cn --argjson layers "$layers" '$layers | unique | sort'
}

j3w1zsh_package_is_installed() {
  local manager="$1"
  local package="$2"
  case "$manager" in
  pacman) pacman -Q -- "$package" >/dev/null 2>&1 ;;
  pkg) dpkg-query -W -f='${Status}' -- "$package" 2>/dev/null | grep -q 'install ok installed' ;;
  npm_global) npm list --global --depth=0 -- "$package" >/dev/null 2>&1 ;;
  pip_user) python -m pip show -- "$package" >/dev/null 2>&1 ;;
  *) return 1 ;;
  esac
}

j3w1zsh_package_ledger_file() {
  printf '%s/packages/provenance.json\n' "$J3W1ZSH_STATE_DIR"
}

j3w1zsh_validate_package_state_directory() {
  local directory="$1" resolved_home resolved_directory
  [[ -d $directory && ! -L $directory ]] || j3w1zsh_die "Package state directory must be a regular non-symlink directory: $directory" \
    "$J3W1ZSH_EXIT_PROTECTED" invalid_package_provenance
  resolved_home="$(readlink -f -- "$HOME")"
  resolved_directory="$(readlink -f -- "$directory")"
  case "$resolved_directory" in
  "$resolved_home" | "$resolved_home"/*) ;;
  *) j3w1zsh_die "Package state resolves outside HOME; preserving it for owner review: $directory" \
    "$J3W1ZSH_EXIT_PROTECTED" invalid_package_provenance ;;
  esac
}

j3w1zsh_validate_package_ledger() {
  local ledger="$1"
  j3w1zsh_validate_package_state_directory "$(dirname -- "$ledger")"
  [[ -f $ledger && ! -L $ledger ]] || j3w1zsh_die "Package provenance must be a regular non-symlink file: $ledger" "$J3W1ZSH_EXIT_PROTECTED" invalid_package_provenance
  jq -e '
    type == "object" and (keys | sort) == ["packages","schema_version"] and .schema_version == 1 and
    (.packages | type == "array" and
      ((map([.manager,.package]) | length) == (map([.manager,.package]) | unique | length)) and
      all(.[];
        type == "object" and
        (keys | sort) == (["declaring_layers","first_seen_product_version","installed_by_j3w1zsh","last_required_plan_digest","manager","package","pre_existing"] | sort) and
        (.manager == "pacman" or .manager == "pkg" or .manager == "npm_global" or .manager == "pip_user") and
        (.package | type == "string" and test("^[A-Za-z0-9@._+:-]+$")) and
        (.declaring_layers | type == "array" and length == (unique | length) and all(.[]; . == "core" or . == "preset" or . == "user" or . == "workspace")) and
        (.pre_existing | type == "boolean") and (.installed_by_j3w1zsh | type == "boolean") and
        (.first_seen_product_version | type == "string" and length > 0) and
        (.last_required_plan_digest | type == "string" and test("^[0-9a-f]{64}$"))
      )
    )
  ' "$ledger" >/dev/null || j3w1zsh_die "Package provenance failed strict validation: $ledger" "$J3W1ZSH_EXIT_PROTECTED" invalid_package_provenance
}

j3w1zsh_pacman_collision_root() {
  if [[ $J3W1ZSH_TEST_MODE == 1 && -n ${J3W1ZSH_TEST_SYSTEM_ROOT:-} ]]; then
    [[ $J3W1ZSH_TEST_SYSTEM_ROOT == /* ]] || j3w1zsh_die "Test system root must be absolute."
    printf '%s\n' "${J3W1ZSH_TEST_SYSTEM_ROOT%/}"
  else
    printf '/\n'
  fi
}

j3w1zsh_pacman_path_owner() {
  pacman -Qqo -- "$1" 2>/dev/null
}

j3w1zsh_guard_pacman_pnpm_collision() {
  local root bin_dir pnpm_link pnpx_link pnpm_target pnpx_target checkpoint
  local resolved_pnpm resolved_pnpx pnpm_owner="" pnpx_owner="" pnpm_path_owner="" pnpx_path_owner=""
  root="$(j3w1zsh_pacman_collision_root)"
  bin_dir="${root%/}/usr/bin"
  pnpm_link="$bin_dir/pnpm"
  pnpx_link="$bin_dir/pnpx"
  pnpm_target="${root%/}/usr/lib/node_modules/corepack/dist/pnpm.js"
  pnpx_target="${root%/}/usr/lib/node_modules/corepack/dist/pnpx.js"
  checkpoint=pacman-pnpm-corepack-collision

  if [[ ! -e $pnpm_link && ! -L $pnpm_link && ! -e $pnpx_link && ! -L $pnpx_link ]]; then
    j3w1zsh_clear_manual "$checkpoint"
    return 0
  fi

  resolved_pnpm="$(readlink -f -- "$pnpm_link" 2>/dev/null || true)"
  resolved_pnpx="$(readlink -f -- "$pnpx_link" 2>/dev/null || true)"
  pnpm_path_owner="$(j3w1zsh_pacman_path_owner "$pnpm_link" || true)"
  pnpx_path_owner="$(j3w1zsh_pacman_path_owner "$pnpx_link" || true)"
  if [[ $pnpm_path_owner == pnpm && $pnpx_path_owner == pnpm ]] && pacman -Q -- pnpm >/dev/null 2>&1; then
    j3w1zsh_clear_manual "$checkpoint"
    return 0
  fi
  pnpm_owner="$(j3w1zsh_pacman_path_owner "$pnpm_target" || true)"
  pnpx_owner="$(j3w1zsh_pacman_path_owner "$pnpx_target" || true)"
  if [[ -L $pnpm_link && -L $pnpx_link && $resolved_pnpm == "$pnpm_target" && $resolved_pnpx == "$pnpx_target" &&
    $pnpm_owner == corepack && $pnpx_owner == corepack ]] &&
    pacman -Q -- corepack >/dev/null 2>&1 &&
    ! j3w1zsh_pacman_path_owner "$pnpm_link" >/dev/null 2>&1 &&
    ! j3w1zsh_pacman_path_owner "$pnpx_link" >/dev/null 2>&1; then
    j3w1zsh_warn "Pacman pnpm is blocked by the exact Corepack shims at /usr/bin/pnpm and /usr/bin/pnpx."
    j3w1zsh_note "Pacman owns both resolved shim targets through package corepack; Pacman does not own the two shim paths."
    j3w1zsh_note "No shim was overwritten or removed. After owner review, run: sudo corepack disable pnpm --install-directory /usr/bin"
    j3w1zsh_note "Then verify both shim paths are absent and rerun phase 20."
    j3w1zsh_mark_manual_pending "$checkpoint" \
      "Review the exact Corepack/Pacman pnpm ownership evidence, remove only the Corepack pnpm shims with the displayed direct command, verify both paths are absent, and rerun phase 20."
    return "$J3W1ZSH_EXIT_CHECKPOINT"
  fi

  j3w1zsh_die "Pacman pnpm is blocked by existing /usr/bin/pnpm or /usr/bin/pnpx content that does not match the exact Corepack-owned shim contract. No path was changed." \
    "$J3W1ZSH_EXIT_PROTECTED" ambiguous_package_collision
}

j3w1zsh_record_package_provenance() {
  local manager="$1"
  local package="$2"
  local pre_existing="$3"
  local digest="$4"
  [[ $J3W1ZSH_DRY_RUN == 1 ]] && return 0
  j3w1zsh_ensure_dirs
  local ledger temporary existing installed_by declaring_layers
  ledger="$(j3w1zsh_package_ledger_file)"
  existing='{"schema_version":1,"packages":[]}'
  if [[ -e $ledger || -L $ledger ]]; then
    j3w1zsh_validate_package_ledger "$ledger"
    existing="$(cat "$ledger")"
  fi
  installed_by=true
  [[ $pre_existing == false ]] || installed_by=false
  declaring_layers="$(j3w1zsh_package_declaring_layers_json "$manager" "$package")"
  temporary="$(mktemp "$J3W1ZSH_STATE_DIR/packages/.provenance.XXXXXX")"
  jq -c \
    --arg manager "$manager" \
    --arg package "$package" \
    --arg version "$J3W1ZSH_VERSION" \
    --arg digest "$digest" \
    --argjson declaring_layers "$declaring_layers" \
    --argjson pre_existing "$pre_existing" \
    --argjson installed_by "$installed_by" '
      ([.packages[] | select(.manager == $manager and .package == $package)][0] // null) as $previous |
      .packages = ([.packages[] | select(.manager != $manager or .package != $package)] + [{
        manager:$manager,
        package:$package,
        declaring_layers:$declaring_layers,
        pre_existing:(if $previous == null then $pre_existing else $previous.pre_existing end),
        installed_by_j3w1zsh:(if $previous == null then $installed_by else $previous.installed_by_j3w1zsh end),
        first_seen_product_version:($previous.first_seen_product_version // $version),
        last_required_plan_digest:$digest
      }] | sort_by(.manager,.package))
    ' <<<"$existing" >"$temporary"
  chmod 600 "$temporary"
  mv -- "$temporary" "$ledger"
}

j3w1zsh_forget_package_provenance() {
  local manager="$1" package="$2" ledger temporary
  ledger="$(j3w1zsh_package_ledger_file)"
  [[ -f $ledger ]] || return 0
  j3w1zsh_validate_package_ledger "$ledger"
  temporary="$(mktemp "$J3W1ZSH_STATE_DIR/packages/.provenance.XXXXXX")"
  jq --arg manager "$manager" --arg package "$package" \
    '.packages = [.packages[] | select(.manager != $manager or .package != $package)]' "$ledger" >"$temporary"
  chmod 600 "$temporary"
  mv -- "$temporary" "$ledger"
}

j3w1zsh_package_repair_candidates_json() {
  local manager="$1"
  shift
  local ledger package record result='[]'
  ledger="$(j3w1zsh_package_ledger_file)"
  j3w1zsh_validate_package_ledger "$ledger"
  for package in "$@"; do
    record="$(jq -c --arg manager "$manager" --arg package "$package" \
      '[.packages[] | select(.manager == $manager and .package == $package)] | if length == 1 then .[0] else empty end' "$ledger")"
    [[ -n $record ]] || j3w1zsh_die "No unique provenance record exists for $manager package $package; preserving state for owner review." \
      "$J3W1ZSH_EXIT_PROTECTED" provenance_repair_not_applicable
    jq -e '.pre_existing == false and .installed_by_j3w1zsh == true' <<<"$record" >/dev/null ||
      j3w1zsh_die "The provenance record for $manager package $package is not an install-ownership claim; preserving it." \
        "$J3W1ZSH_EXIT_PROTECTED" provenance_repair_not_applicable
    if j3w1zsh_package_is_installed "$manager" "$package"; then
      j3w1zsh_die "Package manager $manager currently verifies $package as installed; preserving its provenance." \
        "$J3W1ZSH_EXIT_PROTECTED" package_currently_installed
    fi
    result="$(jq -cn --argjson result "$result" --argjson record "$record" \
      '$result + [{manager:$record.manager,package:$record.package,manager_verified_installed:false,removed_record:$record,reason:"ledger claims j3w1zsh ownership but the exact package manager reports the package absent"}]')"
  done
  jq -cn --argjson result "$result" '$result | sort_by(.manager,.package)'
}

j3w1zsh_package_repair_provenance_execute() {
  local candidates="$1" ledger marker repairs_dir stamp evidence temporary_ledger temporary_evidence
  local current_candidates phase_record=null ledger_digest
  local repair_packages=()
  ledger="$(j3w1zsh_package_ledger_file)"
  marker="$(j3w1zsh_phase_marker 20-packages)"
  repairs_dir="$J3W1ZSH_STATE_DIR/packages/repairs"

  # Revalidate package-manager and ledger projections immediately before the
  # first state mutation. A changed or ambiguous record is never overwritten.
  local manager
  manager="$(jq -r '.[0].manager' <<<"$candidates")"
  mapfile -t repair_packages < <(jq -r '.[].package' <<<"$candidates")
  current_candidates="$(j3w1zsh_package_repair_candidates_json "$manager" "${repair_packages[@]}")"
  [[ $(jq -S -c . <<<"$current_candidates") == "$(jq -S -c . <<<"$candidates")" ]] ||
    j3w1zsh_die "Package provenance changed during repair planning; preserving it for owner review." \
      "$J3W1ZSH_EXIT_PROTECTED" provenance_repair_changed
  ledger_digest="$(sha256sum "$ledger" | awk '{print $1}')"

  if [[ -e $marker || -L $marker ]]; then
    j3w1zsh_validate_package_state_directory "$(dirname -- "$marker")"
    [[ -f $marker && ! -L $marker ]] || j3w1zsh_die "Phase 20 marker is not a regular file; preserving it for owner review." \
      "$J3W1ZSH_EXIT_PROTECTED" invalid_phase_marker
    phase_record="$(jq -c . "$marker")"
  fi

  j3w1zsh_ensure_dirs
  if [[ -e $repairs_dir || -L $repairs_dir ]]; then
    j3w1zsh_validate_package_state_directory "$repairs_dir"
  else
    mkdir -- "$repairs_dir"
  fi
  chmod 700 "$repairs_dir"
  stamp="$(date -u +%Y%m%dT%H%M%S)-$$"
  evidence="$repairs_dir/$stamp.json"
  [[ ! -e $evidence && ! -L $evidence ]] || j3w1zsh_die "Package provenance repair evidence already exists: $evidence"
  temporary_ledger="$(mktemp "$J3W1ZSH_STATE_DIR/packages/.provenance-repair.XXXXXX")"
  temporary_evidence="$(mktemp "$repairs_dir/.repair-evidence.XXXXXX")"

  jq -c --argjson candidates "$candidates" '
    reduce $candidates[] as $candidate (.;
      .packages = [.packages[] | select(.manager != $candidate.manager or .package != $candidate.package)]
    )
  ' "$ledger" >"$temporary_ledger"
  j3w1zsh_validate_package_ledger "$temporary_ledger"
  jq -cn \
    --arg recorded_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg verified_commit "$(j3w1zsh_repo_commit)" \
    --argjson candidates "$candidates" \
    --argjson invalidated_phase_marker "$phase_record" \
    '{schema_version:1,operation:"package-provenance-repair",recorded_at:$recorded_at,verified_commit:$verified_commit,removed_records:[$candidates[].removed_record],manager_verification:[$candidates[] | {manager,package,installed:.manager_verified_installed}],invalidated_phase_marker:$invalidated_phase_marker}' \
    >"$temporary_evidence"
  chmod 600 "$temporary_ledger" "$temporary_evidence"

  [[ $(sha256sum "$ledger" | awk '{print $1}') == "$ledger_digest" ]] ||
    j3w1zsh_die "Package provenance changed before repair commit; preserving it for owner review." \
      "$J3W1ZSH_EXIT_PROTECTED" provenance_repair_changed
  local package
  for package in "${repair_packages[@]}"; do
    ! j3w1zsh_package_is_installed "$manager" "$package" ||
      j3w1zsh_die "Package manager $manager began reporting $package as installed before repair commit; preserving its provenance." \
        "$J3W1ZSH_EXIT_PROTECTED" package_currently_installed
  done
  if [[ $phase_record != null ]]; then
    [[ -f $marker && ! -L $marker && $(jq -S -c . "$marker") == "$(jq -S -c . <<<"$phase_record")" ]] ||
      j3w1zsh_die "Phase 20 marker changed before repair commit; preserving it for owner review." \
        "$J3W1ZSH_EXIT_PROTECTED" invalid_phase_marker
  fi

  # Evidence becomes durable before the safe invalidation. If a later atomic
  # ledger replacement fails, phase 20 remains pending and the original false
  # ledger can be repaired by rerunning the same bounded command.
  mv -- "$temporary_evidence" "$evidence"
  [[ ! -e $marker ]] || rm -- "$marker"
  mv -- "$temporary_ledger" "$ledger"
  J3W1ZSH_PROVENANCE_REPAIR_EVIDENCE="$evidence"
  export J3W1ZSH_PROVENANCE_REPAIR_EVIDENCE
}

j3w1zsh_install_package_set() {
  local manager="$1"
  local packages_json="$2"
  local packages=()
  mapfile -t packages < <(jq -r '.[]' <<<"$packages_json")
  ((${#packages[@]})) || return 0

  local missing=() pre_existing=() package
  for package in "${packages[@]}"; do
    if j3w1zsh_package_is_installed "$manager" "$package"; then
      pre_existing+=(true)
    else
      pre_existing+=(false)
      missing+=("$package")
    fi
  done

  if [[ $J3W1ZSH_NO_PACKAGES == 1 ]]; then
    if ((${#missing[@]})); then
      j3w1zsh_warn "Missing $manager prerequisites (not installed): ${missing[*]}"
    fi
    return 0
  fi

  local refresh="${J3W1ZSH_PACKAGE_REFRESH:-0}"
  local transaction_packages=()
  if [[ $refresh == 1 ]]; then
    transaction_packages=("${packages[@]}")
  else
    transaction_packages=("${missing[@]}")
  fi

  if ((${#transaction_packages[@]})); then
    if [[ $manager == pacman && " ${transaction_packages[*]} " == *" pnpm "* ]]; then
      j3w1zsh_guard_pacman_pnpm_collision
    fi
    case "$manager" in
    pacman)
      if [[ $refresh == 1 ]]; then
        j3w1zsh_confirm "Allow pacman to refresh the Arch keyring, perform a coherent full upgrade, and refresh ${#packages[@]} selected packages?" || return 1
        # Arch's supported stale-keyring recovery is one fail-closed sequence:
        # synchronize and reconcile the keyring first, then immediately perform
        # the full upgrade with every selected target. A failure in either
        # transaction returns before verification, provenance, or phase marking.
        j3w1zsh_run sudo pacman -Sy --needed archlinux-keyring || return $?
        j3w1zsh_run sudo pacman -Su --needed "${packages[@]}" || return $?
      else
        j3w1zsh_run sudo pacman -S --needed "${missing[@]}" || return $?
      fi
      ;;
    pkg)
      if [[ $refresh == 1 ]]; then
        j3w1zsh_confirm "Allow pkg to upgrade Termux and refresh ${#packages[@]} selected packages?" || return 1
        j3w1zsh_run pkg upgrade -y || return $?
        j3w1zsh_run pkg install -y "${packages[@]}" || return $?
      else
        j3w1zsh_confirm "Allow pkg to install ${#missing[@]} newly required packages without a full Termux upgrade?" || return 1
        j3w1zsh_run pkg install -y "${missing[@]}" || return $?
      fi
      ;;
    npm_global)
      if [[ $J3W1ZSH_PLATFORM == termux ]]; then
        j3w1zsh_run npm install --global "${transaction_packages[@]}" || return $?
      else
        j3w1zsh_run sudo npm install --global "${transaction_packages[@]}" || return $?
      fi
      ;;
    pip_user)
      if [[ $refresh == 1 ]]; then
        j3w1zsh_run python -m pip install --user --upgrade "${packages[@]}" || return $?
      else
        j3w1zsh_run python -m pip install --user "${missing[@]}" || return $?
      fi
      ;;
    *) j3w1zsh_die "Unsupported package manager: $manager" ;;
    esac
  fi

  [[ $J3W1ZSH_DRY_RUN != 1 ]] || return 0
  for package in "${packages[@]}"; do
    j3w1zsh_package_is_installed "$manager" "$package" ||
      j3w1zsh_die "Package manager $manager did not verify the required package after reconciliation: $package" \
        "$J3W1ZSH_EXIT_FAILURE" package_verification_failed
  done

  local digest index
  digest="${J3W1ZSH_PACKAGE_PLAN_DIGEST:-$(j3w1zsh_plan_digest)}"
  for index in "${!packages[@]}"; do
    j3w1zsh_record_package_provenance "$manager" "${packages[$index]}" "${pre_existing[$index]}" "$digest"
  done
}

j3w1zsh_packages_status_json() {
  local manager packages_json package
  manager="$(j3w1zsh_package_manager_for_platform)"
  packages_json="$(j3w1zsh_packages_for_manager_json "$manager")"
  local result='[]'
  while IFS= read -r package; do
    local installed=false
    j3w1zsh_package_is_installed "$manager" "$package" && installed=true
    result="$(jq -cn --argjson result "$result" --arg manager "$manager" --arg package "$package" --argjson installed "$installed" '$result + [{manager:$manager,package:$package,installed:$installed}]')"
  done < <(jq -r '.[]' <<<"$packages_json")
  printf '%s\n' "$result"
}

j3w1zsh_packages_prune_candidates_json() {
  local ledger
  ledger="$(j3w1zsh_package_ledger_file)"
  [[ -f $ledger ]] || { printf '[]\n'; return 0; }
  local manager active workspace_active workspace_state package result='[]'
  for manager in pacman pkg npm_global pip_user; do
    active="$(j3w1zsh_packages_for_manager_json "$manager" 2>/dev/null || printf '[]')"
    workspace_state=ok
    if ! workspace_active="$(j3w1zsh_active_workspace_packages_json "$manager")"; then
      workspace_state=ambiguous
      workspace_active='[]'
    fi
    active="$(jq -cn --argjson base "$active" --argjson workspace "$workspace_active" '$base + $workspace | unique | sort')"
    while IFS= read -r package; do
      if [[ $workspace_state == ambiguous ]] && jq -e --arg manager "$manager" --arg package "$package" \
        '.packages[] | select(.manager == $manager and .package == $package) | .declaring_layers | index("workspace")' "$ledger" >/dev/null; then
        continue
      fi
      if ! jq -e --arg package "$package" 'index($package)' <<<"$active" >/dev/null && j3w1zsh_package_is_installed "$manager" "$package"; then
        result="$(jq -cn --argjson result "$result" --arg manager "$manager" --arg package "$package" '$result + [{manager:$manager,package:$package,reason:"installed by j3w1zsh and no active layer declares it"}]')"
      fi
    done < <(jq -r --arg manager "$manager" '.packages[] | select(.manager == $manager and .installed_by_j3w1zsh == true and .pre_existing == false) | .package' "$ledger")
  done
  printf '%s\n' "$result"
}

j3w1zsh_active_workspace_packages_json() {
  local manager="$1" active="$J3W1ZSH_STATE_DIR/workspaces/active.json"
  [[ -e $active || -L $active ]] || { printf '[]\n'; return 0; }
  [[ -f $active && ! -L $active ]] || return 2
  local manifest digest platform actual_digest
  manifest="$(jq -er '.manifest | select(type == "string" and length > 0)' "$active" 2>/dev/null)" || return 2
  digest="$(jq -er '.manifest_sha256 | select(type == "string" and test("^[0-9a-f]{64}$"))' "$active" 2>/dev/null)" || return 2
  platform="$(jq -er '.platform | select(type == "string")' "$active" 2>/dev/null)" || return 2
  [[ $platform == "$J3W1ZSH_PLATFORM" && -f $manifest && ! -L $manifest ]] || return 2
  actual_digest="$(sha256sum "$manifest" | awk '{print $1}')"
  [[ $actual_digest == "$digest" ]] || return 2
  jq -e --arg platform "$platform" --arg manager "$manager" \
    '.schema_version == 2 and (.targets[$platform].packages[$manager] | type == "array")' "$manifest" >/dev/null 2>&1 || return 2
  jq -c --arg platform "$platform" --arg manager "$manager" '.targets[$platform].packages[$manager] | unique | sort' "$manifest"
}
