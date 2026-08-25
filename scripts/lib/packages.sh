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
  [[ ! -f $ledger ]] || existing="$(cat "$ledger")"
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
  temporary="$(mktemp "$J3W1ZSH_STATE_DIR/packages/.provenance.XXXXXX")"
  jq --arg manager "$manager" --arg package "$package" \
    '.packages = [.packages[] | select(.manager != $manager or .package != $package)]' "$ledger" >"$temporary"
  chmod 600 "$temporary"
  mv -- "$temporary" "$ledger"
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

  if ((${#missing[@]})); then
    case "$manager" in
    pacman)
      if [[ ${J3W1ZSH_UPDATE_MODE:-0} == 1 || -f $(j3w1zsh_package_ledger_file) ]]; then
        j3w1zsh_run sudo pacman -S --needed "${missing[@]}"
      else
        j3w1zsh_confirm "Allow pacman to perform a full Arch upgrade and install ${#missing[@]} required packages?" || return 1
        j3w1zsh_run sudo pacman -Syu --needed "${missing[@]}"
      fi
      ;;
    pkg)
      j3w1zsh_confirm "Allow pkg to upgrade Termux and install ${#missing[@]} required packages?" || return 1
      j3w1zsh_run pkg upgrade -y
      j3w1zsh_run pkg install -y "${missing[@]}"
      ;;
    npm_global)
      if [[ $J3W1ZSH_PLATFORM == termux ]]; then
        j3w1zsh_run npm install --global "${missing[@]}"
      else
        j3w1zsh_run sudo npm install --global "${missing[@]}"
      fi
      ;;
    pip_user) j3w1zsh_run python -m pip install --user "${missing[@]}" ;;
    *) j3w1zsh_die "Unsupported package manager: $manager" ;;
    esac
  fi

  local digest index
  digest="${J3W1ZSH_PACKAGE_PLAN_DIGEST:-$(j3w1zsh_plan_digest)}"
  if [[ $J3W1ZSH_DRY_RUN != 1 ]]; then
    for index in "${!packages[@]}"; do
      j3w1zsh_record_package_provenance "$manager" "${packages[$index]}" "${pre_existing[$index]}" "$digest"
    done
  fi
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
