# j3w1zsh — portable shell configuration for native Arch, Arch WSL 2, and Termux
export ZSH="$HOME/.oh-my-zsh"

typeset -U path PATH
path=("$HOME/.local/bin" $path)
export PATH

ZSH_THEME=""
plugins=(git z extract colored-man-pages command-not-found)
(( $+commands[sudo] )) && plugins+=(sudo)

HIST_STAMPS="yyyy-mm-dd"
DISABLE_MAGIC_FUNCTIONS=true
zstyle ':omz:update' mode disabled
DEFAULT_USER="${USERNAME:-${USER:-$(id -un)}}"

source "$ZSH/oh-my-zsh.sh"

settings_file="$HOME/.config/j3w1zsh/settings.zsh"
[[ -r $settings_file ]] && source "$settings_file"
unset settings_file

theme_file="$HOME/.config/j3w1zsh/generated/theme/theme.zsh"
[[ -r $theme_file ]] && source "$theme_file"
unset theme_file

: "${J3W1ZSH_COLOR_FOREGROUND:=#FFF1F1}"
: "${J3W1ZSH_COLOR_BLOOD:=#B00020}"
: "${J3W1ZSH_COLOR_BRIGHT_RED:=#FF334D}"
autoload -Uz vcs_info
setopt prompt_subst
zstyle ':vcs_info:git:*' formats " %F{$J3W1ZSH_COLOR_BLOOD}git:%b%f"
typeset -ga precmd_functions
(( ${precmd_functions[(I)vcs_info]} )) || precmd_functions+=(vcs_info)
typeset J3W1ZSH_PROMPT_IDENTITY=""
[[ -z ${SSH_CONNECTION:-} ]] || J3W1ZSH_PROMPT_IDENTITY="%F{$J3W1ZSH_COLOR_BLOOD}%n@%m%f "
PROMPT='${J3W1ZSH_PROMPT_IDENTITY}%F{${J3W1ZSH_COLOR_FOREGROUND}}%~%f${vcs_info_msg_0_}
%F{${J3W1ZSH_COLOR_BRIGHT_RED}}>%f '

export EDITOR="nvim"
export VISUAL="nvim"

alias ls='ls --color=auto'
alias ll='ls -alF'
alias la='ls -A'
alias grep='grep --color=auto'
alias tree='tree -C --dirsfirst -F'
alias v='nvim'
alias vim='nvim'
alias ta='j3w1zsh attach'
alias tn='j3w1zsh attach --new j3w1zsh'
alias je='j3w1zsh edit'

# Reuse an explicitly selected passphrase-protected GitHub key across shells.
if [[ -n ${J3W1ZSH_GITHUB_KEY:-} && -f $J3W1ZSH_GITHUB_KEY ]]; then
  eval "$(keychain --eval --quiet "$(basename -- "$J3W1ZSH_GITHUB_KEY")")"
fi
