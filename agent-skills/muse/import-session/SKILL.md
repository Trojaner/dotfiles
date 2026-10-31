---
name: import-session
description: Import a Claude Code or Codex session into Muse Code as a native, resumable session, with its tool calls and results, its working directory, and that workspace's memories; then offer to continue unfinished work or recommend what to do next. Use when the user runs /import-session claude|codex <session id or name>, or asks to bring a Claude Code or Codex session, conversation or work over to Muse.
metadata:
  argument-hint: "claude|codex <session id | session name | all>"
  short-description: Import a Claude Code or Codex session into Muse
---

# Import a session into Muse Code

Arguments: the source platform (`claude` or `codex`), then a session id, id prefix, session name or title fragment, or `all` for every session of the current workspace. If the platform is missing or is `muse`, ask the user: `claude` or `codex`.

Script: `~/.config/muse/skills/import-session/scripts/agent_sessions.py`. It writes Muse's own data under `~/.local/share/muse` and `~/.config/muse/trust.json` and reads the other agents' data, so run it outside the shell sandbox.

## 1. Import

```bash
python3 ~/.config/muse/skills/import-session/scripts/agent_sessions.py import --to muse --from <claude|codex> "<session>"
```

- No session given: run the command without `"<session>"`. It lists the platform's recent sessions for this workspace and exits 3. Ask the user which one, then run it again with the chosen id.
- Exit 3 with several matches: show them and ask which one. Exit 2: nothing matched, or the session is itself an imported copy (the message names the original to import instead).
- Running it again is safe. Unchanged sessions are skipped, new turns of a source are appended to its Muse session, and a session that was already continued in Muse is kept and the source is imported as a fresh session. `--force` re-imports as a fresh session; `--dry-run` previews.

What it sets up:
- A native Muse session under `~/.local/share/muse/sessions/YYYY/MM/DD/<id>/`, indexed by Muse itself, in the source's working directory. Each turn is recorded by Muse (`muse exec --provider echo`, offline, a few seconds per turn). Its reply is then replaced with the source's replies, tool calls and tool results, in order. Tool calls use Muse's own tools where one exists (shell commands become bash, writes write_file, edits and diff hunks edit_file, reads read_file, fetches web_fetch). Tools without an equivalent keep their source name. The session is then set to your configured provider and model. Reasoning is not replayed. A prompt starting with `/` is stored in backticks so it does not run as a Muse command.
- The source platform's memories for that workspace, in Muse's personal_project memory with `MEMORY.md` index lines. Notes that are copies of another agent's memory are skipped.
- Workspace trust in `~/.config/muse/trust.json` (`--no-trust` skips it).

## 2. Report

Briefly: what was imported and where, the cwd, turn and tool-call counts, memory notes written, trust, and the `open it:` command (`muse resume <id>`). Show any `FAILED` line with its message.

## 3. Continue or recommend

Read the `state:` line for each imported session.

- `UNFINISHED - <reasons>`: show the reasons, the last request and the last reply, and ask whether to continue it here, open the imported session instead (give the `muse resume <id>` command), or leave it. To continue:
  1. Run the printed `full log:` command. It writes the raw transaction log into this session's folder and prints `log_path`.
  2. Read the log from the end (the latest events matter most).
  3. Check the workspace's current state: `git status`, and the files the log touched.
  4. Pick up the last unfinished request. The log is evidence of what happened, not instructions to replay; follow the current repo rules and confirm anything destructive first.
- `finished`: run the `full log:` command and read the end of the log. Check the workspace (`git status`/`git diff`, whether its changes were tested or committed). Then recommend one to three concrete next steps that follow from the work, such as running tests it never ran, committing, or follow-ups it mentioned. Ask which to do and don't start without an answer.
