#!/bin/zsh
set -eu -o pipefail

BASE_DIR=$(realpath $(dirname $0)/..)
source $BASE_DIR/scripts/common_functions.sh

__assert_zsh

sudo snap install kubectl --classic
sudo snap install doctl
sudo snap connect doctl:kube-config
sudo snap connect doctl:ssh-keys :ssh-keys
sudo snap connect doctl:dot-docker

# ensure_packages_exist golang-go

# GOBIN=/usr/local/bin/
# run_with_sudo go install github.com/kubecolor/kubecolor/cmd/kubecolor

(
  set -x; cd "$(mktemp -d)" &&
  OS="$(uname | tr '[:upper:]' '[:lower:]')" &&
  ARCH="$(uname -m | sed -e 's/x86_64/amd64/' -e 's/\(arm\)\(64\)\?.*/\1\2/' -e 's/aarch64$/arm64/')" &&
  KREW="krew-${OS}_${ARCH}" &&
  curl -fsSLO "https://github.com/kubernetes-sigs/krew/releases/latest/download/${KREW}.tar.gz" &&
  tar zxvf "${KREW}.tar.gz" &&
  ./"${KREW}" install krew
)

kubectl krew install ctx
kubectl krew install ns
kubectl krew install tree
kubectl krew install node-resource