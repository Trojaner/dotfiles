#!/bin/bash

APT_PACKAGES_UPDATED=false
SUDO_KEEPALIVE_STARTED=false

# Ensures that the passed argument exists
assert_argument() {
  ARG=$1

  if [ -z "$ARG" ]; then
    echo "Illegal number of parameters passed to ${FUNCNAME[1]}"
    exit 1
  fi

  return 0
}

# Run a command with sudo, ignores sudo command if already root and keeps sudo session alive
run_with_sudo() {
  assert_argument "$1"

  COMMAND_LINE_ARGS=("$@")

  if [ "$EUID" = 0 ]; then
    eval "${COMMAND_LINE_ARGS[@]}"
    return $?
  fi

  if [ "$SUDO_KEEPALIVE_STARTED" != true ]; then
    # Keeps the sudo session alive so we wont have to re-enter password if something takes too long
    (while true; do sudo -n true; sleep 5; kill -0 "$$" || exit; done 2>/dev/null) &
    SUDO_KEEPALIVE_STARTED=true
    SUDO_KEEPALIVE_PID=$!
  fi

  sudo "${COMMAND_LINE_ARGS[@]}"
  return "$?"
}

do_cleanup() {
  if [ -n "$SUDO_KEEPALIVE_PID" ]; then
    kill "$SUDO_KEEPALIVE_PID"
  fi
}

# Install packages if missing, executing update only once
__ensure_package_exists() {
    assert_argument "$1"

    PACKAGE_NAME=$1
    PACKAGE_RESULT_CODE=0

    dpkg -l "$PACKAGE_NAME" &> /dev/null || PACKAGE_RESULT_CODE="$?"

    if [ "$PACKAGE_RESULT_CODE" != 0 ]; then
       if [ "$APT_PACKAGES_UPDATED" != true ]; then
         echo "Updating package list..."
         run_with_sudo apt-get update
         APT_PACKAGES_UPDATED=true
       fi

       echo "Installing: $PACKAGE_NAME"
       run_with_sudo apt-get install -y "$1"
       return $?
    fi

    return 0
}

ensure_packages_exist() {
  assert_argument "$1"

  for package in "$@"; do
    __ensure_package_exists "$package"

    PACKAGE_EXISTS="$?"

    # Fail if the previous command failed (in case set -e is not set)
    if [ "$PACKAGE_EXISTS" != 0 ]; then
      exit "$PACKAGE_EXISTS"
    fi
  done

  return 0
}

sudo_append_line_to_file() {
  assert_argument "$2"

  LINE="${@[@]:1:(${#}-1)}"
  FILE="${@[-1]}"

  grep -qF "$LINE" "$FILE" 2>/dev/null || echo "$LINE" | run_with_sudo tee --append "$FILE" >/dev/null
}

append_line_to_file() {
  assert_argument "$2"

  LINE="${@[@]:1:(${#}-1)}"
  FILE="${@[-1]}"

  grep -qF "$LINE" "$FILE" 2>/dev/null || echo "$LINE" | tee --append "$FILE" >/dev/null
}
