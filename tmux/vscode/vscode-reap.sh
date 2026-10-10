#!/bin/sh
gone=$1
[ -n "$gone" ] || exit 0
tmux list-sessions -F '#{session_id}|#{@owner}|#{@permanent}' | while IFS='|' read -r id owner perm; do
  [ "$owner" = "$gone" ] || continue
  [ -n "$perm" ] && continue
  viewer=$(tmux list-clients -t "$id" -F '#{client_name}' | grep -vxF "$gone" | head -n 1)
  if [ -n "$viewer" ]; then
    tmux set -t "$id" @owner "$viewer"
  else
    tmux kill-session -t "$id"
  fi
done
