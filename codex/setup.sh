#!/bin/zsh
set -eu -o pipefail

REPO_DIR=$(cd "$(dirname "$0")/.." && pwd)
CODEX_DIR="${CODEX_HOME:-$HOME/.codex}"
mkdir -p "$CODEX_DIR"
backup_dir=""
for name in config.toml AGENTS.md; do
  source_file="$REPO_DIR/codex/$name"
  target_file="$CODEX_DIR/$name"
  [[ "$target_file" -ef "$source_file" ]] && continue
  if [[ -e "$target_file" || -L "$target_file" ]]; then
    if [[ -z "$backup_dir" ]]; then
      backup_dir=$(mktemp -d "$CODEX_DIR/dotfiles-backup.XXXXXX")
      echo "Backing up existing Codex files to $backup_dir"
    fi
    mv "$target_file" "$backup_dir/$name"
  fi
  ln -s "$source_file" "$target_file"
done
