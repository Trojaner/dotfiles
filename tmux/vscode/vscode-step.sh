#!/bin/sh
client=$1
step=$2
current=$(tmux display -p -c "$client" '#{@tab_index}')
count=$(tmux list-sessions | wc -l | tr -d ' ')
[ -n "$current" ] && [ "$count" -gt 1 ] || exit 0
next=$(( (current - 1 + step + count) % count + 1 ))
exec "$(dirname "$0")/vscode-goto.sh" "$client" "$next"
