export LANG=en_US.UTF-8
export ZDOTDIR="$HOME/.zsh"

source "$ZDOTDIR/common_functions.sh"

# zsh settings
zstyle ':antidote:compatibility-mode' 'antibody' 'on'
zstyle ':omz:update' mode auto
zstyle ':omz:update' frequency 7

source "$ZDOTDIR/.antidote/antidote.zsh"

setopt EXTENDED_HISTORY
setopt INC_APPEND_HISTORY_TIME
setopt HIST_FIND_NO_DUPS
setopt HIST_LEX_WORDS
setopt HIST_FIND_NO_DUPS
setopt EXTENDED_GLOB
setopt GLOB_DOTS
setopt NO_HUP

# oh-my-zsh settings
export ZSH=$(antidote path ohmyzsh/ohmyzsh)
export ZSH_AUTOSUGGEST_STRATEGY=(history completion)
export ZSH_TAB_TITLE_DEFAULT_DISABLE_PREFIX=false
export ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=20
export ZSH_AUTOSUGGEST_USE_ASYNC=1
export ZSH_TAB_TITLE_PREFIX='$USER@$HOST - '
export ZSH_THEME="cloud"
export ZSH_TMUX_UNICODE=true
export COMPLETION_WAITING_DOTS="true"
export DISABLE_UNTRACKED_FILES_DIRTY="true"
export HIST_STAMPS="dd/mm/yyyy H:M"
export HISTORY_START_WITH_GLOBAL=1
export HISTORY_SUBSTRING_SEARCH_ENSURE_UNIQUE=1
export HISTORY_SUBSTRING_SEARCH_FUZZY=1


# wsl
if __is_wsl; then
  precmd_functions+=(__wsl_precmd_current_path_prompt)
fi

# antidote
zsh_plugins="$ZDOTDIR/.zsh_plugins"
if [[ ! ${zsh_plugins}.zsh -nt ${zsh_plugins}.txt ]]; then
  (
    source "$ZDOTDIR/.antidote/antidote.zsh"
    antidote bundle <${zsh_plugins}.txt >${zsh_plugins}.zsh
  )
fi
source ${zsh_plugins}.zsh

PATH_DIRECTORIES=(
  "$HOME/bin"
  "$HOME/.local/bin"
  "$HOME/.cargo/bin"
  "/usr/local/bin"
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

# fzf
export FZF_DEFAULT_OPTS='--color=fg:-1,fg+:#ffffff,bg:-1,bg+:#3c4048 --color=hl:#5ea1ff,hl+:#5ef1ff,info:#ffbd5e,marker:#5eff6c --color=prompt:#ff5ef1,spinner:#bd5eff,pointer:#ff5ea0,header:#5eff6c --color=gutter:-1,border:#3c4048,scrollbar:#7b8496,label:#7b8496 --color=query:#ffffff --border="rounded" --border-label="" --preview-window="border-rounded" --height 40% --preview="bat -n --color=always {}"'

# go
export GO111MODULE=on

# python
export PYTHONIOENCODING=UTF-8
export PYTHONUTF8=1
export UV_LINK_MODE=symlink
export PROTOCOL_BUFFERS_PYTHON_IMPLEMENTATION=python

# aliases
alias ls='ls -lah --color=auto'
alias python='python3'
alias tmux='tmux -u'
alias rsync='rsync -Ph --info=progress2 --no-i-r'
alias sysctl='/usr/sbin/sysctl'

# default editor
export EDITOR=nano
export VISUAL="$EDITOR"
export KUBE_EDITOR="$EDITOR"
export GIT_EDITOR="$EDITOR"

# gpg tty fix
export GPG_TTY=$(tty)

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
  ((REGION_ACTIVE = 0))
  local widget_name=$1
  shift
  zle $widget_name -- $@
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

# theme
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

printf %b '\e]11;#300A24\a' # background color

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
  export LIBRARY_PATH=/lib/x86_64-linux-gnu${LIBRARY_PATH:+:${LIBRARY_PATH}}

  if [ -f "/proc/sys/fs/binfmt_misc/WSLInterop" ]; then
    precmd_functions+=(__wsl_append_current_path)
  fi 

  # cuda
  if [ -d "/usr/local/cuda" ]; then
    export CUDA_HOME=/usr/local/cuda
    export CUDA_PATH=/usr/local/cuda
    export CUDADIR=/usr/local/cuda
    export CUDA_CUDA_LIB=/usr/lib/x86_64-linux-gnu/libcuda.so
    export CUDA_INSTALL_PATH=/usr/local/cuda
    export PATH=/usr/local/cuda/bin${PATH:+:${PATH}}
    export CPATH=/usr/local/cuda/include${CPATH:+:${CPATH}}
    export LIBRARY_PATH=/usr/local/cuda/lib64${LIBRARY_PATH:+:${LIBRARY_PATH}}
    export LD_LIBRARY_PATH=/usr/local/cuda/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}
  fi

  if [ -f "/usr/lib/x86_64-linux-gnu/libnccl.so" ]; then
    export NCCL_LIBRARY=/usr/lib/x86_64-linux-gnu/libnccl.so
  fi
fi

# zsh-history-substring-search
bindkey '^[[A' history-substring-search-up
bindkey '^[[B' history-substring-search-down
bindkey 'forward-char' autosuggest-accept

# local zsh configuration
local zsh_rc_local="$HOME/.zshrc_local"

if [ -f "$zsh_rc_local" ]; then
  source "$zsh_rc_local"
fi

if [[ "$OSTYPE" == "darwin"* ]]; then
  autoload -U compinit && compinit
fi
