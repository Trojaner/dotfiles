#!/bin/zsh
# Ensures a detached tmux session named "claude-rc-@NAME@" is running
# `claude rc` (Remote Control, instance name "@NAME@") in @WORKDIR@.
#
# Idempotent: exits immediately if the session is already up, so it is safe to
# run on a timer. The LaunchAgent com.esozbek.claude-rc-@NAME@ runs it at
# login and every 120s thereafter, which is what recreates the session if it
# ever dies. tmux servers do not survive a reboot on their own.
#
# The restart loop lives in claude-rc-supervisor.sh, shared with any other
# Remote Control agent.

export PATH="@HOME@/.local/bin:@BREW_PREFIX@/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

TMUX_BIN=@BREW_PREFIX@/bin/tmux
SUPERVISOR=@HOME@/.local/bin/claude-rc-supervisor.sh
SESSION="claude-rc-@NAME@"
WORKDIR="@WORKDIR@"
NAME="@NAME@"
LOG_DIR="$HOME/Library/Logs/claude-rc-@NAME@"
LOG="$LOG_DIR/session.log"

mkdir -p "$LOG_DIR"

# -t= forces an exact session-name match; without the "=" tmux prefix-matches
# and would treat any session starting with this name as a hit.
if "$TMUX_BIN" has-session -t="$SESSION" 2>/dev/null; then
  exit 0
fi

if [ ! -x "$SUPERVISOR" ]; then
  echo "$(date '+%Y-%m-%dT%H:%M:%S%z') launcher: FATAL - $SUPERVISOR missing or not executable"
  exit 1
fi

if [ ! -d "$WORKDIR" ]; then
  echo "$(date '+%Y-%m-%dT%H:%M:%S%z') launcher: FATAL - workdir $WORKDIR does not exist"
  exit 1
fi

echo "$(date '+%Y-%m-%dT%H:%M:%S%z') launcher: creating tmux session '$SESSION' in $WORKDIR"

@HOME@/.local/bin/tmux-aqua-ready.sh || exit 1

exec "$TMUX_BIN" new-session -d -s "$SESSION" -c "$WORKDIR" \
  "$SUPERVISOR $NAME $LOG"
