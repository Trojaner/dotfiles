#!/bin/sh
client=$1
index=$2
target=$(tmux list-sessions -F '#{@tab_index} #{session_id}' | awk -v n="$index" '$1 == n { print $2; exit }')
if [ -n "$target" ]; then
  tmux switch-client -c "$client" -t "$target"
else
  tmux display -c "$client" "No tab $index"
fi
