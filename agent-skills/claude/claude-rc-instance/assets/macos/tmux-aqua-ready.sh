#!/bin/zsh
# Waits for the launchd-owned tmux server (com.esozbek.tmux-server, `tmux -D`
# in the Aqua session) before a launcher creates a session on it.
#
# A tmux server that starts itself (any `tmux new-session` with no server up)
# daemonizes into the Background session, where the login keychain is locked
# and every process under it fails keychain lookups. Launchers call this right
# before `tmux new-session` and give up when it fails, so they never start that
# daemonized server; the LaunchAgent is the only thing that starts tmux.

LABEL="com.esozbek.tmux-server"
SOCKET="/private/tmp/tmux-$(id -u)/default"
WAIT_SECS="${TMUX_AQUA_WAIT_SECS:-60}"

for _ in $(seq "$WAIT_SECS"); do
  if launchctl print "gui/$(id -u)/$LABEL" 2>/dev/null | grep -q 'state = running' \
      && [ -S "$SOCKET" ]; then
    exit 0
  fi
  sleep 1
done

echo "$(date '+%Y-%m-%dT%H:%M:%S%z') tmux-aqua-ready: $LABEL not running after ${WAIT_SECS}s; refusing to start a daemonized tmux server" >&2
exit 1
