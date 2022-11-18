#!/bin/bash

set -eu -o pipefail

BASE_DIR=$(dirname $(realpath $0))
source $BASE_DIR/common_functions.sh

run_with_sudo rm -f "/etc/locale.gen"
echo "en_US ISO-8859-1" | run_with_sudo tee --append "/etc/locale.gen" >/dev/null
echo "en_US.ISO-8859-15 ISO-8859-15" | run_with_sudo tee --append "/etc/locale.gen" >/dev/null
echo "en_US.UTF-8 UTF-8" | run_with_sudo tee --append "/etc/locale.gen" >/dev/null

ensure_packages_exist locales tzdata

export LANGUAGE=en_US
export LC_ALL=en_US

run_with_sudo update-locale LANG=en_US.UTF-8 LANGUAGE=en_US.UTF-8
run_with_sudo localedef -i en_US -c -f UTF-8 -A /usr/share/locale/locale.alias en_US.UTF-8
run_with_sudo dpkg-reconfigure -f noninteractive locales
run_with_sudo dpkg-reconfigure -f noninteractive tzdata

exec $SHELL
