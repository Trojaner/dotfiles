#!/bin/sh
# Usage: claude-rc-launch.sh <name>   (WORKDIR comes from the environment)
#
# Linux launcher for a `claude rc` instance, run by claude-rc@<name>.service.
# Ensures a detached tmux session named "claude-rc-<name>" is running the
# shared supervisor in WORKDIR on the server of tmux-server.service. Exits
# immediately when the session is already up, so it is safe on a timer.
set -u

NAME="$1"
SESSION="claude-rc-$NAME"
SUPERVISOR="$HOME/.local/bin/claude-rc-supervisor.sh"
LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/claude-rc/$NAME"
LOG="$LOG_DIR/session.log"
WORKDIR="${WORKDIR:-}"

mkdir -p "$LOG_DIR"
stamp() { date '+%Y-%m-%dT%H:%M:%S%z'; }

# -t= forces an exact session-name match; without the "=" tmux prefix-matches.
if tmux has-session -t="$SESSION" 2>/dev/null; then
  exit 0
fi

if [ ! -x "$SUPERVISOR" ]; then
  echo "$(stamp) launcher: FATAL - $SUPERVISOR missing or not executable" >> "$LOG_DIR/launcher.log"
  exit 1
fi

if [ -z "$WORKDIR" ] || [ ! -d "$WORKDIR" ]; then
  echo "$(stamp) launcher: FATAL - workdir '$WORKDIR' does not exist" >> "$LOG_DIR/launcher.log"
  exit 1
fi

# Only the tmux-server.service server may host the session: a client that finds
# no server would start a daemonized one inside this oneshot unit, which
# systemd kills when the unit finishes.
if ! systemctl --user is-active --quiet tmux-server.service; then
  echo "$(stamp) launcher: tmux-server.service is not active; refusing to start a daemonized tmux server" >> "$LOG_DIR/launcher.log"
  exit 1
fi
SOCKET="${TMUX_TMPDIR:-/tmp}/tmux-$(id -u)/default"
for _ in $(seq 30); do
  [ -S "$SOCKET" ] && break
  sleep 1
done
if [ ! -S "$SOCKET" ]; then
  echo "$(stamp) launcher: no tmux socket at $SOCKET after 30s" >> "$LOG_DIR/launcher.log"
  exit 1
fi

echo "$(stamp) launcher: creating tmux session '$SESSION' in $WORKDIR" >> "$LOG_DIR/launcher.log"
exec tmux new-session -d -s "$SESSION" -c "$WORKDIR" "$SUPERVISOR $NAME $LOG"
