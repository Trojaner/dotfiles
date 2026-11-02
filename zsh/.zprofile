# The following lines were added by Docker Desktop to add commands to your PATH.
export PATH="$PATH:$HOME/.docker/bin"
# End of Docker Desktop section.

if [[ ! -o interactive ]]; then
  path=($PATH_DIRECTORIES /opt/homebrew/bin /opt/homebrew/sbin $path)
  export PATH
fi

[[ -f "$HOME/.zprofile_local" ]] && source "$HOME/.zprofile_local"
