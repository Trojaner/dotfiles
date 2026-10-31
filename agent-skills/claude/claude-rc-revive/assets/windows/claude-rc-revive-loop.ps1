# Retry loop for `claude rc --session-id` on Windows, the counterpart of the
# inline tmux loop on macOS and Linux. Right after the owning instance stops,
# the "already served" error persists for about 2-4 minutes, so it retries every
# 20 s up to 15 times. A Ctrl+C sent to this console ends claude rc and this
# loop together, which is how the session is handed back to the instance.
#
# Usage: claude-rc-revive-loop.ps1 -SessionId <id> -WorkDir <dir> -Log <file>
param(
  [Parameter(Mandatory)][string]$SessionId,
  [Parameter(Mandatory)][string]$WorkDir,
  [Parameter(Mandatory)][string]$Log
)

$host.UI.RawUI.WindowTitle = 'claude-rc-revive'
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Log) | Out-Null
Set-Content -Path $Log -Value $null
Set-Location -LiteralPath $WorkDir

foreach ($attempt in 1..15) {
  Add-Content -Path $Log -Value ("attempt {0} {1}" -f $attempt, (Get-Date -Format 'HH:mm:ss'))
  & claude rc --session-id $SessionId --permission-mode auto
  $code = $LASTEXITCODE
  Add-Content -Path $Log -Value ("exited (code {0}) {1}" -f $code, (Get-Date -Format 'HH:mm:ss'))
  if ($code -eq 0) { break }
  Start-Sleep -Seconds 20
}
Add-Content -Path $Log -Value 'loop done'
