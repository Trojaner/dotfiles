echo "Microsoft.PowerShell_profile.ps1"

if ([Environment]::GetCommandLineArgs().Contains("-NonInteractive")) {
  return
}

oh-my-posh init pwsh --config "$HOME\Documents\PowerShell\posh-theme.json" | Invoke-Expression

Set-PSReadLineOption -PredictionViewStyle ListView
Set-PSReadLineOption -HistorySearchCursorMovesToEnd:$true
Set-PSReadlineKeyHandler -Key Tab -Function MenuComplete

fastfetch