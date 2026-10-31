---
name: claude-rc-revive
description: "Use when the user runs /claude-rc-revive <url> or asks to revive, bring back or reconnect an offline or archived Remote Control session (a claude.ai/code/session_... or cse_... URL) that was served by one of this machine's `claude rc` instances (macOS, Linux or Windows; on the Mac mini: mac-mini, eksenova, palavr, sellersgo-be, sellersgo-fe). Temporarily stops the owning instance, reattaches the session with `claude rc --session-id`, then hands it back to the instance's listener."
metadata:
  argument-hint: "<claude.ai/code session url> [instance-name]"
---

# claude-rc-revive

Brings an offline or archived Remote Control session back online on this machine and returns it
to the `claude rc` instance that owns its directory. Instances, launchers, supervisors and the
OS schedulers are described in the `claude-rc-instance` skill; read its "Session continuity"
section first if unsure why a session went offline.

Background (Remote Control docs, "Resume sessions after stopping the server"):
`claude rc --session-id <id>` brings back one session, including an archived one (it unarchives
it on Claude Code >= 2.1.228), but only within about four hours of the server that served it
stopping, and only when run in the session's directory. A directory can be served by only one
`claude rc` at a time: a second one fails with "This folder is already served by a terminal
`claude remote-control` on this device. Stop it first." So the owning instance must be stopped
for the duration of the revive.

## Inputs

- `URL`: the session URL. The ID is the path segment after `/code/`, before any `?`
  (`https://claude.ai/code/session_01Gr5nw8N5i9X7jBrUbTkFVM` gives
  `session_01Gr5nw8N5i9X7jBrUbTkFVM`). Reject anything that is not a `session_...` or `cse_...`
  ID.
- `NAME`: the instance whose directory the session ran in. If not given, infer it:
  - from the session's title or prefix in `ListAgents` (instance sessions are named `<NAME>-xx`
    until auto-titled);
  - from its local transcript: rc children are `entrypoint: "sdk-cli"` transcripts under
    `~/.claude/projects/<dir-slug>/`; match on the first prompt or topic the user describes.
  If it is still ambiguous, ask the user which instance; never guess between directories.
- `WORKDIR`: the instance's directory, from its OS-specific definition (see the reference).

## Procedure

Read the reference for the OS you are on first; it has the exact commands for every step:
[references/macos.md](references/macos.md), [references/linux.md](references/linux.md),
[references/windows.md](references/windows.md).

Tell the user up front that the instance's other sessions go offline for the few minutes this
takes (they come back with it in step 6). The user invoking this skill is the consent for
stopping and restarting that one instance; touch no other instance.

1. **Pause the instance's scheduler** (LaunchAgent, systemd timer or scheduled task), so its
   two-minute re-check does not recreate the listener in the middle of the revive. This does not
   stop the running listener.
2. **Stop the listener cleanly with Ctrl+C**, then make sure its supervisor cannot restart it
   (remove the tmux session within the supervisor's 5 s backoff; on Windows the loop ends with
   it). Confirm no `claude rc --name <NAME>` process is left. Never hard-kill it unless Ctrl+C
   failed, and say so if you had to.
3. **Start the revive with a retry loop** in the instance's directory, detached from your own
   shell: `claude rc --session-id <ID> --permission-mode auto`, retried every 20 s up to about
   15 times. Right after a server stops, the "already served" error persists for about 2-4
   minutes until a server-side lock clears. Log each attempt to `revive.log` in the instance's
   log directory.
4. **Verify it is back.** Wait until the latest attempt has stayed up for about 40 s, then check
   that the revive shows the session (the reference says how) and that `ListAgents` no longer
   lists the session as offline. If every attempt fails with "already served", look for a live
   process still serving the directory (`~/.claude/sessions/*.json`); if the error is different
   (for example the session expired after about four hours), stop, report it, and go to step 6
   so the instance is not left down.
5. **Hand the session back.** The single-session revive server blocks the directory, so stop it
   with Ctrl+C and end its retry loop before it can retry (a Ctrl+C exit can be non-zero, which
   would make the loop reattach).
6. **Resume the instance's scheduler**, which starts the listener at once. It brings back every
   session the previous server in that directory was serving, which includes the revived one.
   (On 2026-10-06 the hand-back from a cleanly stopped revive server started on the first
   attempt; the "already served" lock was only hit going the other way, in step 3. If it does
   hit, the supervisor retries with backoff up to 60 s.) Wait until the last `starting` line in
   the instance's `session.log` is two or more minutes old, then confirm with `ListAgents` that
   the session is no longer offline (and on macOS and Linux that the instance's TUI lists it
   under `Capacity: N/32`).
7. **Report**: the session ID and URL, whether it is online and under which instance, how long
   the instance was down, and anything that did not go as described.
