#!/bin/sh
# Supervisor loop for a `claude rc` (Remote Control) agent.
#
# Usage: claude-rc-supervisor.sh <name> <logfile>
#
# Runs `claude rc` forever, restarting it with exponential backoff if it exits
# (network blip, transient auth failure at login, crash). Keeping the loop in
# the pane is what stops tmux from tearing the session down when the command
# exits. The TUI stays on the pane so `tmux attach` shows the live UI; only
# supervisor events go to the log, because teeing the TUI would append its
# full-screen repaints at ~28 MiB/day.
#
# Session continuity across restarts: a plain `claude rc` started in the same
# directory brings back every session the previous server was serving (for
# about four hours after it stopped), so the sessions spawned from claude.ai
# come back online on their own once this loop restarts the server. Do NOT pass
# --no-create-session-in-dir: with it, Claude Code archives all of the
# server's sessions when the server stops, leaving nothing to bring back. The
# cost is one pre-created session per instance in the session list.
#
# Killed child sessions: the server itself re-serves a crashed or killed child
# the next time a message is sent to it (Claude Code >= 2.1.238), so no
# per-child respawning is needed here. Never start a second `claude rc`
# (e.g. --session-id) in the same directory to revive one: a second server in
# the directory makes Claude Code archive sessions instead of restoring them.
set -u

NAME="$1"
LOG="$2"

# A run lasting at least this long counts as healthy and resets the backoff, so
# a crash after days of uptime restarts in 5s instead of the 60s ceiling, which
# keeps the window where its sessions are offline short.
HEALTHY_RUN_SECS=300

delay=5
while true; do
  echo "$(date '+%Y-%m-%dT%H:%M:%S%z') starting claude rc --name $NAME" >> "$LOG"
  started=$(date +%s)
  claude rc \
    --name "$NAME" \
    --remote-control-session-name-prefix "$NAME" \
    --permission-mode auto \
    --spawn same-dir
  code=$?
  if [ $(( $(date +%s) - started )) -ge "$HEALTHY_RUN_SECS" ]; then
    delay=5
  fi
  echo "$(date '+%Y-%m-%dT%H:%M:%S%z') claude rc exited (code $code); restarting in ${delay}s" >> "$LOG"
  sleep "$delay"
  # Back off up to 60s so a persistent failure does not spin hot. The clamp
  # after doubling is what actually holds the ceiling at 60s: testing only
  # "delay < 60" before doubling lets the value overshoot to 80s and stay there.
  if [ "$delay" -lt 60 ]; then
    delay=$((delay * 2))
    [ "$delay" -gt 60 ] && delay=60
  fi
done
