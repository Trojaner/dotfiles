# Windows

Native Windows with the native Claude Code install (`claude.exe`, usually in
`%USERPROFILE%\.local\bin`) and Windows PowerShell 5.1 or PowerShell 7. There is no tmux, so the
TUI lives in a minimized console window and Task Scheduler takes the role of the LaunchAgent. For
a WSL2 distribution use [linux.md](linux.md) inside the distribution instead.

Files per instance: the scheduled task `claude-rc-<name>`. Logs:
`%LOCALAPPDATA%\claude-rc\<name>\session.log` (supervisor events only; the TUI is in the window).

Shared, installed once per machine:

| File | From |
| --- | --- |
| `%USERPROFILE%\.local\bin\claude-rc-supervisor.ps1` | `assets\windows\claude-rc-supervisor.ps1` |
| `%USERPROFILE%\.local\bin\Send-CtrlC.ps1` | `assets\windows\Send-CtrlC.ps1` |

`assets\windows\Register-ClaudeRc.ps1` registers the task and is run straight from the skill.

## How it maps to the other platforms

- **Starts and re-checks:** the task triggers at logon and repeats every two minutes. Its
  `MultipleInstances IgnoreNew` setting makes each repetition a no-op while the supervisor runs,
  so it only starts the supervisor again after it died; that is the `StartInterval 120` of the
  macOS launcher. `ExecutionTimeLimit` is zero, because the default 72-hour limit would kill the
  supervisor.
- **Interactive logon type:** the task runs in the signed-in desktop session, which gives the
  console window and the user's Claude credentials. Instances therefore run while the user is
  signed in (a locked screen is fine), the way LaunchAgents do on macOS.
- **Watching the TUI:** restore the `claude-rc-<name>` window from the taskbar. Do not close it
  and do not press Ctrl+C in it unless the instance should stop.
- **Clean stop:** `claude rc` only keeps its sessions resumable when it stops on Ctrl+C. Windows
  has no signal for that, so `Send-CtrlC.ps1` attaches to the console and raises `CTRL_C_EVENT`
  there. It ends `claude rc` and the supervisor loop together (on macOS and Linux the loop
  survives), so disable the task first when it must stay down.

## Checks before creating

- `Get-ScheduledTask -TaskName claude-rc-$Name` finds nothing.
- `Get-Command claude` resolves in a new PowerShell window (the task runs with the user's normal
  environment, so `claude` must be on the user `PATH`).
- No `claude.exe` process already serves the directory:
  `Get-CimInstance Win32_Process -Filter "Name='claude.exe'" | Where-Object CommandLine -like '* rc *'`.

## First instance on a machine

```powershell
$S = '<this skill''s directory>\assets\windows'
New-Item -ItemType Directory -Force "$HOME\.local\bin" | Out-Null
Copy-Item "$S\claude-rc-supervisor.ps1", "$S\Send-CtrlC.ps1" "$HOME\.local\bin\"
```

## Create the instance

After the user confirms (it starts a persistent process at every logon):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$S\Register-ClaudeRc.ps1" -Name $Name -WorkDir $WorkDir
Start-ScheduledTask -TaskName "claude-rc-$Name"
```

## Verify

`Get-ScheduledTask -TaskName claude-rc-$Name | Get-ScheduledTaskInfo` shows a recent
`LastRunTime`, a minimized `claude-rc-<name>` window exists, and
`Get-Content "$env:LOCALAPPDATA\claude-rc\$Name\session.log" -Tail 5` shows
`starting claude rc --name <name>` with no `exited` line right after it.

## Stop, start, pause

Find the processes by command line:

```powershell
$claude = Get-CimInstance Win32_Process -Filter "Name='claude.exe'" |
  Where-Object CommandLine -like "* rc --name $Name *"
```

- Pause re-checks: `Disable-ScheduledTask -TaskName claude-rc-$Name` (the running supervisor
  keeps going).
- Resume: `Enable-ScheduledTask -TaskName claude-rc-$Name; Start-ScheduledTask -TaskName claude-rc-$Name`
- Stop cleanly: disable the task, then
  `powershell -NoProfile -File "$HOME\.local\bin\Send-CtrlC.ps1" -ProcessId $claude.ProcessId`
  and wait until the process is gone. Run the helper as its own `powershell` process as shown; it
  detaches from the console it starts in.
- `Stop-Process` is a hard kill, like `kill -9`: use it only when Ctrl+C did not work, and say so.

## Removing an instance

```powershell
Disable-ScheduledTask -TaskName claude-rc-$Name
# stop it cleanly as above, then:
Unregister-ScheduledTask -TaskName claude-rc-$Name -Confirm:$false
```

The shared scripts in `%USERPROFILE%\.local\bin` stay for the machine's other instances.
