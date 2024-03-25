Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Confirm

winget install JanDeDobbeleer.OhMyPosh -s winget

Install-Module -Name posh-git -Scope CurrentUser -Confirm
Install-Module -Name PSReadLine -Scope CurrentUser -Confirm
Install-Module -Name Get-ChildItemColor -Scope CurrentUser -Confirm
Install-Module -Name Terminal-Icons -Scope CurrentUser -Confirm
Install-Module -Name nvm -Scope CurrentUser -Confirm

if (Test-Path $PROFILE) { Remove-Item $PROFILE }
New-Item -Path $PROFILE -ItemType SymbolicLink -Value (Resolve-Path "..\Microsoft.PowerShell_profile.ps1").Path | Out-Null

. $PROFILE

oh-my-posh font install Hack

iex "& {$(irm get.scoop.sh)} -RunAsAdmin"

winget install magic-wormhole
