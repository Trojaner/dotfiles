#!/bin/zsh

# Fail script if any command fails
set -eu -o pipefail

# Variables
BASE_DIR=$(cd "$(dirname "$0")" && pwd)
HOME_DIR=$(cd ~ && pwd)
APT_PACKAGES_UPDATED=false
BREW_PACKAGES_UPDATED=false

# Import common functions
source $BASE_DIR/scripts/common_functions.sh

__assert_zsh

# On macOS, bootstrap Homebrew before anything else uses ensure_packages_exist
if __is_macos; then
  if ! command -v brew >/dev/null 2>&1; then
    echo "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi

  if [ -x /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [ -x /usr/local/bin/brew ]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
fi

# Packages required for the scripts to work properly
ensure_packages_exist git coreutils moreutils

# Clone latest version
if [ ! -d "$BASE_DIR/.git" ]; then
  echo "Downloading latest version..."
  git init
  git remote add origin https://github.com/Trojaner/dotfiles.git
  git fetch >/dev/null
  git reset origin/main >/dev/null
  git checkout -t origin/main >/dev/null
  source $HOME_DIR/install.sh
  exit 0
else
  # Check if newer version is available
  git checkout main >/dev/null 2>/dev/null
  git fetch >/dev/null

  if [ $(git rev-parse HEAD) != $(git rev-parse @{u}) ]; then
    echo "Newer version found, downloading..."
    git pull origin main --autostash >/dev/null
    source $HOME_DIR/install.sh
    exit 0
  else
    echo "No update found."
  fi
fi

echo "Installing dependencies"
if __is_macos; then
  ensure_packages_exist chroma
else
  ensure_packages_exist chroma command-not-found
fi

echo "Installing packages for zsh extensions"
mkdir -p $HOME_DIR/.local/bin
if __is_macos; then
  ensure_packages_exist fd fzf bat jq sqlite zoxide eza magic-wormhole procs
else
  ensure_packages_exist fd-find fzf bat jq libsqlite3-dev sqlite3 zoxide eza sqlite3-tools magic-wormhole
  ln -sf /usr/bin/batcat $HOME_DIR/.local/bin/bat
  run_with_sudo snap install procs
fi

echo "Installing utilities"
if __is_macos; then
  # macOS: pbcopy is built-in (xclip not needed); ncurses/libnotify are not applicable
  ensure_packages_exist nano unzip tmux tmuxinator go entr pipx htop ninja terminal-notifier
else
  ensure_packages_exist nano xclip xdg-utils unzip tmux tmuxinator lm-sensors libnotify-bin golang entr python3-pip pipx htop ninja-build
fi
pipx ensurepath
curl -LsSf https://astral.sh/uv/install.sh | sh

# zsh, oh-my-zsh, antidote
ZDOTDIR="$HOME_DIR/.zsh"
mkdir -p $ZDOTDIR

ln -sf $BASE_DIR/scripts/common_functions.sh $ZDOTDIR/common_functions.sh
ln -sf $BASE_DIR/scripts/relay-ssh-agent.sh $ZDOTDIR/relay-ssh-agent.sh
ln -sf $BASE_DIR/zsh/.zsh_plugins.txt $ZDOTDIR/.zsh_plugins.txt
ln -sf $BASE_DIR/zsh/.zshrc $HOME_DIR/.zshrc

ln -sf $BASE_DIR/shell/.profile $HOME_DIR/.profile
ln -sf $BASE_DIR/shell/.inputrc $HOME_DIR/.inputrc

if [ ! -d "$ZDOTDIR/.antidote" ]; then
  git clone --depth=1 https://github.com/mattmc3/antidote.git "$ZDOTDIR/.antidote"
else
  git -C "$ZDOTDIR/.antidote" pull
fi

# antidote functions reference parameters like BASH_VERSION that are unset
# under `set -u`; relax it for the antidote-driven block.
set +u
source "$ZDOTDIR/.antidote/antidote.zsh"
# Ensure plugins are bundled/cloned so `antidote path` resolves below.
antidote load "$ZDOTDIR/.zsh_plugins.txt" >/dev/null
ZSH=$(antidote path ohmyzsh/ohmyzsh)

echo "Building zsh-histdb-skim from source"
if __is_macos; then
  ensure_packages_exist rust
else
  ensure_packages_exist cargo
fi
_histdb_skim_plugin_dir=$(antidote path m42e/zsh-histdb-skim)
_histdb_skim_version=$(grep -m1 'HISTB_SKIM_VERSION=' "${_histdb_skim_plugin_dir}/zsh-histdb-skim.zsh" | sed 's/.*"\(.*\)".*/\1/')
_histdb_skim_bin_dir="${XDG_DATA_HOME:-$HOME_DIR/.local/share}/zsh-histdb-skim"
_histdb_skim_bin="${_histdb_skim_bin_dir}/zsh-histdb-skim"
if [[ ! -f "${_histdb_skim_bin}" ]] || [[ "$("${_histdb_skim_bin}" --version 2>/dev/null)" != "${_histdb_skim_version}" ]]; then
  echo "Building zsh-histdb-skim ${_histdb_skim_version} from source"
  mkdir -p "${_histdb_skim_bin_dir}"
  cargo build --release --manifest-path "${_histdb_skim_plugin_dir}/Cargo.toml"
  cp "${_histdb_skim_plugin_dir}/target/release/zsh-histdb-skim" "${_histdb_skim_bin}"
fi
set -u

# nano
touch $HOME_DIR/.nanorc
mkdir -p $HOME_DIR/.nano/backup
if __is_macos; then
  # The upstream installer's _update_nanorc_lite uses GNU sed syntax which
  # fails on BSD sed. Our $BASE_DIR/nano/.nanorc already includes
  # ~/.nano/*.nanorc, so we only need the syntax files themselves.
  _nanorc_tmp=$(mktemp -d)
  curl -fsSL -o "$_nanorc_tmp/nanorc.zip" https://github.com/scopatz/nanorc/archive/master.zip
  unzip -oq "$_nanorc_tmp/nanorc.zip" -d "$_nanorc_tmp"
  cp -R "$_nanorc_tmp"/nanorc-master/* "$HOME_DIR/.nano/"
  rm -rf "$_nanorc_tmp"
else
  { curl -fsSL https://raw.githubusercontent.com/scopatz/nanorc/master/install.sh | sh -s -- -l } >/dev/null
fi
ln -sf $BASE_DIR/nano/.nanorc $HOME_DIR/.nanorc

# tmux
mkdir -p $HOME_DIR/.tmux

ln -sf $BASE_DIR/tmux/.tmux.conf $HOME_DIR/.tmux.conf
ln -sf $BASE_DIR/tmux/show-tmux-popup.sh $HOME_DIR/.tmux/show-tmux-popup.sh

if [ ! -d $HOME_DIR/.tmux/plugins/tpm ]; then
  git clone https://github.com/tmux-plugins/tpm $HOME_DIR/.tmux/plugins/tpm
else
  git -C $HOME_DIR/.tmux/plugins/tpm pull
fi

uv tool install tmuxp --force
uv tool install s-tui --force
uv tool install gpustat --force

if __is_macos; then
  ZSH_SITE_FUNCTIONS_DIR="$(brew --prefix)/share/zsh/site-functions"
  mkdir -p "$ZSH_SITE_FUNCTIONS_DIR"
  uvx --with tmuxp shtab --shell=zsh -u tmuxp.cli.create_parser \
    > "$ZSH_SITE_FUNCTIONS_DIR/_TMUXP"
else
  uvx --with tmuxp shtab --shell=zsh -u tmuxp.cli.create_parser \
    | run_with_sudo tee /usr/local/share/zsh/site-functions/_TMUXP
fi

# htop
mkdir -p $HOME_DIR/.config/htop
ln -sf $BASE_DIR/htop/htoprc $HOME_DIR/.config/htop/htoprc

# git
ln -sf $BASE_DIR/git/.gitconfig.shared $HOME_DIR/.gitconfig.shared
if __is_macos; then
  ln -sf $BASE_DIR/git/.gitconfig.macos $HOME_DIR/.gitconfig
else
  ln -sf $BASE_DIR/git/.gitconfig.linux $HOME_DIR/.gitconfig
fi

# claude code
npm install -g @anthropic-ai/claude-code
mkdir -p $HOME_DIR/.claude
if __is_macos; then
  jq -s '.[0] * .[1]' $BASE_DIR/claude/settings.base.json $BASE_DIR/claude/settings.macos.json > $BASE_DIR/claude/settings.json
else
  jq -s '.[0] * .[1]' $BASE_DIR/claude/settings.base.json $BASE_DIR/claude/settings.linux.json > $BASE_DIR/claude/settings.json
fi
ln -sf $BASE_DIR/claude/settings.json $HOME_DIR/.claude/settings.json
ln -sf $BASE_DIR/claude/statusline-command.sh $HOME_DIR/.claude/statusline-command.sh
ln -sf $BASE_DIR/claude/CLAUDE.md $HOME_DIR/.claude/CLAUDE.md

# tig (macOS ships ncurses; install via Homebrew which is simpler than building)
if __is_macos; then
  ensure_packages_exist tig
else
  ensure_packages_exist libncurses-dev

  if [ ! -d $HOME_DIR/.local/src/tig ]; then
  git clone --depth=1 https://github.com/jonas/tig.git $HOME_DIR/.local/src/tig
  else
    git -C $HOME_DIR/.local/src/tig pull
  fi
  (cd $HOME_DIR/.local/src/tig; make; make install)
fi

# keys
echo "Adding SSH public key"
mkdir -p $HOME_DIR/.ssh/

PUBLIC_KEY=
append_to_file $(cat $BASE_DIR/public_keys/esozbek_id.pub) $HOME_DIR/.ssh/authorized_keys

echo "Adding SSH private key"
SSH_PRIVATE_KEY_PATH=$HOME_DIR/.ssh/id_rsa

echo "Add key to following directory: $SSH_PRIVATE_KEY_PATH"
echo "Press any button to continue."
read -n 1

if [ ! -f $SSH_PRIVATE_KEY_PATH ]; then
  echo "Private key not found; skipping ssh agent private key import"
else
  eval `ssh-agent -s`
  ssh-add $SSH_PRIVATE_KEY_PATH
  chmod 400 $HOME_DIR/.ssh/id_rsa
  append_to_file $(echo "IdentityFile $SSH_PRIVATE_KEY_PATH") "$HOME_DIR/.ssh/config"
  chmod 600 $HOME_DIR/.ssh/config
fi

# sudo (skip on macOS — system-managed; opt in manually if desired)
if ! __is_macos; then
  echo "$USER ALL=(ALL:ALL) NOPASSWD: ALL" | run_with_sudo tee /etc/sudoers.d/$USER
fi

if __is_wsl; then
  ensure_packages_exist socat golang-go
  go get -d github.com/jstarks/npiperelay

  GOOS=windows go build -o /mnt/c/Users/Public/go/bin/npiperelay.exe github.com/jstarks/npiperelay
  run_with_sudo ln -s /mnt/c/Users/Public/go/bin/npiperelay.exe /usr/local/bin/npiperelay.exe

  if [ ! -f /etc/wsl.conf ]; then
    echo "[boot]" | run_with_sudo tee /etc/wsl.conf
    echo "systemd=true" | run_with_sudo tee --append /etc/wsl.conf
    echo "" | run_with_sudo tee --append /etc/wsl.conf
    echo "[automount]" | run_with_sudo tee --append /etc/wsl.conf
    echo "enabled=true" | run_with_sudo tee --append /etc/wsl.conf
  fi
fi


echo "Done!"

# Sourcing the user zshrc here is best-effort: it expects an interactive
# shell environment without `set -u`, so relax safety just for this final step.
set +u +e +o pipefail
. $HOME_DIR/.zshrc
