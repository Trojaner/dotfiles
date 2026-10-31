# macOS commands

Instance definition: `~/.local/bin/start-claude-rc-$NAME.sh` holds `SESSION` and `WORKDIR`
(`mac-mini` uses the legacy `~/.local/bin/start-claude-rc.sh`, session `claude-rc`, workdir
`~/repos`). LaunchAgent label: `com.esozbek.claude-rc-$NAME` (`com.esozbek.claude-rc` for
`mac-mini`). Logs: `~/Library/Logs/claude-rc-$NAME/`.

All `tmux` commands run outside the sandbox (the tmux socket is blocked inside it). Quote
`=`-prefixed tmux targets (`-t '=claude-rc-palavr'`): in zsh an unquoted `=word` expands to a
command path and fails with "claude-rc-palavr not found". `send-keys` does not accept the `=`
form at all; target the pane as `'<session>:0'`.

1. Pause the LaunchAgent:
   ```sh
   launchctl bootout gui/$(id -u)/com.esozbek.claude-rc-$NAME
   ```
2. Stop the listener, then remove its tmux session inside the supervisor's 5 s backoff:
   ```sh
   tmux send-keys -t "$SESSION:0" C-c
   # poll until `pgrep -f "claude rc --name $NAME"` is empty (about 10 s at most)
   tmux kill-session -t "=$SESSION"
   ```
   `pgrep -fl "claude rc --name $NAME"` must print nothing.
3. Start the revive in its own tmux session:
   ```sh
   L=~/Library/Logs/claude-rc-$NAME/revive.log; : > "$L"
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
6. Resume the LaunchAgent (`RunAtLoad` runs the launcher at once):
   ```sh
   launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.esozbek.claude-rc-$NAME.plist
   ```
   Then `tmux capture-pane -p -t "$SESSION:0"` shows `Capacity: N/32` with the revived
   session's title under it.
