#!/bin/bash

# Fail script if any command fails
set -eu -o pipefail

# Variables
BASE_DIR=$(dirname $(realpath $0))
HOME_DIR=$(realpath ~)
APT_PACKAGES_UPDATED=false
SUDO_KEEPALIVE_STARTED=false

# Import common functions
source $BASE_DIR/common_functions.sh

ensure_packages_exist git

# Clone latest version
if [ ! -d "$BASE_DIR/.git" ]; then
  echo "Downloading latest version..."
  git init
  git remote add origin https://github.com/Trojaner/dotfiles.git
  git fetch
  git reset origin/main >/dev/null
  git checkout -t origin/main >/dev/null
  source $HOME_DIR/install.sh
  exit 0
else
  # Check if newer version is available
  git checkout main >/dev/null
  git fetch

  if [ $(git rev-parse HEAD) != $(git rev-parse @{u}) ]; then
    echo "Newer version found, downloading..."
    git pull origin main
    source $HOME_DIR/install.sh
    exit 0
  else
    echo "No update found."
  fi
fi

echo "Installing dependencies"
ensure_packages_exist zsh chroma command-not-found

echo "Installing optional tools"
ensure_packages_exist nano fd-find tmux tmuxinator fzf

# Install fig
# curl -fSsL https://repo.fig.io/scripts/install-headless.sh | bash

# Link files
echo "Linking files"
rm -f $HOME_DIR/.zshrc $HOME_DIR/.gitconfig $HOME_DIR/.fastfile
ln -s $BASE_DIR/.zshrc $HOME_DIR/.zshrc
ln -s $BASE_DIR/.gitconfig $HOME_DIR/.gitconfig
ln -s $BASE_DIR/.fastfile $HOME_DIR/.fastfile

# Install oh-my-zsh and related stuff
if [ ! -d $HOME_DIR/.oh-my-zsh ]; then
  sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi

curl -sfL git.io/antibody | sudo sh -s - -b /usr/local/bin
git clone https://github.com/zsh-users/zsh-completions ${ZSH_CUSTOM:-${ZSH:-~/.oh-my-zsh}/custom}/plugins/zsh-completions

# Import SSH public key
echo "Adding SSH public key"
mkdir -p $HOME_DIR/.ssh/
cat $BASE_DIR/public_keys/esozbek_id.pub >> $HOME_DIR/.ssh/authorized_keys
echo "es.ozbek@outlook.com $(cat $BASE_DIR/public_keys/esozbek_id.pub)" >> $HOME_DIR/.ssh/allowed_signers

echo "Adding SSH private key"
PRIVATE_KEY_PATH=$HOME_DIR/.ssh/esozbek_id

echo "Add key to following directory: $PRIVATE_KEY_PATH"
read -n 1 -p "Press any button to continue."

if [ ! -f $PRIVATE_KEY_PATH ]; then
  echo "Private key not found; skipping ssh agent private key import"
else
  eval `ssh-agent -s`
  ssh-add $PRIVATE_KEY_PATH
  chmod 400 $HOME_DIR/.ssh/esozbek_id
  rm -f $HOME_DIR/.ssh/config
  echo "IdentityFile $PRIVATE_KEY_PATH" >> $HOME_DIR/.ssh/config
  chmod 600 $HOME_DIR/.ssh/config
fi

echo "Cleanup..."
do_cleanup

echo "Done!"
exec zsh
