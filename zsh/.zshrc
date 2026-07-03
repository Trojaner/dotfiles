export LANG=en_US.UTF-8
ZDOTDIR="$HOME/.zsh"

[[ -f "$HOME/.local/bin/env" ]] && . "$HOME/.local/bin/env"

source "$ZDOTDIR/common_functions.sh"

if [ -f "$ZDOTDIR/.zsh_secrets.sh" ]; then
  source "$ZDOTDIR/.zsh_secrets.sh"
fi

# zsh settings
zstyle ':antidote:compatibility-mode' 'antibody' 'on'
zstyle ':omz:update' mode auto
zstyle ':omz:update' frequency 7

source "$ZDOTDIR/.antidote/antidote.zsh"

setopt EXTENDED_HISTORY
setopt INC_APPEND_HISTORY_TIME
setopt HIST_FIND_NO_DUPS
setopt HIST_LEX_WORDS
setopt EXTENDED_GLOB
setopt GLOB_DOTS
setopt NO_HUP

# oh-my-zsh settings
export ZSH_DISABLE_COMPFIX=true
export ZSH=$(antidote path ohmyzsh/ohmyzsh)
export ZSH_AUTOSUGGEST_STRATEGY=(histdb_top_here completion)
export ZSH_TAB_TITLE_DEFAULT_DISABLE_PREFIX=false
export ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=20
export ZSH_AUTOSUGGEST_USE_ASYNC=1
export ZSH_TAB_TITLE_PREFIX='$USER@$HOST - '
export ZSH_THEME="cloud"
export ZSH_TMUX_UNICODE=true
export ZSH_COPILOT_AI_PROVIDER="openai"
export ZSH_COPILOT_KEY="^g"
export ZSH_COPILOT_DEBUG="true"
export COMPLETION_WAITING_DOTS="true"
export DISABLE_UNTRACKED_FILES_DIRTY="true"
export HIST_STAMPS="%d/%m/%Y %H:%M"
export HISTORY_START_WITH_GLOBAL=1
export HISTORY_SUBSTRING_SEARCH_ENSURE_UNIQUE=1
export HISTORY_SUBSTRING_SEARCH_FUZZY=0
export HISTDB_NOSORT=0
export HISTDB_DEFAULT_TAB=Host
# export WORDCHARS="${WORDCHARS//[\/_\-.]/}"

# wsl
if __is_wsl; then
  precmd_functions+=(__wsl_precmd_current_path_prompt)
  source "$ZDOTDIR/relay-ssh-agent.sh"
  append_path "$HOME/.go/bin/windows_amd64"
fi

skip_global_compinit=1

# antidote
zsh_plugins="$ZDOTDIR/.zsh_plugins"
if [[ ! ${zsh_plugins}.zsh -nt ${zsh_plugins}.txt ]]; then
  (
    source "$ZDOTDIR/.antidote/antidote.zsh"
    antidote bundle <${zsh_plugins}.txt >${zsh_plugins}.zsh
  )
fi

source ${zsh_plugins}.zsh

if [[ "$OSTYPE" == "darwin"* ]]; then
  export HISTDB_TABULATE_CMD=(sed -e $'s/\x1f/\t/g')
fi

_histdb_dir="$(antidote path larkery/zsh-histdb)"
source "${_histdb_dir}/sqlite-history.zsh"
source "${_histdb_dir}/histdb-interactive.zsh"
unset _histdb_dir

PATH_DIRECTORIES=(
  "$HOME/bin"
  "$HOME/.local/bin"
  "$HOME/.cargo/bin"
  "$HOME/.krew/bin"
  "$HOME/.go/bin"
  "/usr/local/bin"
  "/snap/bin"
)

append_path "${PATH_DIRECTORIES[@]}"

# build flags
export ARCHFLAGS="-arch $(uname -m)"
export CMAKE_GENERATOR=Ninja
export TRITON_BUILD_WITH_CCACHE=true
export DOCKER_BUILDKIT=1

# note:
#  breaks triton builds for some reason
#
# export TRITON_BUILD_WITH_CLANG_LLD=true
#if [ -f "/usr/bin/clang" ]; then
#  export CC=/usr/bin/clang
#  export CXX=/usr/bin/clang++
#fi

# telemtry and auto updates
export NO_ALBUMENTATIONS_UPDATE=1
export DOTNET_CLI_TELEMETRY_OPTOUT=1
export DOTNET_NOLOGO=1

# ffmpeg
if [ -f "/usr/bin/ffmpeg" ]; then
  export FFMPEG_PATH=/usr/bin/ffmpeg
fi

# openblas
if [ -d "/usr/lib/x86_64-linux-gnu/openblas" ]; then
  export OPENBLASDIR=/usr/lib/x86_64-linux-gnu/openblas
fi

# go
export GO111MODULE=on
export GOPATH="$HOME/.go"
export CGO_ENABLED=1

# python
export PYTHONIOENCODING=UTF-8
export PYTHONUTF8=1
export PROTOCOL_BUFFERS_PYTHON_IMPLEMENTATION=python

# aliases
# alias cd='z'
alias ls='eza -lah --icons=always --color=always --created --changed --git --no-quotes'
alias kubectx='kubectl ctx'
alias kubens='kubectl ns'
alias python='python3'
alias tmux='tmux -u -2'
alias rs='rsync -vPh --info=progress2 --no-i-r'
alias rsync='rsync -vPh --info=progress2 --no-i-r'

[[ "$OSTYPE" == "linux-gnu"* ]] && alias sysctl='/usr/sbin/sysctl'

# default editor
export EDITOR=nano
export VISUAL="$EDITOR"
export KUBE_EDITOR="$EDITOR"
export GIT_EDITOR="$EDITOR"

# gpg tty fix
export GPG_TTY=$(tty)

autoload -Uz history-search-end

zle -N history-beginning-search-backward-end history-search-end
zle -N history-beginning-search-forward-end  history-search-end

# windows-like keyboard behavior
r-delregion() {
  if ((REGION_ACTIVE)) then
     zle kill-region
  else
    local widget_name=$1
    shift
    zle $widget_name -- $@
  fi
}

r-deselect() {
  local was_active=$REGION_ACTIVE
  ((REGION_ACTIVE = 0))
  local widget_name=$1
  shift
  if ((was_active)); then
    zle .$widget_name -- $@
  else
    zle $widget_name -- $@
  fi
}

r-select() {
  ((REGION_ACTIVE)) || zle set-mark-command
  local widget_name=$1
  shift
  zle $widget_name -- $@
}

for key     kcap   seq        mode   widget (
    sleft   kLFT   $'\e[1;2D' select   backward-char
    sright  kRIT   $'\e[1;2C' select   forward-char
    sup     kri    $'\e[1;2A' select   up-line-or-history
    sdown   kind   $'\e[1;2B' select   down-line-or-history

    send    kEND   $'\E[1;2F' select   end-of-line
    send2   x      $'\E[4;2~' select   end-of-line

    shome   kHOM   $'\E[1;2H' select   beginning-of-line
    shome2  x      $'\E[1;2~' select   beginning-of-line

    left    kcub1  $'\EOD'    deselect backward-char
    right   kcuf1  $'\EOC'    deselect forward-char

    end     kend   $'\EOF'    deselect end-of-line
    end2    x      $'\E4~'    deselect end-of-line

    home    khome  $'\EOH'    deselect beginning-of-line
    home2   x      $'\E1~'    deselect beginning-of-line

    csleft  x      $'\E[1;6D' select   backward-word
    csright x      $'\E[1;6C' select   forward-word
    csend   x      $'\E[1;6F' select   end-of-line
    cshome  x      $'\E[1;6H' select   beginning-of-line

    cleft   x      $'\E[1;5D' deselect backward-word
    cright  x      $'\E[1;5C' deselect forward-word

    del     kdch1   $'\E[3~'  delregion delete-char
    bs      x       $'^?'     delregion backward-delete-char

  ) {
  eval "key-$key() {
    r-$mode $widget \$@
  }"
  zle -N key-$key
  bindkey ${terminfo[$kcap]-$seq} key-$key
}

bindkey '^H' backward-kill-word
bindkey '\e[3;5~' kill-word 
(( ${+terminfo[kDC5]} )) && bindkey "${terminfo[kDC5]}" kill-word

__win_shift_del() {
  if (( REGION_ACTIVE )); then
    zle kill-region
  else
    zle kill-whole-line
  fi
}

zle -N __win_shift_del
bindkey '\e[3;2~' __win_shift_del

# Linux virtual console palette (only applies to TERM=linux)
if [[ "$TERM" == "linux" ]]; then
  echo -en "\e]P0000000" #black
  echo -en "\e]P1FF0000" #lightred
  echo -en "\e]P200FF00" #lightgreen
  echo -en "\e]P3FFFF00" #yellow
  echo -en "\e]P40000FF" #lightblue
  echo -en "\e]P5FF00FF" #lightmagenta
  echo -en "\e]P600FFFF" #lightcyan
  echo -en "\e]P7FFFFFF" #highwhite
  echo -en "\e]P8808080" #grey
  echo -en "\e]P9800000" #red
  echo -en "\e]PA008000" #green
  echo -en "\e]PB808000" #brown
  echo -en "\e]PC000080" #blue
  echo -en "\e]PD800080" #magenta
  echo -en "\e]PE008080" #cyan
  echo -en "\e]PFC0C0C0" #white
fi

# macos specific
if [[ "$OSTYPE" == "darwin"* ]]; then
  export PATH="/opt/homebrew/bin${PATH:+:${PATH}}"

  if [ -f "/opt/homebrew/bin/brew" ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  fi

  if [ -f "/opt/homebrew/bin/pyenv" ]; then
    eval "$(pyenv init -)"
  fi
fi

# linux specific
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
  export XAUTHORITY=$HOME/.Xauthority
  export LIBGL_ALWAYS_INDIRECT=1
  export XCURSOR_SIZE=64
  export LD_LIBRARY_PATH=/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}
  export LIBRARY_PATH=/lib/x86_64-linux-gnu${LIBRARY_PATH:+:${LIBRARY_PATH}}

  # cuda
  if [ -d "/usr/local/cuda" ]; then
    export CUDA_HOME=/usr/local/cuda
    export CUDA_PATH=/usr/local/cuda
    export CUDADIR=/usr/local/cuda
    export CUDA_CUDA_LIB=/usr/lib/x86_64-linux-gnu/libcuda.so
    export CUDA_INSTALL_PATH=/usr/local/cuda
    export PATH=/usr/local/cuda/bin${PATH:+:${PATH}}
    export CPATH=/usr/local/cuda/include${CPATH:+:${CPATH}}
    export LIBRARY_PATH=/usr/local/cuda/lib64/stubs:/usr/local/cuda/lib64${LIBRARY_PATH:+:${LIBRARY_PATH}}
    export TRITON_LIBCUDA_PATH=/usr/local/cuda/lib64/stubs/libcuda.so
    export LD_LIBRARY_PATH=/usr/local/cuda/lib64/stubs${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}
    export LDFLAGS=-L/usr/local/cuda/lib64/stubs
  fi

  if [ -f "/usr/lib/x86_64-linux-gnu/libnccl.so" ]; then
    export NCCL_LIBRARY=/usr/lib/x86_64-linux-gnu/libnccl.so
  fi
fi

# history search — Ctrl-R over histdb. Every keystroke re-queries the database
# (fzf runs --disabled with change:reload) so ranking/filtering happens in SQL,
# not over an already-fetched list. Backed by scripts/histdb-fzf.sh, resolved to
# its real repo path via the :A modifier so no extra symlink is needed.
#   • relevancy sort: exact-prefix > word-prefix > contains > fuzzy, and within
#     that, commands run here and successful rank above global/failed ones.
#   • execution-time sort: most recent matches first (substring match).
#   • scope: global (default) / current dir / current dir + subdirs.
#   ctrl-s cycles sort, ctrl-t cycles scope; the header shows the active modes.
# Replaces the zsh-histdb-skim ^R widget (its binary hardcodes `order by start`).
__histdb_helper="${ZDOTDIR:-$HOME/.zsh}/common_functions.sh"
__histdb_helper="${__histdb_helper:A:h}/histdb-fzf.sh"

__histdb_fzf_history_widget() {
  emulate -L zsh
  local selected id cmd state
  local S=${(q)__histdb_helper}
  state=$(mktemp -d "${TMPDIR:-/tmp}/histdb-ctlr.XXXXXX") || return
  print -r -- relevancy > "$state/sort"
  print -r -- global    > "$state/scope"

  # env prefix baked into every fzf child command (not exported into the shell)
  local E="HISTDB_FILE=${(q)HISTDB_FILE} HISTDB_STATE=${(q)state} HISTDB_PWD=${(q)PWD} HISTDB_LIMIT=1000"

  {
    selected=$(</dev/null fzf \
      --ansi --disabled \
      --delimiter='\t' --with-nth='2..' \
      --layout=reverse --height=100% \
      --query="$BUFFER" --header-first \
      --header="$(eval "$E \"$__histdb_helper\" header")" \
      --preview="$E $S preview {1}" \
      --preview-window='right:55%:wrap' \
      --bind="start:reload:$E $S search {q}" \
      --bind="change:reload:$E $S search {q}" \
      --bind="ctrl-s:execute-silent($E $S cycle-sort)+reload($E $S search {q})+transform-header($E $S header)" \
      --bind="ctrl-t:execute-silent($E $S cycle-scope)+reload($E $S search {q})+transform-header($E $S header)")
  } always {
    [[ -n "$state" ]] && command rm -rf -- "$state"
  }

  if [[ -n "$selected" ]]; then
    id="${selected%%$'\t'*}"
    cmd=$(_histdb_query "SELECT commands.argv FROM history LEFT JOIN commands ON history.command_id = commands.id WHERE history.id = ${id} LIMIT 1")
    BUFFER="$cmd"
    CURSOR=$#BUFFER
  fi
  zle reset-prompt
}
zle -N __histdb_fzf_history_widget
bindkey '^R' __histdb_fzf_history_widget

zle-line-init() {}

bindkey '\e[A' history-beginning-search-backward-end
bindkey '\e[B' history-beginning-search-forward-end

# fix random ANSI mouse tracking garbage
__disable_mouse_tracking() {
  printf '\e[?1000l\e[?1002l\e[?1003l\e[?1006l'
}

autoload -Uz add-zsh-hook
add-zsh-hook precmd __disable_mouse_tracking

autoload -Uz add-zle-hook-widget
__zle_sanity_line_init()  { __disable_mouse_tracking }
__zle_sanity_line_finish(){ __disable_mouse_tracking }
add-zle-hook-widget line-init   __zle_sanity_line_init
add-zle-hook-widget line-finish __zle_sanity_line_finish

# completions
zstyle ':completion:*:descriptions' format '[%d]'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*' menu no
zstyle ':fzf-tab:*' switch-group '<' '>'
zstyle ':fzf-tab:*' use-fzf-default-opts yes
zstyle ':fzf-tab:*' fzf-flags '--height=100%'
zstyle ':fzf-tab:*' continuous-trigger 'tab'
zstyle ':fzf-tab:complete:(export|unset):*' fzf-preview 'echo ${(P)word}'
zstyle ':fzf-tab:complete:*:*' fzf-preview '
  if [[ -d "$realpath" ]]; then
    eza -1 --color=always -- "$realpath"
  elif [[ -f "$realpath" ]]; then
    bat -n --color=always -- "$realpath" 2>/dev/null || cat -- "$realpath"
  fi
'

# "partial accept" for completions
typeset -ga ZSH_AUTOSUGGEST_PARTIAL_ACCEPT_WIDGETS
ZSH_AUTOSUGGEST_PARTIAL_ACCEPT_WIDGETS+=(
  forward-word
)

bindkey '\e[1;5C' forward-word 
bindkey '\e[5C'   forward-word
(( ${+terminfo[kRIT5]} )) && bindkey "${terminfo[kRIT5]}" forward-word

# local zsh configuration
local zsh_rc_local="$HOME/.zshrc_local"

if [ -f "$zsh_rc_local" ]; then
  source "$zsh_rc_local"
fi

autoload -Uz compinit
if [[ -n ${ZDOTDIR:-$HOME}/.zcompdump(#qN.mh+24) ]]; then
  compinit -i
else
  compinit -C -i
fi

if [[ "$TERM_PROGRAM" == "vscode" ]] && [[ -d "$HOME/.vscode-server-insiders" ]]; then
  vscode_server_path=$(find "$HOME/.vscode-server-insiders" -name "code-insiders" -type f -print -quit 2>/dev/null)
  [[ -f "$vscode_server_path" ]] && . "$("$vscode_server_path" --locate-shell-integration-path zsh)"
  unset vscode_server_path
fi

# fzf
export FZF_PREVIEW_WINDOW="border-rounded"
export FZF_COLOR_SCHEME="--color=fg:-1,fg+:#ffffff,bg:-1,bg+:#3c4048 --color=hl:#5ea1ff,hl+:#5ef1ff,info:#ffbd5e,marker:#5eff6c --color=prompt:#ff5ef1,spinner:#bd5eff,pointer:#ff5ea0,header:#5eff6c --color=gutter:-1,border:#3c4048,scrollbar:#7b8496,label:#7b8496 --color=query:#ffffff"
export FZF_DEFAULT_OPTS="$FZF_COLOR_SCHEME --border='rounded' --border-label='' --preview-window='$FZF_PREVIEW_WINDOW' --height 40%"
export FZF_CTRL_T_COMMAND='fd --type f --type d --hidden --follow --exclude .git'
export FZF_CTRL_T_OPTS="--multi --height=100% --bind='ctrl-/:toggle-preview,ctrl-a:select-all' --preview='if [ -d {} ]; then eza -1 --color=always -- {}; else bat -n --color=always -- {} 2>/dev/null || cat -- {}; fi'"
export FZF_CTRL_R_OPTS="--delimiter=':' --preview=''"
export _ZO_FZF_OPTS="$FZF_DEFAULT_OPTS --preview='eza -1 --color=always -- {2..}'"

# Ctrl+G: ripgrep content search -> insert "$EDITOR +<line> <file>" into buffer
__fzf_rg_widget() {
  local rg_cmd='rg --line-number --no-heading --color=always --smart-case --hidden --glob=!.git'
  local selected
  selected=$(
    FZF_DEFAULT_COMMAND="$rg_cmd ''" \
    fzf --ansi --multi --height=100% --delimiter=: \
        --disabled --query="" \
        --bind="change:reload:$rg_cmd {q} || true" \
        --bind='ctrl-/:toggle-preview' \
        --preview='bat --color=always --highlight-line {2} -- {1} 2>/dev/null || cat -- {1}' \
        --preview-window='right:60%:+{2}-/2'
  )
  if [[ -n "$selected" ]]; then
    local files=()
    local line
    while IFS= read -r line; do
      local file="${line%%:*}"
      local lineno="${line#*:}"; lineno="${lineno%%:*}"
      files+=("+${lineno} ${(q)file}")
    done <<< "$selected"
    LBUFFER+="${EDITOR:-nano} ${files[@]}"
  fi
  zle reset-prompt
}
zle -N __fzf_rg_widget
bindkey '^g' __fzf_rg_widget

TRAPWINCH() {
  zle && { zle reset-prompt; zle -R }
}

__reset_terminal_colors() {
  [[ -e /dev/tty ]] || return

  printf '\033]104\007' > /dev/tty

  printf '\033]110\007' > /dev/tty
  printf '\033]111\007' > /dev/tty

  printf '\033[39;49m' > /dev/tty
}

if [[ $- == *i* ]]; then
  __reset_terminal_colors
fi

eval "$(zoxide init --cmd cd zsh)"
