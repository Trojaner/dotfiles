---
name: claude-rc-instance
description: "Use when the user wants a new `claude rc` (Remote Control) autostart instance for a repo on macOS, Linux or Windows: a persistent, login- or boot-launched, auto-restarting Remote Control listener reachable from claude.ai/code or the Claude mobile app for that repo, whose spawned sessions come back after a server restart or child crash. Also covers why rc sessions went offline or were archived and how to keep them alive. Scaffolds the launcher, the supervisor and the OS scheduler entry (LaunchAgent, systemd user units, or a Task Scheduler task) from this skill's templates."
---

# claude-rc-instance

Scaffolds a new `claude rc` (Remote Control) autostart instance: a supervised `claude rc` that
restarts on crash or exit, is started at login (or boot) and is re-checked every 120 seconds by
the OS scheduler. This is machine-local automation under `~/.local/bin` and the OS's scheduler
locations, built from the templates in `assets/`. The instances themselves are not checked into
any repo; this skill lives in the dotfiles repo (`agent-skills/claude/claude-rc-instance`).

## When to use

The user asks to "add a claude rc instance for `<repo>`", "set up remote control autostart for
`<repo>`", or similar: a new named `claude rc` listener that survives reboots and logins and is
reachable from claude.ai/code or the mobile app.

## Platforms

| OS | Holds the TUI | Restart loop | Starts and re-checks it | Steps |
| --- | --- | --- | --- | --- |
| macOS | tmux session on the launchd-owned `tmux -D` server (`com.esozbek.tmux-server`) | `claude-rc-supervisor.sh` | LaunchAgent `com.esozbek.claude-rc-<name>` (`RunAtLoad`, `StartInterval 120`) | [references/macos.md](references/macos.md) |
| Linux | tmux session on the `tmux -D` server of the systemd user unit `tmux-server.service` | `claude-rc-supervisor.sh` | `claude-rc@<name>.timer` (boot, then every 120 s) running `claude-rc@<name>.service` | [references/linux.md](references/linux.md) |
| Windows | minimized console window titled `claude-rc-<name>` | `claude-rc-supervisor.ps1` | Task Scheduler task `claude-rc-<name>` (at logon, repeated every 2 min, `IgnoreNew`) | [references/windows.md](references/windows.md) |

Read the reference for the OS you are on (`uname -s`: `Darwin` or `Linux`; Windows when
`$env:OS` is `Windows_NT`) before creating anything.

## Existing instances on the Mac mini (do not duplicate)

- `mac-mini`: `~/repos`. Legacy inline script (`start-claude-rc.sh`) that predates the shared
  supervisor; do not copy it.
- `eksenova`: `~/repos/eksenova/eksenova`
- `palavr`: `~/palavr`
- `sellersgo-be`: `~/repos/ayomsoft/sellersgo-be`
- `sellersgo-fe`: `~/repos/ayomsoft/sellersgo-fe`

Every instance except `mac-mini` runs the shared supervisor (`~/.local/bin/claude-rc-supervisor.sh`,
or `claude-rc-supervisor.ps1` on Windows). **New instances use the shared supervisor too**;
never write an inline supervisor loop per instance.

## Steps (all platforms)

Given a `NAME` (short, lowercase, matches the repo's own naming) and a `WORKDIR` (absolute path
to the repo):

1. **Verify prerequisites** before creating anything:
   - `WORKDIR` exists.
   - `claude` is installed for this user (`claude --version`) and signed in.
   - `claude` has already been run once in `WORKDIR` interactively, so the workspace-trust
     dialog has been accepted (Remote Control refuses to run otherwise). If unsure, ask the user
     to confirm, or run `claude` there yourself first.
   - No instance with this `NAME` exists yet (the OS reference lists what to check).

2. **Install the shared supervisor** if the machine has none yet, from `assets/` (the OS
   reference says which file and where). If it exists, leave it alone: it is shared by every
   instance on the machine.

3. **Create the per-instance files** from the OS templates, substituting the placeholders
   (`@NAME@`, `@WORKDIR@`, `@HOME@`, `@BREW_PREFIX@`). Only the substituted values differ from
   the templates; keep their structure, idempotency checks and guards.

4. **Do not edit the supervisor per instance.** It runs
   `claude rc --name <name> --remote-control-session-name-prefix <name> --permission-mode auto --spawn same-dir`
   with the default pre-created session, which is what lets sessions survive a server restart
   (see "Session continuity"). Changing its flags changes every instance on the machine; that is
   the user's decision, not a default. Never add `--no-create-session-in-dir`: it makes Claude
   Code archive every session the server was serving whenever it stops.

5. **Before starting anything persistent** (loading the LaunchAgent, enabling the systemd units,
   registering the scheduled task, enabling lingering), tell the user what was created and ask
   for confirmation. These start long-running background processes, and side-effecting or
   persistent actions need explicit consent on this user's machines.

6. **Verify** as the OS reference describes: the instance is running within about two minutes,
   and its `session.log` shows `starting claude rc` without an immediate `exited` line.

## Session continuity

How sessions spawned from claude.ai/code survive the things that kill them (Remote Control docs,
"Resume sessions after stopping the server" and "Limitations"):

- **Server restarted** (supervisor restart, tmux session or console killed, launcher recreated
  it): a plain `claude rc` in the same directory brings back every session the previous server
  was serving, for about four hours after it stopped. The supervisor restarts within seconds, so
  sessions come back online by themselves. This only works because the supervisor does **not**
  pass `--no-create-session-in-dir`; with that flag Claude Code archives the sessions on stop and
  there is nothing to bring back (this is how sessions were lost on 2026-10-06).
- **A single child session killed or crashed** while the server keeps running: the server
  re-serves it the next time a message is sent to it from claude.ai/code or the app (Claude Code
  >= 2.1.238). No per-child respawn script is needed. Idle children also exit on their own after
  about an hour and come back the same way.
- **Server down for more than about four hours** (machine off, long outage): sessions can no
  longer be brought back by the server; reopen them from claude.ai/code as new work.

Never start a second `claude rc` in an instance's directory to revive one session
(`--session-id`, `--continue`) while the instance is running: the docs make restoring
conditional on there being no other `claude rc` in the same directory, so a second server risks
archiving the instance's sessions (the CLI also refuses: "This folder is already served by a
terminal `claude remote-control` on this device"). To revive a specific offline or archived
session, use the `claude-rc-revive` skill (`/claude-rc-revive <url>`), which stops the owning
instance, reattaches the session and hands it back to the instance's listener.

## Restarting a running instance: avoid it

Each restart briefly takes every session of that instance offline, and killing the server
leaves a server-side "already served" lock for about 2-4 minutes, during which the supervisor
fails with exit code 1 (backing off up to 60 s) until the lock clears. Sessions come back once
it starts successfully, but do not restart a running instance unless you have to, and never
kill and recreate it repeatedly. A supervisor change only takes effect after the instance's
tmux session (or Windows console) is recreated, because the running loop has already parsed the
old script.

## Removing an instance

Reverse of the creation steps in the OS reference ("Removing an instance"). Confirm with the
user before each destructive step.
