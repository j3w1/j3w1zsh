#!/usr/bin/env bash

readonly J3W1ZSH_FEATURES='["shell","tmux","neovim","github","codex","remote","host-theme","developer-tools","workspace"]'

j3w1zsh_validate_preset() {
  local file="$1"
  jq -e --argjson features "$J3W1ZSH_FEATURES" '
    type == "object" and
    ((keys | sort) == (["$schema","features","id","platforms","schema_version","theme"] | sort)) and
    .schema_version == 1 and
    (.id | type == "string" and test("^[a-z0-9][a-z0-9-]*$")) and
    (.theme | type == "string" and test("^[a-z0-9][a-z0-9-]*$")) and
    (.features | type == "array" and length == (unique | length) and all(. as $f | $features | index($f))) and
    (.platforms | type == "object" and (keys | sort) == ["arch","termux","wsl"]) and
    ([.platforms.arch,.platforms.wsl] | all(
      type == "object" and (keys | sort) == ["npm_global","pacman","pip_user"] and
      all(.[]; type == "array" and length == (unique | length) and all(.[]; type == "string" and test("^[A-Za-z0-9@._+:-]+$")))
    )) and
    (.platforms.termux | type == "object" and (keys | sort) == ["npm_global","pip_user","pkg"] and
      all(.[]; type == "array" and length == (unique | length) and all(.[]; type == "string" and test("^[A-Za-z0-9@._+:-]+$")))
    )
  ' "$file" >/dev/null || j3w1zsh_die "Invalid preset schema: $file"
}

j3w1zsh_resolve_preset() {
  local requested="${1:-j3w1}"
  local path
  case "$requested" in
  j3w1 | minimal) path="$J3W1ZSH_REPO_ROOT/presets/$requested.json" ;;
  *) path="$requested" ;;
  esac
  [[ -f $path && ! -L $path ]] || j3w1zsh_die "Preset is not a regular file: $path"
  path="$(readlink -f -- "$path")"
  j3w1zsh_validate_preset "$path"
  J3W1ZSH_PRESET="$(jq -r .id "$path")"
  J3W1ZSH_THEME="$(jq -r .theme "$path")"
  J3W1ZSH_RESOLVED_PRESET_PATH="$path"
  export J3W1ZSH_PRESET J3W1ZSH_THEME J3W1ZSH_RESOLVED_PRESET_PATH
}

j3w1zsh_preset_has_feature() {
  jq -e --arg feature "$1" '.features | index($feature)' "$J3W1ZSH_RESOLVED_PRESET_PATH" >/dev/null
}

j3w1zsh_preset_json() {
  jq -c . "$J3W1ZSH_RESOLVED_PRESET_PATH"
}
