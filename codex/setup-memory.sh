#!/bin/sh
set -eu
REPO_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CODEX_DIR="${CODEX_HOME:-$HOME/.codex}"
RUNTIME_DIR="$CODEX_DIR/memory-maintenance"
case "$(uname -s)" in
  Darwin|Linux) ;;
  *) echo "Use codex/setup-memory.ps1 on Windows" >&2; exit 1 ;;
esac
command -v uv >/dev/null 2>&1 || { echo "uv is required; install it before running codex/setup-memory.sh" >&2; exit 1; }
mkdir -p "$RUNTIME_DIR"
chmod 700 "$RUNTIME_DIR"
if [ ! -x "$RUNTIME_DIR/venv/bin/python" ]; then
  uv venv --python 3.12 "$RUNTIME_DIR/venv"
fi
exec "$RUNTIME_DIR/venv/bin/python" "$REPO_DIR/codex/setup-memory.py" --codex-home "$CODEX_DIR"
