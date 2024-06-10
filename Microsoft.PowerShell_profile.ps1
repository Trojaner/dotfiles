# $POSH_CONFIG=(Join-Path $HOME "oh-my-posh.json")

oh-my-posh init pwsh --config "$HOME\Documents\PowerShell\posh-theme.json" | Invoke-Expression


Import-Module PSReadLine
Import-Module Get-ChildItemColor
Import-Module Terminal-Icons

$ChocolateyProfile = "$env:ChocolateyInstall\helpers\chocolateyProfile.psm1"
if (Test-Path($ChocolateyProfile)) {
  Import-Module "$ChocolateyProfile"
}

if (Test-Path alias:Curl) { 
  Remove-Item alias:Curl 
}

if (Test-Path alias:WGet) { 
  Remove-Item alias:WGet 
}

$PSDefaultParameterValues["Out-File:Encoding"] = "utf8"
Set-PSReadlineKeyHandler -Key Tab -Function Complete
