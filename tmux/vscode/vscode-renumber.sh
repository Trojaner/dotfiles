#!/bin/sh
tmux list-sessions -F '#{s/[$]//:session_id} #{session_id}' | sort -n | awk '{print NR, $2}' | while read -r n id; do
  tmux set -t "$id" @tab_index "$n"
done
tmux list-clients -F '#{client_name}' | while read -r c; do
  tmux refresh-client -S -t "$c"
done
