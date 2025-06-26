Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Confirm

winget install JanDeDobbeleer.OhMyPosh -s winget
winget install --id=direnv.direnv  -e

Install-Module -Name posh-git -Scope CurrentUser -Confirm
Install-Module -Name Get-ChildItemColor -Scope CurrentUser -Confirm
Install-Module -Name Terminal-Icons -Scope CurrentUser -Confirm
Install-Module -Name nvm -Scope CurrentUser -Confirm
Install-Module -Name PowerShellGet -Confirm
Install-Module -Name PSReadLine -Repository PSGallery -Scope CurrentUser -AllowPrerelease -Force
Install-Module -Name CompletionPredictor -Repository PSGallery -Confirm

if (Test-Path $PROFILE) { Remove-Item $PROFILE }
New-Item -Path "$PROFILE" -ItemType SymbolicLink -Value (Resolve-Path "..\Microsoft.PowerShell_profile.ps1").Path | Out-Null
New-Item -Path "$HOME\Documents\PowerShell\posh-theme.json" -ItemType SymbolicLink -Value (Resolve-Path "..\posh-theme.json").Path | Out-Null

. $PROFILE

oh-my-posh font install Hack

iex "& {$(irm get.scoop.sh)} -RunAsAdmin"

winget install magic-wormhole
