#!/bin/bash

session="$(tmux display -p '_popup_#S')"

if ! tmux has -t "$session" 2> /dev/null; then
  parent_session="$(tmux display -p '#{session_id}')"
  session_id="$(tmux new-session -c '#{pane_current_path}' -dP -s "$session" -F '#{session_id}' -e TMUX_PARENT_SESSION="$parent_session")"
  exec tmux set-option -t "$session_id" key-table popup \; \
    set-option -t "$session_id" status off \; \
    set-option -t "$session_id" prefix None \; \
    attach -t "$session"
fi

exec tmux attach -t "$session" > /dev/null
