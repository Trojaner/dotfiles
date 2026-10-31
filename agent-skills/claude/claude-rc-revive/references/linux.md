# Linux commands

Instance definition: `~/.config/claude-rc/$NAME.env` holds `WORKDIR`; the tmux session is
`SESSION=claude-rc-$NAME` on the server of `tmux-server.service`; the scheduler is
`claude-rc@$NAME.timer`. Logs: `~/.local/state/claude-rc/$NAME/`.

```sh
. ~/.config/claude-rc/$NAME.env      # sets WORKDIR
SESSION=claude-rc-$NAME
LOGDIR=${XDG_STATE_HOME:-$HOME/.local/state}/claude-rc/$NAME
```

Run `tmux` outside any sandbox that hides `/tmp/tmux-<uid>/`.

1. Pause the timer:
   ```sh
   systemctl --user stop claude-rc@$NAME.timer
   ```
2. Stop the listener, then remove its tmux session inside the supervisor's 5 s backoff:
   ```sh
   tmux send-keys -t "$SESSION:0" C-c
   # poll until `pgrep -f "claude rc --name $NAME"` is empty (about 10 s at most)
   tmux kill-session -t "=$SESSION"
   ```
   `pgrep -fl "claude rc --name $NAME"` must print nothing.
   If `kill-session` reports that the session does not exist, the supervisor already ended with
   the listener (it happens when a Ctrl+C reaches the pane as a signal); that is fine.
3. Start the revive in its own tmux session on the same server, so it outlives your shell:
   ```sh
   L=$LOGDIR/revive.log; : > "$L"
   tmux new-session -d -s "$SESSION-revive" -c "$WORKDIR" \
     "for i in \$(seq 1 15); do echo \"attempt \$i \$(date +%T)\" >> $L; \
        claude rc --session-id $ID --permission-mode auto && break; sleep 20; done; \
      echo 'loop done' >> $L; sleep 600"
   ```
   Do not log `$?` after a `$(date ...)` substitution in that loop; the substitution resets it.
4. Verify: `tmux capture-pane -p -t "$SESSION-revive:0"` shows the session title with
   "Single session · exits when complete" and the session URL.
5. Hand back:
   ```sh
   tmux send-keys -t "$SESSION-revive:0" C-c
   # poll until `pgrep -f "claude rc --session-id"` is empty
   tmux kill-session -t "=$SESSION-revive"
   ```
6. Resume the timer and run the launcher now:
   ```sh
   systemctl --user start claude-rc@$NAME.timer
   systemctl --user start claude-rc@$NAME.service
   ```
   Then `tmux capture-pane -p -t "$SESSION:0"` shows `Capacity: N/32` with the revived
   session's title under it.
