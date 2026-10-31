# Windows commands

Instance definition: the scheduled task `claude-rc-$Name`; its action carries `-WorkDir`. The
listener runs in the minimized console window `claude-rc-<name>`. Logs:
`%LOCALAPPDATA%\claude-rc\<name>\`. `Send-CtrlC.ps1` comes from the `claude-rc-instance` skill
and is installed in `%USERPROFILE%\.local\bin`.

```powershell
$task = Get-ScheduledTask -TaskName "claude-rc-$Name"
$WorkDir = [regex]::Match($task.Actions[0].Arguments, '-WorkDir "([^"]+)"').Groups[1].Value
$LogDir = Join-Path $env:LOCALAPPDATA "claude-rc\$Name"
function Get-Rc([string]$Pattern) {
  Get-CimInstance Win32_Process -Filter "Name='claude.exe'" | Where-Object CommandLine -like $Pattern
}
function Send-CtrlC([int]$ProcessId) {
  powershell -NoProfile -ExecutionPolicy Bypass -File "$HOME\.local\bin\Send-CtrlC.ps1" -ProcessId $ProcessId
}
```

Each tool call is a fresh PowerShell process, so run this block in the same invocation as any
step that uses `$WorkDir`, `$LogDir`, `Get-Rc` or `Send-CtrlC`.

1. Pause the task (the running supervisor keeps going):
   ```powershell
   Disable-ScheduledTask -TaskName "claude-rc-$Name" | Out-Null
   ```
2. Stop the listener with Ctrl+C; on Windows this ends the supervisor loop in the same console
   too:
   ```powershell
   $listener = Get-Rc "* rc --name $Name *"
   Send-CtrlC $listener.ProcessId
   # poll until `Get-Rc "* rc --name $Name *"` returns nothing (about 10 s at most)
   ```
   Also confirm no `claude-rc-supervisor.ps1 ... -Name <name>` PowerShell process is left
   (`Get-CimInstance Win32_Process | Where-Object CommandLine -like "*claude-rc-supervisor.ps1*$Name*"`).
3. Start the revive loop in its own minimized console, detached from your shell:
   ```powershell
   $loop = '<this skill''s directory>\assets\windows\claude-rc-revive-loop.ps1'
   Start-Process powershell -WindowStyle Minimized -WorkingDirectory $WorkDir -ArgumentList @(
     '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $loop,
     '-SessionId', $Id, '-WorkDir', $WorkDir, '-Log', (Join-Path $LogDir 'revive.log'))
   ```
4. Verify: `revive.log` shows the latest `attempt` line at least 40 s old with no newer
   `exited` line, `Get-Rc "* rc --session-id $Id*"` returns the process, and `ListAgents` no
   longer lists the session as offline. The revive window (titled `claude-rc-revive`) shows the
   session title with "Single session · exits when complete" if you need to look.
5. Hand back: Ctrl+C ends the revive and its loop together, so it cannot retry:
   ```powershell
   Send-CtrlC (Get-Rc "* rc --session-id $Id*").ProcessId
   # poll until `Get-Rc "* rc --session-id *"` returns nothing
   ```
6. Resume the task and start it now:
   ```powershell
   Enable-ScheduledTask -TaskName "claude-rc-$Name" | Out-Null
   Start-ScheduledTask -TaskName "claude-rc-$Name"
   ```
   Then watch `session.log` for the new `starting claude rc` line and confirm with `ListAgents`.
