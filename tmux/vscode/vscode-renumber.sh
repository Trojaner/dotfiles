#!/bin/sh
order=$(tmux list-sessions -F '#{?@tab_order,#{@tab_order},999999} #{s/[$]//:session_id} #{session_id}' | sort -n -k1,1 -k2,2 | awk '{print NR, $3}')
slots=
while read -r n id; do
  [ -n "$id" ] || continue
  tmux set -t "$id" @tab_index "$n" \; set -t "$id" @tab_order "$n"
  slots="$slots#{S:#{?#{==:#{@tab_index},$n},#{E:@tab} ,},#{?#{==:#{@tab_index},$n},#{E:@tab_current} ,}}"
done <<EOF
$order
EOF
tmux set -g @tab_slots "$slots"
tmux list-clients -F '#{client_name}' | while read -r c; do
  tmux refresh-client -S -t "$c"
done
