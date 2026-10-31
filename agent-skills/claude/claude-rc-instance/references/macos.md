# macOS

Files per instance: `~/.local/bin/start-claude-rc-<name>.sh` (launcher) and
`~/Library/LaunchAgents/com.esozbek.claude-rc-<name>.plist` (LaunchAgent). Logs:
`~/Library/Logs/claude-rc-<name>/` (`session.log` from the supervisor, `launchd.log` from the
launcher). Shared: `~/.local/bin/claude-rc-supervisor.sh`, `~/.local/bin/tmux-aqua-ready.sh` and
the tmux server LaunchAgent `com.esozbek.tmux-server`.

## Why the tmux server is a LaunchAgent

A tmux server that starts itself (any `tmux new-session` with no server up) daemonizes into the
Background session, where the login keychain is locked, so `claude rc` under it fails its
keychain lookups. `com.esozbek.tmux-server` runs `tmux -u -D` (foreground) in the Aqua session
instead, and every launcher calls `tmux-aqua-ready.sh` right before `tmux new-session`, giving up
when that server is not running rather than starting a daemonized one.

## Checks before creating

- `~/.local/bin/start-claude-rc-$NAME.sh` and `~/Library/LaunchAgents/com.esozbek.claude-rc-$NAME.plist`
  do not exist, and `tmux has-session -t='claude-rc-$NAME'` fails.
- `launchctl print gui/$(id -u)/com.esozbek.tmux-server` shows `state = running`. If the label
  does not exist (a fresh Mac), install it first (below).

## First instance on a machine

Install the shared pieces once (skip any that exist; never overwrite a running machine's copies):

```sh
S=<this skill's directory>/assets
BREW_PREFIX=$(brew --prefix)
install -m 755 "$S/claude-rc-supervisor.sh" ~/.local/bin/claude-rc-supervisor.sh
install -m 755 "$S/macos/tmux-aqua-ready.sh" ~/.local/bin/tmux-aqua-ready.sh
mkdir -p ~/Library/Logs/tmux-server
sed -e "s|@HOME@|$HOME|g" -e "s|@BREW_PREFIX@|$BREW_PREFIX|g" \
  "$S/macos/com.esozbek.tmux-server.plist" > ~/Library/LaunchAgents/com.esozbek.tmux-server.plist
```

Loading `com.esozbek.tmux-server` (`launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.esozbek.tmux-server.plist`)
starts a persistent process: ask first. If a self-started tmux server is already running in the
Background session, its sessions have to move before the LaunchAgent can own the default socket;
tell the user instead of killing it.

## Create the instance

```sh
S=<this skill's directory>/assets
BREW_PREFIX=$(brew --prefix)
subst() { sed -e "s|@NAME@|$NAME|g" -e "s|@WORKDIR@|$WORKDIR|g" -e "s|@HOME@|$HOME|g" -e "s|@BREW_PREFIX@|$BREW_PREFIX|g" "$1"; }
subst "$S/macos/start-claude-rc.sh" > ~/.local/bin/start-claude-rc-$NAME.sh
chmod +x ~/.local/bin/start-claude-rc-$NAME.sh
mkdir -p ~/Library/Logs/claude-rc-$NAME
subst "$S/macos/com.esozbek.claude-rc.plist" > ~/Library/LaunchAgents/com.esozbek.claude-rc-$NAME.plist
```

The plist keeps `RunAtLoad true` and `StartInterval 120`. After the user confirms:

```sh
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.esozbek.claude-rc-$NAME.plist
```

(Check `launchctl list | grep claude-rc-$NAME` first; use `launchctl load` only if `bootstrap`
reports an already-loaded conflict.)

## Verify

`tmux list-sessions | grep claude-rc-$NAME` shows the session within 120 s, and
`~/Library/Logs/claude-rc-$NAME/session.log` shows `starting claude rc --name $NAME` with no
`exited` line right after it. `tmux attach -t 'claude-rc-$NAME'` shows the live TUI
(detach with the prefix key, then `d`; never Ctrl+C there).

## Stop, start, pause

- Pause re-checks (keeps the running session): `launchctl bootout gui/$(id -u)/com.esozbek.claude-rc-$NAME`
- Resume: `launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.esozbek.claude-rc-$NAME.plist`
  (`RunAtLoad` runs the launcher at once).
- Stop the listener cleanly: `tmux send-keys -t 'claude-rc-$NAME:0' C-c`, wait until
  `pgrep -f "claude rc --name $NAME"` is empty, then `tmux kill-session -t '=claude-rc-$NAME'`
  within the supervisor's 5 s backoff.

Quote `=`-prefixed tmux targets: in zsh an unquoted `=word` expands to a command path.
`send-keys` does not accept the `=` form; target the pane as `'<session>:0'`.

## Removing an instance

```sh
launchctl bootout gui/$(id -u)/com.esozbek.claude-rc-$NAME
rm ~/Library/LaunchAgents/com.esozbek.claude-rc-$NAME.plist
rm ~/.local/bin/start-claude-rc-$NAME.sh
tmux kill-session -t '=claude-rc-$NAME'   # only if the live session should go now too
```
