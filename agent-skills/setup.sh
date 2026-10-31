#!/bin/zsh
set -eu -o pipefail

REPO_DIR=$(cd "$(dirname "$0")/.." && pwd)
SKILLS_DIR="$REPO_DIR/agent-skills"
CLAUDE_SKILLS="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills"
CODEX_SKILLS="${CODEX_HOME:-$HOME/.codex}/skills"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/agent-sessions"

link_skill() {
  local source_dir=$1 target_root=$2
  local target="$target_root/$(basename "$source_dir")"
  mkdir -p "$target_root"
  [[ -L "$target" && "$target" -ef "$source_dir" ]] && return
  if [[ -e "$target" || -L "$target" ]]; then
    local backup="$target.dotfiles-backup.$(date +%Y%m%d%H%M%S)"
    echo "Backing up $target to $backup"
    mv "$target" "$backup"
  fi
  ln -s "$source_dir" "$target"
  echo "Linked $target"
}

# Drop links to skills that were renamed or removed from this repo.
unlink_stale() {
  local target_root=$1 link
  [[ -d "$target_root" ]] || return 0
  for link in "$target_root"/*(N@); do
    if [[ "$(readlink "$link")" == "$SKILLS_DIR"/* && ! -e "$link" ]]; then
      rm "$link"
      echo "Removed stale link $link"
    fi
  done
}

unlink_stale "$CLAUDE_SKILLS"
for skill in "$SKILLS_DIR"/claude/*(/); do
  link_skill "$skill" "$CLAUDE_SKILLS"
done

unlink_stale "$CODEX_SKILLS"
for skill in "$SKILLS_DIR"/codex/*(/); do
  link_skill "$skill" "$CODEX_SKILLS"
done

# Muse keeps its user skills as managed copies (with a lock file and a content
# scan), so install a symlink-free copy through its own CLI. Rerun this script
# after changing a Muse skill to refresh the installed copy.
if command -v muse >/dev/null 2>&1 || [[ -x "$HOME/.local/bin/muse" ]]; then
  muse_bin=$(command -v muse 2>/dev/null || echo "$HOME/.local/bin/muse")
  mkdir -p "$STATE_DIR"
  installed_list="$STATE_DIR/muse-skills.txt"
  staging=$(mktemp -d)
  trap 'rm -rf "$staging"' EXIT
  current=()
  for skill in "$SKILLS_DIR"/muse/*(/); do
    name=$(basename "$skill")
    current+=("$name")
    cp -RL "$skill" "$staging/$name"
    "$muse_bin" skills install "$staging/$name" --scope user --force >/dev/null
    echo "Installed Muse skill $name"
  done
  if [[ -f "$installed_list" ]]; then
    for name in $(<"$installed_list"); do
      if (( ! ${current[(Ie)$name]} )); then
        "$muse_bin" skills uninstall "$name" >/dev/null && echo "Uninstalled Muse skill $name"
      fi
    done
  fi
  print -l "${current[@]}" > "$installed_list"
else
  echo "Muse Code is not installed; skipping Muse skills"
fi
