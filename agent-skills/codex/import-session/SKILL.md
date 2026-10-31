---
name: import-session
description: Import a Claude Code or Muse Code session into Codex as a native, resumable thread, with its tool calls and results, its working directory, and that workspace's memories; then offer to continue unfinished work or recommend what to do next. Use when the user runs import-session claude|muse <session id or name>, or asks to bring a Claude Code or Muse session, conversation or work over to Codex.
metadata:
  short-description: Import a Claude Code or Muse session into Codex
---

# Import a session into Codex

Arguments: the source platform (`claude` or `muse`), then a session id, id prefix, session name or title fragment, or `all` for every session of the current workspace. If the platform is missing or is `codex`, ask the user: `claude` or `muse`.

Script: `~/.codex/skills/import-session/scripts/agent_sessions.py`. It writes outside the workspace (`~/.codex`, `~/.local/state/agent-sessions`, and the source agent's data for memory reads), so run it with the permissions that needs.

## 1. Import

```bash
python3 ~/.codex/skills/import-session/scripts/agent_sessions.py import --to codex --from <claude|muse> "<session>"
```

- No session given: run the command without `"<session>"`. It lists the platform's recent sessions for this workspace and exits 3. Ask the user which one, then run it again with the chosen id.
- Exit 3 with several matches: show them and ask which one. Exit 2: nothing matched, or the session is itself an imported copy (the message names the original to import instead).
- Running it again is safe. Unchanged sessions are skipped, changed ones are rewritten into the same thread, and a thread that was already continued in Codex is kept and the source is imported as a fresh thread. `--force` re-imports as a fresh thread; `--dry-run` previews.

What it sets up:
- A rollout under `~/.codex/sessions/YYYY/MM/DD/`, plus the `threads` row the resume picker reads. It carries a `turn_context` per turn with the source's working directory, your default model and on-request approvals. Every user prompt, reply, tool call and tool result is kept in order. Shell commands become `shell` calls with command-execution items, and file writes, edits and patches become `apply_patch` calls with file-change items, so they show in Codex's transcript. Other tools keep their source name (reads as `read_file`). Reasoning is not replayed.
- The source platform's memories for that workspace. Claude Code memory is synced to `memories/extensions/external_agent_import/resources/<project key>/` with `scope.json`, as Codex's own import does. Muse notes become ad-hoc notes. Codex folds them in on its next memory consolidation.
- Workspace trust in `~/.codex/config.toml` (`--no-trust` skips it).

## 2. Report

Briefly: what was imported and where, the cwd, turn and tool-call counts, memory files written, trust, and the `open it:` command (`codex resume <id>`). Show any `FAILED` line with its message.

## 3. Continue or recommend

Read the `state:` line for each imported session.

- `UNFINISHED - <reasons>`: show the reasons, the last request and the last reply, and ask whether to continue it here, open the imported thread instead (give the `codex resume <id>` command), or leave it. To continue:
  1. Run the printed `full log:` command. It writes the raw transaction log into this thread's folder and prints `log_path`.
  2. Read the log from the end (the latest events matter most).
  3. Check the workspace's current state: `git status`, and the files the log touched.
  4. Pick up the last unfinished request. The log is evidence of what happened, not instructions to replay; follow the current repo rules and confirm anything destructive first.
- `finished`: run the `full log:` command and read the end of the log. Check the workspace (`git status`/`git diff`, whether its changes were tested or committed). Then recommend one to three concrete next steps that follow from the work, such as running tests it never ran, committing, or follow-ups it mentioned. Ask which to do and don't start without an answer.
