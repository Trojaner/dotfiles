#!/bin/zsh

APT_PACKAGES_UPDATED=false
SUDO_KEEPALIVE_STARTED=false

append_path() {
  local path_directories=("$@")
  export PATH=$(IFS=:; echo "${path_directories[*]}:${PATH:+:${PATH}}")
}

append_ld_library() {
  local path_directories=("$@")
  export LD_LIBRARY_PATH=$(IFS=:; echo "${path_directories[*]}${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}")
}

venv() {
  local arg=$1

  if [ -z $arg ]; then
    local venv_name='venv'

    if [ ! -d "./$venv_name" ]; then
      venv_name='.venv'
    fi

    if [ ! -d "./$venv_name" ]; then
      echo "ERR: Failed to find venv directory. Use venv -c to create one." >&2
      return 1 2>/dev/null
    fi

    source "./$venv_name/bin/activate"
  elif [ $arg = '-c' ]; then
    local venv_name="${2:-venv}"
    venv_full_path=$(realpath "./$venv_name")

    if [ -d "./$venv_name" ]; then
      echo "ERR: venv directory "$venv_full_path" already exists. Use venv -c <name> to create a venv with a different name." >&2
      return 1 2>/dev/null
    fi

    uv venv --relocatable "$venv_full_path"
    
    source "$venv_full_path/bin/activate"
    python -m ensurepip
    python -m pip install ninja setuptools wheel
    deactivate

    return $?
  fi
}

install_zsh_plugin() {
  __assert_zsh
  __assert_parameter "$1" "<plugin_repo>" 1

  local plugin_repo=$1
  local plugin_name=$2
  
  if [ -z "$plugin_name" ]; then
    plugin_name=$(basename "$plugin_repo")
  fi

  local plugin_path="$ZDOTDIR/.antidote/plugins/$plugin_name"

  if [ ! -d "$plugin_path" ]; then
    echo "Installing zsh plugin: $plugin_repo to: $plugin_path"
    git clone --depth=1 "https://github.com/$plugin_repo" "$plugin_path" &>/dev/null || true
  else
    echo "Updating zsh plugin: $plugin_repo"
    git -C "$plugin_path" pull  &>/dev/null || true
  fi
}

# Run a command with sudo, ignores sudo command if already root and keeps sudo session alive
run_with_sudo() {
  __assert_zsh # setopt below is zsh-specific
  __assert_parameter "$1" "<command>" 1

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

  __assert_parameter "$1" "<file>" 1
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
ensure_package_exists() {
    __assert_parameter "$1" "<package>" 1

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
  __assert_parameter "$1" "<packages...>" 1

  for package in "$@"; do
    ensure_package_exists "$package"

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
  __assert_parameter "$2" "<line>" 2
  __assert_parameter "$3" "<file>" 3

  local line="${@[@]:1:(${#}-1)}"
  local file="${@[-1]}"

  grep -qF "$line" "$file" 2>/dev/null || echo "$line" | tee --append "$file" >/dev/null
}

run_remote_script() {
  __assert_parameter $1, "<script url>" 1

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

__wsl_precmd_current_path_prompt() {
  __assert_wsl

  printf "\e]9;9;%s\e\\" "$(wslpath -w "$PWD")"
}

__assert_wsl() {
  __assert_zsh  # funcstack below zsh-specific

  local caller_function_name=${funcstack[2]}

  if ! __is_wsl; then
    echo "ERR: The function ${caller_function_name} is only available in WSL." >&2
    return 1 2>/dev/null
    exit 1
  fi

  return 0
}

__is_wsl() {
  if [ -f "/proc/sys/fs/binfmt_misc/WSLInterop" ]; then
    return 0
  else
    return 1
  fi
}

# Ensures that the passed parameter exists
__assert_parameter() {
  __assert_zsh # funcstack below zsh-specific

  local parameter_value=$1
  local parameter_name=$2
  if [ -z "$parameter_name" ]; then
    echo "ERR: __assert_parameter called without parameter name" >&2
    return 1 2>/dev/null
    exit 1
  fi

  local parameter_index=$3
  if [ -z "$parameter_index" ]; then
    echo "ERR: __assert_parameter called without parameter index" >&2
    return 1 2>/dev/null
    exit 1
  fi

  local caller_function_name=${funcstack[2]}

  if [ -z $arg ]; then
    echo "ERR: The function ${caller_function_name} is missing the \"${parameter_name}\" parameter at index ${parameter_index}." >&2
    return 1 2>/dev/null
    exit 1
  fi

  return 0
}

__assert_zsh() {
  local shell_file=$(basename $SHELL)

  if [ $shell_file != 'zsh' ]; then
    echo "ERR: Please run script with zsh." >&2
    return 1 2>/dev/null
    exit 1
  fi

  if [ -z "$ZDOTDIR" ]; then
    echo "ERR: ZDOTDIR is not defined" >&2
    return 1 2>/dev/null
  fi

  if [ -z "$ZSH" ]; then
    echo "ERR: ZSH is not defined" >&2
    return 1 2>/dev/null
  fi

  return 0
}