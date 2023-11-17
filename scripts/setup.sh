#!/bin/zsh

# Fail script if any command fails
set -eu -o pipefail

# Variables
BASE_DIR=$(realpath $(dirname $0)/..)
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
    git pull origin main >/dev/null
    source $HOME_DIR/install.sh
    exit 0
  else
    echo "No update found."
  fi
fi

echo "Installing dependencies"
ensure_packages_exist chroma command-not-found

echo "Installing packages for zsh extensions"
ensure_packages_exist fd-find fzf

echo "Installing utilities"
ensure_packages_exist nano xclip xdg-utils unzip tmux tmuxinator lm-sensors libnotify-bin golang entr

touch ~/.nanorc
{ curl -fsSL https://raw.githubusercontent.com/scopatz/nanorc/master/install.sh | sh -s -- -l } >/dev/null
mkdir -p ~/.nano/backup

# Install fig (?)
# curl -fSsL https://repo.fig.io/scripts/install-headless.sh | bash


# Link files
echo "Linking dotfiles"
mkdir -p $HOME_DIR/.zsh

# Install oh-my-zsh and related stuff
echo "Installing oh-my-zsh"
if [ ! -d $HOME_DIR/.oh-my-zsh ]; then
  { curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh | /bin/bash -s -- "" --unattended } >/dev/null
fi

{ curl -fsSL git.io/antibody | sudo sh -s - -b /usr/local/bin } >/dev/null
git clone https://github.com/zsh-users/zsh-completions ${ZSH_CUSTOM:-${ZSH:-~/.oh-my-zsh}/custom}/plugins/zsh-completions &>/dev/null || true
git clone https://github.com/trystan2k/zsh-tab-title ${ZSH_CUSTOM:-${ZSH:-~/.oh-my-zsh}/custom}/plugins/zsh-tab-title &>/dev/null || true

git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
python3 -m pip install --user libtmux

ln -sf $BASE_DIR/scripts/common_functions.sh $HOME_DIR/.zsh/common_functions.sh
ln -sf $BASE_DIR/.nanorc $HOME_DIR/.nanorc
ln -sf $BASE_DIR/.zshrc $HOME_DIR/.zshrc
ln -sf $BASE_DIR/.gitconfig $HOME_DIR/.gitconfig
ln -sf $BASE_DIR/.profile $HOME_DIR/.profile
ln -sf $BASE_DIR/.minttyrc $HOME_DIR/.minttyrc
ln -sf $BASE_DIR/.tmux.conf $HOME_DIR/.tmux.conf
ln -sf $BASE_DIR/config/htop/htoprc $HOME_DIR/.config/htop/htoprc

# Import SSH public key
echo "Adding SSH public key"
mkdir -p $HOME_DIR/.ssh/

PUBLIC_KEY=
append_to_file $(cat $BASE_DIR/public_keys/esozbek_id.pub) $HOME_DIR/.ssh/authorized_keys

echo "Adding SSH private key"
PRIVATE_KEY_PATH=$HOME_DIR/.ssh/id_rsa

echo "Add key to following directory: $PRIVATE_KEY_PATH"
echo "Press any button to continue."
read -n 1

if [ ! -f $PRIVATE_KEY_PATH ]; then
  echo "Private key not found; skipping ssh agent private key import"
else
  eval `ssh-agent -s`
  ssh-add $PRIVATE_KEY_PATH
  chmod 400 $HOME_DIR/.ssh/id_rsa
  append_to_file $(echo "IdentityFile $PRIVATE_KEY_PATH") "$HOME_DIR/.ssh/config"
  chmod 600 $HOME_DIR/.ssh/config
fi

echo "Removing sudo requirement"
echo "$USER ALL=(ALL:ALL) NOPASSWD: ALL" | run_with_sudo tee /etc/sudoers.d/$USER

echo "Done!"
exec zsh
