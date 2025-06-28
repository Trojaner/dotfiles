#!/bin/zsh

# Fail script if any command fails
set -eu -o pipefail

# Variables
BASE_DIR=$(realpath $(dirname $0))
HOME_DIR=$(realpath ~)
APT_PACKAGES_UPDATED=false

# Import common functions
source $BASE_DIR/scripts/common_functions.sh

__assert_zsh

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
ensure_packages_exist chroma command-not-found

echo "Installing packages for zsh extensions"
ensure_packages_exist fd-find fzf bat
ln -sf /usr/bin/batcat ~/.local/bin/bat
run_with_sudo snap install procs

echo "Installing utilities"
ensure_packages_exist nano xclip xdg-utils unzip tmux tmuxinator lm-sensors libnotify-bin golang entr python3-pip htop ninja-build

# zsh, oh-my-zsh, antidote
ZDOTDIR="$HOME_DIR/.zsh"
mkdir -p $ZDOTDIR

ln -sf $BASE_DIR/scripts/common_functions.sh $ZDOTDIR/common_functions.sh
ln -sf $BASE_DIR/zsh/.zsh_plugins.txt $ZDOTDIR/.zsh_plugins.txt
ln -sf $BASE_DIR/zsh/.zshrc $HOME_DIR/.zshrc

ln -sf $BASE_DIR/shell/.profile $HOME_DIR/.profile
ln -sf $BASE_DIR/shell/.inputrc $HOME_DIR/.inputrc

git clone --depth=1 https://github.com/mattmc3/antidote.git "$ZDOTDIR/.antidote"
source "$ZDOTDIR/.antidote/antidote.zsh"
antidote update
antidote bundle <${zsh_plugins}.txt >${zsh_plugins}.zsh
antidote load
ZSH=$(antidote path ohmyzsh/ohmyzsh)

# nano
touch ~/.nanorc
{ curl -fsSL https://raw.githubusercontent.com/scopatz/nanorc/master/install.sh | sh -s -- -l } >/dev/null
mkdir -p ~/.nano/backup
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

python3 -m pip install --user libtmux tmuxp s-tui gpustat

# htop
mkdir -p $HOME_DIR/.config/htop
ln -sf $BASE_DIR/htop/htoprc $HOME_DIR/.config/htop/htoprc

# git
ln -sf $BASE_DIR/git/.gitconfig $HOME_DIR/.gitconfig

# tig
git clone --depth=1 https://github.com/jonas/tig.git $HOME_DIR/.local/src/tig
(cd $HOME_DIR/.local/src/tig; make; make install)

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

echo ""
echo "**Do not forget to import GPG signing key 30D309B77EDBEE37 if "git commit" is needed on this device**"
echo ""

# sudo
echo "$USER ALL=(ALL:ALL) NOPASSWD: ALL" | run_with_sudo tee /etc/sudoers.d/$USER

echo "Done!"

. ~/.zshrc
