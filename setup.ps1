if (Test-Path  $PROFILE.CurrentUserAllHosts) {
    Write-Output "ERROR: $PROFILE.CurrentUserAllHosts already exists. Please remove it before running this script."
    exit 1
}

[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

[System.Environment]::SetEnvironmentVariable('POWERSHELL_TELEMETRY_OPTOUT', 'true', 'User')

[System.Environment]::SetEnvironmentVariable('EDITOR', 'code-insiders --wait', 'User')
[System.Environment]::SetEnvironmentVariable('KUBE_EDITOR', 'code-insiders --wait', 'User')
[System.Environment]::SetEnvironmentVariable('FZF_DEFAULT_OPTS', '--color=fg:-1,fg+:#ffffff,bg:-1,bg+:#3c4048 --color=hl:#5ea1ff,hl+:#5ef1ff,info:#ffbd5e,marker:#5eff6c --color=prompt:#ff5ef1,spinner:#bd5eff,pointer:#ff5ea0,header:#5eff6c --color=gutter:-1,border:#3c4048,scrollbar:#7b8496,label:#7b8496 --color=query:#ffffff --border="rounded" --border-label="" --preview-window="border-rounded" --height 40% --preview="bat -n --color=always {}"', 'User')

Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

winget install --exact --source winget --id=JanDeDobbeleer.OhMyPosh --scope user --accept-source-agreements --silent
winget install --exact --source winget --id=magic-wormhole.magic-wormhole --scope user --accept-source-agreements --silent
winget install --exact --source winget --id=junegunn.fzf --scope user --accept-source-agreements --silent
winget install --exact --source winget --id=Fastfetch-cli.Fastfetch --scope user --accept-source-agreements --silent
winget install --exact --source winget --id=sharkdp.bat --scope user --accept-source-agreements --silent
# winget install --exact --source winget --id=direnv.direnv --scope user --accept-source-agreements --silent

Unregister-PackageSource -Source PSGallery
Register-PackageSource -Name PSGallery -ProviderName PowerShellGet -Trusted

Enable-ExperimentalFeature PSFeedbackProvider
Enable-ExperimentalFeature PSNativeWindowsTildeExpansion
Enable-ExperimentalFeature PSSubsystemPluginModel

Install-PSResource -Repository PSGallery -Name CompletionPredictor -Scope CurrentUser
Install-PSResource -Repository PSGallery -Name Get-ChildItemColor -Scope CurrentUser
Install-PSResource -Repository PSGallery -Name Microsoft.WinGet.Client -Scope CurrentUser
Install-PSResource -Repository PSGallery -Name Microsoft.WinGet.CommandNotFound -Scope CurrentUser
Install-PSResource -Repository PSGallery -Name posh-git -Scope CurrentUser
Install-PSResource -Repository PSGallery -Name PSReadLine -Scope CurrentUser
Install-PSResource -Repository PSGallery -Name Terminal-Icons -Scope CurrentUser

Invoke-Expression "& {$(Invoke-RestMethod https://get.scoop.sh)} -RunAsAdmin"
Invoke-Expression "& { $(Invoke-RestMethod 'https://aka.ms/install-aishell.ps1') }"

oh-my-posh font install Hack
oh-my-posh enable notice
oh-my-posh disable upgrade

New-Item -Path "$HOME\Documents\PowerShell\Microsoft.PowerShell_profile.ps1" -ItemType SymbolicLink -Value (Resolve-Path ".\powershell\Microsoft.PowerShell_profile.ps1").Path | Out-Null
New-Item -Path "$HOME\Documents\PowerShell\posh-theme.json" -ItemType SymbolicLink -Value (Resolve-Path ".\powershell\posh-theme.json").Path | Out-Null

. $PROFILE
. $PROFILE.CurrentUserAllHosts
