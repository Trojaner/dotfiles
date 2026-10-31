# Registers the scheduled task claude-rc-<name>: the Windows counterpart of the
# macOS LaunchAgent (RunAtLoad + StartInterval 120). It starts the supervisor at
# logon in a minimized console and re-checks every two minutes; MultipleInstances
# IgnoreNew makes each re-check a no-op while the supervisor is running, so a
# repetition only starts it again after it died.
#
# Usage: powershell -NoProfile -File Register-ClaudeRc.ps1 -Name <name> -WorkDir <dir>
param(
  [Parameter(Mandatory)][string]$Name,
  [Parameter(Mandatory)][string]$WorkDir
)

$taskName = "claude-rc-$Name"
if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
  Write-Error "Scheduled task $taskName already exists"
  exit 1
}

$shell = (Get-Command pwsh.exe -ErrorAction SilentlyContinue).Source
if (-not $shell) { $shell = (Get-Command powershell.exe).Source }
$supervisor = Join-Path $HOME '.local\bin\claude-rc-supervisor.ps1'
$arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Minimized -File `"$supervisor`" -Name `"$Name`" -WorkDir `"$WorkDir`""

$action = New-ScheduledTaskAction -Execute $shell -Argument $arguments -WorkingDirectory $WorkDir
$trigger = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
$trigger.Repetition = (New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 2)).Repetition
# Interactive: runs in the signed-in desktop session, so the console window and
# the user's Claude credentials are available. ExecutionTimeLimit 0 removes the
# default 72-hour limit, which would otherwise kill the supervisor.
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::Zero) `
  -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -DontStopOnIdleEnd

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings `
  -Description "claude rc (Remote Control) instance $Name in $WorkDir" | Out-Null
Write-Output "Registered $taskName"
