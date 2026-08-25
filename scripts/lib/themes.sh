#!/usr/bin/env bash

j3w1zsh_validate_theme() {
  local file="$1"
  jq -e '
    type == "object" and (keys | sort) == ["ansi","display_name","id","palette","schema_version"] and
    .schema_version == 1 and
    (.id | type == "string" and test("^[a-z0-9][a-z0-9-]*$")) and
    (.display_name | type == "string" and length > 0 and length <= 80) and
    (.palette | type == "object" and (keys | sort) == (["background","foreground","blood","bright_red","selection","muted","orange","blue","semantic_green"] | sort)) and
    (all(.palette[]; type == "string" and test("^#[0-9A-F]{6}$"))) and
    (.ansi | type == "array" and length == 16 and all(.[]; type == "string" and test("^#[0-9A-F]{6}$")))
  ' "$file" >/dev/null || j3w1zsh_die "Invalid declarative theme: $file"
}

j3w1zsh_resolve_theme() {
  local requested="${1:-$J3W1ZSH_THEME}"
  local built_in="$J3W1ZSH_REPO_ROOT/themes/$requested/theme.json"
  local user="$J3W1ZSH_CONFIG_DIR/themes/$requested/theme.json"
  local path
  if [[ -f $requested ]]; then
    path="$requested"
  elif [[ -f $user ]]; then
    path="$user"
  elif [[ -f $built_in ]]; then
    path="$built_in"
  else
    j3w1zsh_die "Theme not found: $requested"
  fi
  [[ ! -L $path ]] || j3w1zsh_die "Theme files must not be symlinks: $path"
  path="$(readlink -f -- "$path")"
  j3w1zsh_validate_theme "$path"
  J3W1ZSH_THEME="$(jq -r .id "$path")"
  J3W1ZSH_RESOLVED_THEME_PATH="$path"
  export J3W1ZSH_THEME J3W1ZSH_RESOLVED_THEME_PATH
}

j3w1zsh_theme_value() {
  jq -r "$1" "$J3W1ZSH_RESOLVED_THEME_PATH"
}

j3w1zsh_render_theme() {
  local output_dir="$J3W1ZSH_CONFIG_DIR/generated/theme"
  j3w1zsh_validate_home_target "$output_dir"
  j3w1zsh_validate_home_target "$output_dir.previous"
  if [[ $J3W1ZSH_DRY_RUN == 1 ]]; then
    j3w1zsh_note "Would render theme $J3W1ZSH_THEME into $output_dir."
    return 0
  fi
  local staging
  mkdir -p "$J3W1ZSH_CONFIG_DIR/generated"
  j3w1zsh_create_ephemeral_dir staging theme-render

  local background foreground blood bright selection muted orange blue green
  background="$(j3w1zsh_theme_value .palette.background)"
  foreground="$(j3w1zsh_theme_value .palette.foreground)"
  blood="$(j3w1zsh_theme_value .palette.blood)"
  bright="$(j3w1zsh_theme_value .palette.bright_red)"
  selection="$(j3w1zsh_theme_value .palette.selection)"
  muted="$(j3w1zsh_theme_value .palette.muted)"
  orange="$(j3w1zsh_theme_value .palette.orange)"
  blue="$(j3w1zsh_theme_value .palette.blue)"
  green="$(j3w1zsh_theme_value .palette.semantic_green)"

  {
    printf "export J3W1ZSH_COLOR_BACKGROUND='%s'\n" "$background"
    printf "export J3W1ZSH_COLOR_FOREGROUND='%s'\n" "$foreground"
    printf "export J3W1ZSH_COLOR_BLOOD='%s'\n" "$blood"
    printf "export J3W1ZSH_COLOR_BRIGHT_RED='%s'\n" "$bright"
  } >"$staging/theme.zsh"
  {
    printf 'set -g status-style "bg=%s,fg=%s"\n' "$background" "$foreground"
    printf 'set -g message-style "bg=%s,fg=%s"\n' "$blood" "$foreground"
    printf 'set -g mode-style "bg=%s,fg=%s"\n' "$selection" "$bright"
    printf 'set -g pane-border-style "fg=%s"\n' "$muted"
    printf 'set -g pane-active-border-style "fg=%s"\n' "$bright"
    printf 'set -g status-left "#[fg=%s,bg=%s,bold] >_ #S "\n' "$foreground" "$blood"
    printf 'setw -g window-status-format "#[fg=%s,bg=%s] #I:#W "\n' "$muted" "$background"
    printf 'setw -g window-status-current-format "#[fg=%s,bg=%s,bold] #I:#W "\n' "$background" "$bright"
    printf 'set -g status-right "#[fg=%s] #{pane_current_path} #[fg=%s,bold] %%H:%%M "\n' "$muted" "$foreground"
  } >"$staging/theme.tmux.conf"
  cat >"$staging/theme.lua" <<EOF
return {
  background = "$background", foreground = "$foreground", blood = "$blood",
  bright_red = "$bright", selection = "$selection", muted = "$muted",
  orange = "$orange", blue = "$blue", semantic_green = "$green",
}
EOF
  jq -c '{name:"j3w1zsh",background:.palette.background,foreground:.palette.foreground,selectionBackground:.palette.selection,cursorColor:.palette.bright_red,black:.ansi[0],red:.ansi[1],green:.ansi[2],yellow:.ansi[3],blue:.ansi[4],purple:.ansi[5],cyan:.ansi[6],white:.ansi[7],brightBlack:.ansi[8],brightRed:.ansi[9],brightGreen:.ansi[10],brightYellow:.ansi[11],brightBlue:.ansi[12],brightPurple:.ansi[13],brightCyan:.ansi[14],brightWhite:.ansi[15]}' \
    "$J3W1ZSH_RESOLVED_THEME_PATH" >"$staging/windows-terminal.json"
  jq -r '.[0] as $root | ["background="+$root.palette.background,"foreground="+$root.palette.foreground,"cursor="+$root.palette.bright_red,"color0="+$root.ansi[0],"color1="+$root.ansi[1],"color2="+$root.ansi[2],"color3="+$root.ansi[3],"color4="+$root.ansi[4],"color5="+$root.ansi[5],"color6="+$root.ansi[6],"color7="+$root.ansi[7],"color8="+$root.ansi[8],"color9="+$root.ansi[9],"color10="+$root.ansi[10],"color11="+$root.ansi[11],"color12="+$root.ansi[12],"color13="+$root.ansi[13],"color14="+$root.ansi[14],"color15="+$root.ansi[15]] | .[]' \
    --slurp "$J3W1ZSH_RESOLVED_THEME_PATH" >"$staging/termux-colors.properties"
  jq -cn --arg id "$J3W1ZSH_THEME" --arg source_sha256 "$(sha256sum "$J3W1ZSH_RESOLVED_THEME_PATH" | awk '{print $1}')" \
    '{schema_version:1,id:$id,source_sha256:$source_sha256}' >"$staging/manifest.json"

  chmod 600 "$staging"/*
  [[ ! -e $output_dir.previous && ! -L $output_dir.previous ]] || rm -r -- "$output_dir.previous"
  [[ ! -e $output_dir && ! -L $output_dir ]] || mv -- "$output_dir" "$output_dir.previous"
  j3w1zsh_promote_ephemeral_dir "$staging" "$output_dir"
  [[ ! -e $output_dir.previous && ! -L $output_dir.previous ]] || rm -r -- "$output_dir.previous"
}

j3w1zsh_theme_list_json() {
  local result='[]' file
  while IFS= read -r file; do
    if j3w1zsh_validate_theme "$file" 2>/dev/null; then
      result="$(jq -cn --argjson result "$result" --argjson theme "$(jq -c '{id,display_name}' "$file")" '$result + [$theme]')"
    fi
  done < <(find "$J3W1ZSH_REPO_ROOT/themes" "$J3W1ZSH_CONFIG_DIR/themes" -mindepth 2 -maxdepth 2 -type f -name theme.json -print 2>/dev/null | LC_ALL=C sort -u)
  printf '%s\n' "$result"
}
