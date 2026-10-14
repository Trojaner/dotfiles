#!/bin/sh
s=$1
[ -n "$s" ] || exit 0
tmux list-clients -t "$s" -F '#{client_flags}' | grep -q focused && exit 0
tmux set -t "$s" -F @bell '#{session_activity}'
if [ "$(tmux display -p -t "$s" '#{session_attached}')" = 0 ]; then
  owner=$(tmux show -t "$s" -v @owner 2>/dev/null)
  ttys=$(tmux list-clients -F '#{client_name} #{client_tty}' | awk -v o="$owner" '$1 == o { print $2 }')
  [ -n "$ttys" ] || ttys=$(tmux list-clients -F '#{client_tty}')
  for t in $ttys; do printf '\a' > "$t"; done
fi
tmux list-clients -F '#{client_name}' | while read -r c; do tmux refresh-client -S -t "$c"; done
