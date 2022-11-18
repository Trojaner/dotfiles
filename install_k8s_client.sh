#!/bin/bash
set -eu -o pipefail

# Variables
BASE_DIR=$(dirname $(realpath $0))
HOME_DIR=$(realpath ~)

# Install kubectl
ARCH=$(dpkg-architecture -q DEB_BUILD_ARCH)
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/$ARCH/kubectl"

# Import common functions
source $BASE_DIR/common_functions.sh

# ensure_packages_exist golang-go

# GOBIN=/usr/local/bin/
# run_with_sudo go install github.com/kubecolor/kubecolor/cmd/kubecolor

run_with_sudo git -C /opt/kubectx clone https://github.com/ahmetb/kubectx 2>/dev/null || run_with_sudo git -C /opt/kubectx pull
run_with_sudo rm -f /usr/local/bin/kubectx /usr/local/bin/kubens
run_with_sudo ln -s /opt/kubectx/kubectx /usr/local/bin/kubectx
run_with_sudo ln -s /opt/kubectx/kubens /usr/local/bin/kubens

echo "ahmetb/kubectx path:completion kind:fpath" >> ~/.zsh_plugins.txt
mkdir -p $HOME_DIR/.oh-my-zsh/completions
chmod -R 755 $HOME_DIR/.oh-my-zsh/completions

rm -f $HOME_DIR/.oh-my-zsh/completions/_kubectx.zsh $HOME_DIR/.oh-my-zsh/completions/_kubens.zsh
ln -s /opt/kubectx/completion/_kubectx.zsh $HOME_DIR/.oh-my-zsh/completions/_kubectx.zsh
ln -s /opt/kubectx/completion/_kubens.zsh $HOME_DIR/.oh-my-zsh/completions/_kubens.zsh
