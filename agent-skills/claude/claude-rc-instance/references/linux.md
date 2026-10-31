# Linux

Runs on any distribution with a systemd user manager and tmux 3.2 or later (`tmux -D` needs it).
WSL2 counts when `systemd=true` is set under `[boot]` in `/etc/wsl.conf` (the dotfiles setup
does this).

Files per instance: `~/.config/claude-rc/<name>.env` (`WORKDIR=...`) plus the enabled timer
`claude-rc@<name>.timer`. Logs: `~/.local/state/claude-rc/<name>/` (`session.log` from the
supervisor, `launcher.log` from the launcher) and `journalctl --user -u 'claude-rc@<name>*'`.

Shared, installed once per machine:

| File | From |
| --- | --- |
| `~/.local/bin/claude-rc-supervisor.sh` | `assets/claude-rc-supervisor.sh` (the same POSIX script as on macOS) |
| `~/.local/bin/claude-rc-launch.sh` | `assets/linux/claude-rc-launch.sh` |
| `~/.config/systemd/user/tmux-server.service` | `assets/linux/tmux-server.service` |
| `~/.config/systemd/user/claude-rc@.service` | `assets/linux/claude-rc@.service` |
| `~/.config/systemd/user/claude-rc@.timer` | `assets/linux/claude-rc@.timer` |

## Why a tmux server unit

The launcher runs as a oneshot service. A `tmux new-session` that finds no server starts a
daemonized one inside that oneshot's cgroup, and systemd kills everything left in the cgroup
when the oneshot finishes, taking `claude rc` with it. `tmux-server.service` runs `tmux -u -D`
in the foreground as its own unit, so every instance's session belongs to that unit and outlives
the launcher. The launcher refuses to run when the unit is not active. This mirrors
`com.esozbek.tmux-server` on macOS.

Instances share the default tmux socket (`/tmp/tmux-<uid>/default`) with interactive tmux use.
If the user already runs a self-started tmux server on that socket, `tmux-server.service` fails
to start (the socket is taken); tell the user instead of killing their server.

## Checks before creating

- `~/.config/claude-rc/$NAME.env` does not exist, `systemctl --user list-timers 'claude-rc@*'`
  does not list `$NAME`, and `tmux has-session -t='claude-rc-$NAME'` fails.
- `tmux -V` is 3.2 or later and `command -v claude` resolves for this user (the units put
  `~/.local/bin`, `/usr/local/bin`, `/usr/bin` and `/bin` on `PATH`; if `claude` lives elsewhere,
  say so and adjust the `Environment=PATH=` lines).
- `loginctl show-user "$USER" -p Linger` says `Linger=yes` when the instance must run without
  anyone logged in (a headless server). Without lingering the user manager, and with it every
  instance, only runs while the user has a session.

## First instance on a machine

```sh
S=<this skill's directory>/assets
install -D -m 755 "$S/claude-rc-supervisor.sh" ~/.local/bin/claude-rc-supervisor.sh
install -D -m 755 "$S/linux/claude-rc-launch.sh" ~/.local/bin/claude-rc-launch.sh
install -D -m 644 "$S/linux/tmux-server.service" ~/.config/systemd/user/tmux-server.service
install -D -m 644 "$S/linux/claude-rc@.service" ~/.config/systemd/user/claude-rc@.service
install -D -m 644 "$S/linux/claude-rc@.timer" ~/.config/systemd/user/claude-rc@.timer
systemctl --user daemon-reload
```

After the user confirms (persistent processes, and lingering is a system setting):

```sh
sudo loginctl enable-linger "$USER"          # only for headless machines, and only if Linger=no
systemctl --user enable --now tmux-server.service
```

## Create the instance

```sh
mkdir -p ~/.config/claude-rc
printf 'WORKDIR=%s\n' "$WORKDIR" > ~/.config/claude-rc/$NAME.env
```

After the user confirms:

```sh
systemctl --user enable --now claude-rc@$NAME.timer
systemctl --user start claude-rc@$NAME.service   # run the launcher now instead of in 15 s
```

## Verify

`systemctl --user status claude-rc@$NAME.service` ends with `status=0/SUCCESS`,
`tmux list-sessions | grep claude-rc-$NAME` shows the session, and
`~/.local/state/claude-rc/$NAME/session.log` shows `starting claude rc --name $NAME` with no
`exited` line right after it. `tmux attach -t 'claude-rc-$NAME'` shows the live TUI (detach with
the prefix key, then `d`; never Ctrl+C there).

## Stop, start, pause

- Pause re-checks (keeps the running session): `systemctl --user stop claude-rc@$NAME.timer`
- Resume: `systemctl --user start claude-rc@$NAME.timer && systemctl --user start claude-rc@$NAME.service`
- Stop the listener cleanly: `tmux send-keys -t "claude-rc-$NAME:0" C-c`, wait until
  `pgrep -f "claude rc --name $NAME"` is empty, then `tmux kill-session -t "=claude-rc-$NAME"`
  within the supervisor's 5 s backoff.
- Never `systemctl --user restart tmux-server.service`: it ends every instance's session at once.

## Removing an instance

```sh
systemctl --user disable --now claude-rc@$NAME.timer
rm ~/.config/claude-rc/$NAME.env
tmux kill-session -t "=claude-rc-$NAME"   # only if the live session should go now too
```

The shared units stay for the machine's other instances. When the last instance is gone,
`systemctl --user disable --now tmux-server.service` stops the server, which also ends any
interactive tmux sessions on the default socket: ask first.
