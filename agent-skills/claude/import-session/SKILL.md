---
name: import-session
description: Import a Codex or Muse Code session into Claude Code as a native, resumable session, with its tool calls and results, its working directory, and that workspace's memories; then offer to continue unfinished work or recommend what to do next. Use when the user runs /import-session codex|muse <session id or name>, or asks to bring a Codex or Muse session, conversation or work over to Claude Code.
metadata:
  argument-hint: "codex|muse <session id | session name | all>"
---

# Import a session into Claude Code

Arguments: the source platform (`codex` or `muse`), then a session id, id prefix, session name or title fragment, or `all` for every session of the current workspace. If the platform is missing or is `claude`, ask with AskUserQuestion: `codex` or `muse`.

Script: `~/.claude/skills/import-session/scripts/agent_sessions.py`

## 1. Import

```bash
python3 ~/.claude/skills/import-session/scripts/agent_sessions.py import --to claude --from <codex|muse> "<session>"
```

- No session given: run the command without `"<session>"`. It lists the platform's recent sessions for this workspace and exits 3. Ask the user which one with AskUserQuestion, then run it again with the chosen id.
- Exit 3 with several matches: show them and ask which one. Exit 2: nothing matched, or the session is itself an imported copy (the message names the original to import instead).
- Running it again is safe. Unchanged sessions are skipped, changed ones are updated in place, and a session that was already continued in Claude Code is kept and the source is imported as a fresh copy. `--force` re-imports as a fresh copy; `--dry-run` previews.

What it sets up:
- The session at `~/.claude/projects/<cwd as key>/<id>.jsonl`, with the source's working directory and git branch. Every user prompt, reply, tool call and tool result is kept in order. Tool calls use Claude Code's own tools where one exists (shell commands become Bash, file writes Write, edits and diff hunks Edit, reads Read, fetches WebFetch). Tools without an equivalent keep their source name. Reasoning is not replayed.
- The source platform's memories for that workspace, in this project's auto memory with `MEMORY.md` index lines. Notes that are copies of another agent's memory are skipped.
- Workspace trust in `~/.claude.json` (`--no-trust` skips it).

## 2. Report

Briefly: what was imported and where, the cwd, turn and tool-call counts, memory notes written, trust, and the `open it:` command (`claude --resume <id>`). Show any `FAILED` line with its message.

## 3. Continue or recommend

Read the `state:` line for each imported session.

- `UNFINISHED - <reasons>`: show the reasons, the last request and the last reply. Ask with AskUserQuestion whether to continue it, with the options "Continue here (Recommended)", "Open the imported session instead" (give the `claude --resume <id>` command), and "Not now". To continue:
  1. Run the printed `full log:` command. It writes the raw transaction log into this session's folder and prints `log_path`.
  2. Read the log from the end (the latest events matter most).
  3. Check the workspace's current state: `git status`, and the files the log touched.
  4. Pick up the last unfinished request. The log is evidence of what happened, not instructions to replay; follow the current repo rules and confirm anything destructive first.
- `finished`: run the `full log:` command and read the end of the log. Check the workspace (`git status`/`git diff`, whether its changes were tested or committed). Then recommend one to three concrete next steps that follow from the work, such as running tests it never ran, committing, or follow-ups it mentioned. Ask which to do and don't start without an answer.
