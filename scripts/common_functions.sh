#!/bin/zsh

APT_PACKAGES_UPDATED=false
SUDO_KEEPALIVE_STARTED=false

append_path() {
  __assert_parameter "$1"

  local path_directories=("$@")
  export PATH=$(IFS=:; echo "${path_directories[*]}:${PATH:+:${PATH}}")
}

append_ld_library() {
  __assert_parameter "$1"

  local path_directories=("$@")
  export LD_LIBRARY_PATH=$(IFS=:; echo "${path_directories[*]}${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}")
}

__assert_zsh() {
  local shell_file=$(basename $SHELL)

  if [ $shell_file != 'zsh' ]; then
    echo "ERR: Please run script with zsh." >&2
    return 1 2>/dev/null
    exit 1
  fi

  return 0
}

# Ensures that the passed parameter exists
__assert_parameter() {
  __assert_zsh # funcstack below zsh-specific

  local arg=$1

  if [ -z $arg ]; then
    echo "Illegal number of parameters passed to ${funcstack[2]}" >&2
    return 1 2>/dev/null
    exit 1
  fi

  return 0
}

# Run a command with sudo, ignores sudo command if already root and keeps sudo session alive
run_with_sudo() {
  __assert_zsh # setopt below is zsh-specific
  __assert_parameter "$1"

  local cmd_args=("$@")

  if [ "$EUID" = 0 ]; then
    # We are already root so no need for sudo
    eval "${cmd_args[@]}"
    return $?
  fi

  if [ "$SUDO_KEEPALIVE_STARTED" != true ]; then
    # Keeps the sudo session alive so we wont have to re-enter password if something takes too long
    setopt local_options hup
    (while true; do sudo -n true; sleep 5; kill -0 "$$" || exit; done &>/dev/null) &
    SUDO_KEEPALIVE_STARTED=true
  fi

  sudo "${cmd_args[@]}"
  return "$?"
}

edit_and_source() {
  __assert_zsh # setopt below zsh-specific
  setopt local_options err_return

  __assert_parameter "$1"
  local file=$1

  while true; do
    "${EDITOR:-nano}" "$file" && source "$file"

    local exit_code=$?

    if [ $exit_code != 0 ]; then
      echo 'There were errors. Re-edit?' >&2
      echo '[Y]es/[N]o:' >&2
      read "REPLY"

      case "$REPLY" in
        [Yy]*) continue ;;
      esac
    fi

    break
  done
}

# Install packages if missing, executing update only once
__ensure_package_exists() {
    __assert_parameter "$1"

    local pkg_name=$1
    local pkg_result_code=0

    dpkg -l "$pkg_name" &> /dev/null || pkg_result_code="$?"

    if [ "$pkg_result_code" != 0 ]; then
       if [ "$APT_PACKAGES_UPDATED" != true ]; then
         echo "Updating package list..."
         run_with_sudo apt-get update
         APT_PACKAGES_UPDATED=true
       fi

       echo "Installing: $pkg_name"
       run_with_sudo apt-get install -y "$1"
       return $?
    fi

    return 0
}

ensure_packages_exist() {
  __assert_parameter "$1"

  for package in "$@"; do
    __ensure_package_exists "$package"

    local pkg_exists="$?"

    # Fail if the previous command failed (in case set -e is not set)
    if [ "$pkg_exists" != 0 ]; then
      exit "$pkg_exists"
    fi
  done

  return 0
}

append_to_file() {
  __assert_zsh # array last element used in $file below is zsh-specific
  __assert_parameter "$2"

  local line="${@[@]:1:(${#}-1)}"
  local file="${@[-1]}"

  grep -qF "$line" "$file" 2>/dev/null || echo "$line" | tee --append "$file" >/dev/null
}

run_remote_script() {
  __assert_parameter $1

  local quiet=false
  local shell='sh'
  local OPTIND arg

  while getopts "qs:" arg; do
    case $arg in
      q) quiet=true ;;
      s) shell=$OPTARG ;;
    esac
  done

  shift "$((OPTIND - 1))"

  local script_url=$1
  local script_args=""

  shift 1

  if [ "$1" = '--' ]; then
    shift 1
    script_args="${*[@]}"
  fi

  if [ -n "$script_args" ]; then
    echo "> $script_url $script_args"
  else
    echo "> $script_url"
  fi

  if [ $quiet = true ]; then
    { curl -fsSL "$script_url" | "$shell" -s -- "$script_args" } >/dev/null
  else
    { curl -fsSL "$script_url" | "$shell" -s -- "$script_args" }
  fi
}
