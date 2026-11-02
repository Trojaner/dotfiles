export LANG=en_US.UTF-8

# telemetry and auto updates
export NO_ALBUMENTATIONS_UPDATE=1
export DOTNET_CLI_TELEMETRY_OPTOUT=1
export DOTNET_NOLOGO=1

# dotnet
export DOTNET_ROOT="$HOME/.dotnet"

# go
export GO111MODULE=on
export GOPATH="$HOME/.go"

# python
export PYTHONIOENCODING=UTF-8
export PYTHONUTF8=1

# homebrew
if [[ -d /opt/homebrew ]]; then
  export HOMEBREW_PREFIX=/opt/homebrew
  export HOMEBREW_CELLAR=/opt/homebrew/Cellar
  export HOMEBREW_REPOSITORY=/opt/homebrew
  [[ :$INFOPATH: == *:/opt/homebrew/share/info:* ]] || export INFOPATH="/opt/homebrew/share/info:${INFOPATH:-}"
fi

# path
typeset -U PATH path

PATH_DIRECTORIES=(
  "$HOME/.pyenv/shims"
  "/bin/local"
  "/usr/local/bin"
  "/snap/bin"
  "$HOME/bin"
  "$HOME/.local/bin"
  "$HOME/.cargo/bin"
  "$HOME/.krew/bin"
  "$HOME/.go/bin"
  "$HOME/.dotnet"
  "$HOME/.dotnet/tools"
  "$HOME/.maestro/bin"
  "$HOME/Library/pnpm"
)

path=($PATH_DIRECTORIES $path /opt/homebrew/bin /opt/homebrew/sbin)
export PATH
