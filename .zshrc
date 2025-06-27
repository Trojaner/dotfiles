source ~/.zsh/common_functions.sh

PATH_DIRECTORIES=(
  "$HOME/bin"
  "$HOME/.local/bin"
  "$HOME/.cargo/bin"
  "/usr/local/bin"
)

append_path "${PATH_DIRECTORIES[@]}"

export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="cloud"

# Uncomment the following line to use case-sensitive completion.
# CASE_SENSITIVE="true"

# Uncomment the following line to use hyphen-insensitive completion.
# Case-sensitive completion must be off. _ and - will be interchangeable.
# HYPHEN_INSENSITIVE="true"

zstyle ':omz:update' mode auto      # update automatically without asking
zstyle ':omz:update' frequency 7

setopt EXTENDED_HISTORY
setopt INC_APPEND_HISTORY_TIME
setopt HIST_FIND_NO_DUPS
setopt HIST_LEX_WORDS

# Uncomment the following line if pasting URLs and other text is messed up.
# DISABLE_MAGIC_FUNCTIONS="true"

# Uncomment the following line to display red dots whilst waiting for completion.
# You can also set it to another string to have that shown instead of the default red dots.
# e.g. COMPLETION_WAITING_DOTS="%F{yellow}waiting...%f"
# Caution: this setting can cause issues with multiline prompts in zsh < 5.7.1 (see #5765)
COMPLETION_WAITING_DOTS="true"

# Uncomment the following line if you want to disable marking untracked files
# under VCS as dirty. This makes repository status check for large repositories
# much, much faster.
DISABLE_UNTRACKED_FILES_DIRTY="true"

# Uncomment the following line if you want to change the command execution time
# stamp shown in the history command output.
# You can set one of the optional three formats:
# "mm/dd/yyyy"|"dd.mm.yyyy"|"yyyy-mm-dd"
# or set a custom format using the strftime function format specifications,
# see 'man strftime' for details.
HIST_STAMPS="dd/mm/yyyy H:M"

export ZSH_TAB_TITLE_DEFAULT_DISABLE_PREFIX=false
export ZSH_TAB_TITLE_PREFIX='$USER@$HOST - '
export ZSH_TMUX_UNICODE=true

plugins=(
  aws
  colored-man-pages
  colorize
  command-not-found
  docker
  dotnet
  extract
  fastfile
  # fig -- commercial
  # gcloud
  gh
  # helm -- causes address already in use error on multiple shells
  history
  # httpie
  # kn
  kubectl
  kubectx
  kops
  nmap
  npm
  nvm
  pip
  # postgres -- only adds aliases?
  redis-cli
  rsync
  screen
  sudo
  systemd
  timer
  tmux
  tmuxinator
  ufw
  vscode
  yarn
  z
  zsh-interactive-cd
  zsh-navigation-tools
  zsh-tab-title
)

# zsh-completions
keep_current_path() {
  if [ -f "/proc/sys/fs/binfmt_misc/WSLInterop" ]; then
    printf "\e]9;9;%s\e\\" "$(wslpath -w "$PWD")"
  fi

}

precmd_functions+=(keep_current_path)
fpath+=${ZSH_CUSTOM:-${ZSH:-~/.oh-my-zsh}/custom}/plugins/zsh-completions/src

source $ZSH/oh-my-zsh.sh
source <(fzf --zsh)

export LANG=en_US.UTF-8
export DOCKER_BUILDKIT=1

export ARCHFLAGS="-arch $(uname -m)"
# export TRITON_BUILD_WITH_CLANG_LLD=true
export TRITON_BUILD_WITH_CCACHE=true
export PROTOCOL_BUFFERS_PYTHON_IMPLEMENTATION=python
export CMAKE_GENERATOR=Ninja

#if [ -f "/usr/bin/clang" ]; then
#  export CC=/usr/bin/clang
#  export CXX=/usr/bin/clang++
#fi

export NO_ALBUMENTATIONS_UPDATE=1
export DOTNET_CLI_TELEMETRY_OPTOUT=1
export DOTNET_NOLOGO=1

if [[ "$OSTYPE" == "darwin"* ]]; then
  if [ -f "/opt/homebrew/bin/brew" ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  fi

  if [ -f "/opt/homebrew/bin/pyenv" ]; then
    eval "$(pyenv init -)"
  fi
fi

if [[ "$OSTYPE" == "linux-gnu"* ]]; then
  export XAUTHORITY=$HOME/.Xauthority
  export LIBGL_ALWAYS_INDIRECT=1
  export XCURSOR_SIZE=64
  export LIBRARY_PATH=/lib/x86_64-linux-gnu${LIBRARY_PATH:+:${LIBRARY_PATH}}
fi

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

if [ -d "/usr/lib/x86_64-linux-gnu/openblas" ]; then
  export OPENBLASDIR=/usr/lib/x86_64-linux-gnu/openblas
fi

if [ -f "/usr/lib/x86_64-linux-gnu/libnccl.so" ]; then
  export NCCL_LIBRARY=/usr/lib/x86_64-linux-gnu/libnccl.so
fi

if [ -f "/usr/bin/ffmpeg" ]; then
  export FFMPEG_PATH=/usr/bin/ffmpeg
fi

# Always list all files
alias ls='ls -lah --color=auto'
alias python='python3'
alias tmux='tmux -u'
alias venv='. venv/bin/activate'
alias rsync='rsync -Ph --info=progress2 --no-i-r'
alias sysctl='/usr/sbin/sysctl'

# Include hidden files in GLOB
setopt GLOB_DOTS
setopt NO_HUP

# Set nano as default editor
export EDITOR=nano
export VISUAL="$EDITOR"
export KUBE_EDITOR="$EDITOR"
export GIT_EDITOR="$EDITOR"

# Fix GPG TTY
export GPG_TTY=$(tty)

# Fix something with go
export GO111MODULE=on

# Windows-like keyboard behavior
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

# Set theme
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

# Set background color
printf %b '\e]11;#300A24\a'

# zsh parameter completion for the dotnet CLI

_dotnet_zsh_complete()
{
  local completions=("$(dotnet complete "$words")")

  # If the completion list is empty, just continue with filename selection
  if [ -z "$completions" ]
  then
    _arguments '*::arguments: _normal'
    return
  fi

  # This is not a variable assignment, don't remove spaces!
  _values = "${(ps:\n:)completions}"
}

compdef _dotnet_zsh_complete dotnet

local zsh_rc_local="$HOME/.zshrc_local"

if [ -f "$zsh_rc_local" ]; then
  source "$zsh_rc_local"
fi
