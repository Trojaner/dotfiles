# Supervisor loop for a `claude rc` (Remote Control) instance on Windows.
#
# Usage: claude-rc-supervisor.ps1 -Name <name> -WorkDir <dir>
#
# The Windows counterpart of claude-rc-supervisor.sh. The scheduled task
# claude-rc-<name> starts it at logon in a minimized console window, which is
# where the claude rc TUI lives (restore the window to see it, as `tmux attach`
# does on macOS and Linux). It runs `claude rc` forever and restarts it with
# exponential backoff when it exits; only supervisor events go to the log.
#
# Session continuity works as on the other platforms: a plain `claude rc` in the
# same directory brings back the sessions the previous server was serving for
# about four hours, so never add --no-create-session-in-dir (it archives them).
#
# A Ctrl+C sent to this console ends claude rc and this loop together; the
# task's two-minute repetition starts the loop again unless the task is disabled.
param(
  [Parameter(Mandatory)][string]$Name,
  [Parameter(Mandatory)][string]$WorkDir
)

$ErrorActionPreference = 'Continue'
$logDir = Join-Path $env:LOCALAPPDATA "claude-rc\$Name"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$log = Join-Path $logDir 'session.log'
$host.UI.RawUI.WindowTitle = "claude-rc-$Name"

function Write-Log([string]$Message) {
  Add-Content -Path $log -Value ("{0} {1}" -f (Get-Date -Format 'yyyy-MM-ddTHH:mm:sszzz'), $Message)
}

if (-not (Test-Path -LiteralPath $WorkDir -PathType Container)) {
  Write-Log "supervisor: FATAL - workdir $WorkDir does not exist"
  exit 1
}
Set-Location -LiteralPath $WorkDir

# A run lasting at least this long counts as healthy and resets the backoff.
$healthyRunSecs = 300
$delay = 5
while ($true) {
  Write-Log "starting claude rc --name $Name"
  $started = Get-Date
  & claude rc --name $Name --remote-control-session-name-prefix $Name --permission-mode auto --spawn same-dir
  $code = $LASTEXITCODE
  if (((Get-Date) - $started).TotalSeconds -ge $healthyRunSecs) { $delay = 5 }
  Write-Log "claude rc exited (code $code); restarting in ${delay}s"
  Start-Sleep -Seconds $delay
  if ($delay -lt 60) { $delay = [Math]::Min($delay * 2, 60) }
}
