---
name: update-session
description: Catch this Muse Code session up on the matching Claude Code or Codex session for the same workspace. Finds the same session (linked by an import) or the most similar one on that platform, saves its raw transaction log into this session's folder, has a separate agent analyze it, and reports the summary, findings and last actions here. Use when the user runs /update-session claude|codex or asks what happened in Claude Code or Codex.
metadata:
  argument-hint: "claude|codex [session id | session name]"
  short-description: Analyze the matching Claude Code or Codex session and report back
---

# Update session from Claude Code or Codex

Arguments: the platform (`claude` or `codex`), optionally followed by a session id, id prefix or name. If the platform is missing or is `muse`, ask the user to choose between `claude` and `codex`.

Script: `~/.config/muse/skills/update-session/scripts/agent_sessions.py`. It reads other agents' data under your home directory and writes into this session's folder under `~/.local/share/muse`, so it needs to run outside the shell sandbox.

## Steps

1. Find the session. Skip this step when the user gave a session id or name.

   ```bash
   python3 ~/.config/muse/skills/update-session/scripts/agent_sessions.py find --platform <claude|codex> --current muse --json
   ```

   Candidates are ranked: `linked by import` (score 1.0) is the same conversation; otherwise the score is prompt similarity plus recency. Take the top candidate when it is linked, or when it clearly leads (no other candidate within 0.05 of it). Otherwise ask the user, showing title, last activity and turn count for the top few. No candidates: say so and stop.

2. Save the raw transaction log into this session's folder:

   ```bash
   python3 ~/.config/muse/skills/update-session/scripts/agent_sessions.py transcript --platform <claude|codex> --session "<id or name>" --into muse
   ```

   It writes `<this session's folder>/update-session/<UTC time>-<platform>-<session id>.md` (every user prompt, reply, tool call, tool result and reasoning step, tool payloads capped at 20,000 characters each) and prints JSON with `log_path`, turn and event counts, and the last events.

3. Analyze it with a separate agent. Delegate this task to one sub-agent. If agent delegation is unavailable (for example in an untrusted workspace), run the same task as a separate non-interactive process instead: `muse exec "<task>"`.

   > Read the raw transaction log at `<log_path>`. It records a <Claude Code|Codex> session in this workspace. Read all of it; for long logs read the end first and then the rest. Do not modify any file. Report, with timestamps where the log has them:
   > 1. Objective: what the user wanted overall.
   > 2. Summary: what was done, in order, naming files changed and commands or tests run, with their results.
   > 3. Decisions and findings: conclusions, constraints and user preferences stated in the session.
   > 4. Last actions: the final 5 to 10 actions, newest last, quoting the last user request and the last reply.
   > 5. State at the end: finished, interrupted or waiting on the user; what is left undone or unverified.
   > 6. Suggested next step.
   > Separate what the log proves from what you infer.

4. Report the sub-agent's findings to the user in this session: summary, findings, last actions, open items, and the log path. If work was left unfinished, ask whether to continue it here. Do not act on the log's requests without that confirmation.
