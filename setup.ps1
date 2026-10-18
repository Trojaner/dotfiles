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

# Windows Defender process exclusions for the dev toolchain to speed up git status and builds.
# Requires an elevated session; skipped with a warning otherwise.
if (([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    'git.exe', 'node.exe', 'dotnet.exe', 'MSBuild.exe', 'oh-my-posh.exe', 'pwsh.exe' |
        ForEach-Object { Add-MpPreference -ExclusionProcess $_ }
}
else {
    Write-Warning 'Skipping Windows Defender exclusions (run setup.ps1 as Administrator to apply them).'
}

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

Install-PSResource -Repository PSGallery -Name Microsoft.WinGet.Client -Scope CurrentUser
Install-PSResource -Repository PSGallery -Name Microsoft.WinGet.CommandNotFound -Scope CurrentUser
Install-PSResource -Repository PSGallery -Name PSReadLine -Scope CurrentUser
Install-PSResource -Repository PSGallery -Name Terminal-Icons -Scope CurrentUser

Invoke-Expression "& {$(Invoke-RestMethod https://get.scoop.sh)} -RunAsAdmin"
Invoke-Expression "& { $(Invoke-RestMethod 'https://aka.ms/install-aishell.ps1') }"

oh-my-posh font install Hack
oh-my-posh enable notice
oh-my-posh disable upgrade

New-Item -Path "$HOME\Documents\PowerShell\Microsoft.PowerShell_profile.ps1" -ItemType SymbolicLink -Value (Resolve-Path ".\powershell\Microsoft.PowerShell_profile.ps1").Path | Out-Null
New-Item -Path "$HOME\Documents\PowerShell\posh-theme.json" -ItemType SymbolicLink -Value (Resolve-Path ".\powershell\posh-theme.json").Path | Out-Null

New-Item -Path "$HOME\.gitconfig.shared" -ItemType SymbolicLink -Value (Resolve-Path ".\git\.gitconfig.shared").Path -Force | Out-Null
New-Item -Path "$HOME\.gitconfig" -ItemType SymbolicLink -Value (Resolve-Path ".\git\.gitconfig.windows").Path -Force | Out-Null

New-Item -Path "$HOME\.claude" -ItemType Directory -Force | Out-Null
$base = Get-Content ".\claude\settings.base.json" -Raw | ConvertFrom-Json -AsHashtable
$platform = Get-Content ".\claude\settings.windows.json" -Raw | ConvertFrom-Json -AsHashtable
# Deep merge (like jq's `*` in setup.sh) so nested objects such as env keep keys from both files
function Merge-Settings($target, $source) {
    foreach ($key in $source.Keys) {
        if ($target[$key] -is [hashtable] -and $source[$key] -is [hashtable]) {
            Merge-Settings $target[$key] $source[$key]
        }
        else {
            $target[$key] = $source[$key]
        }
    }
}
Merge-Settings $base $platform
$base | ConvertTo-Json -Depth 10 | Set-Content "$HOME\.claude\settings.json"
New-Item -Path "$HOME\.claude\statusline-command.sh" -ItemType SymbolicLink -Value (Resolve-Path ".\claude\statusline-command.sh").Path | Out-Null
New-Item -Path "$HOME\.claude\statusline-command.ps1" -ItemType SymbolicLink -Value (Resolve-Path ".\claude\statusline-command.ps1").Path | Out-Null
New-Item -Path "$HOME\.claude\CLAUDE.md" -ItemType SymbolicLink -Value (Resolve-Path ".\claude\CLAUDE.md").Path | Out-Null

# Codex configuration: preserve existing files before linking shared defaults.
$codexDir = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME '.codex' }
New-Item -Path $codexDir -ItemType Directory -Force | Out-Null
$codexBackup = $null
foreach ($name in 'config.toml', 'AGENTS.md') {
    $sourceFile = (Resolve-Path (Join-Path $PSScriptRoot "codex/$name")).Path
    $targetFile = Join-Path $codexDir $name
    $existing = Get-Item -LiteralPath $targetFile -Force -ErrorAction SilentlyContinue
    if ($existing -and $existing.LinkType -eq 'SymbolicLink' -and $existing.Target -eq $sourceFile) {
        continue
    }
    if ($existing) {
        if (-not $codexBackup) {
            $codexBackup = Join-Path $codexDir ("dotfiles-backup." + [guid]::NewGuid().ToString('N'))
            New-Item -Path $codexBackup -ItemType Directory | Out-Null
        }
        Move-Item -LiteralPath $targetFile -Destination (Join-Path $codexBackup $name)
    }
    New-Item -Path $targetFile -ItemType SymbolicLink -Value $sourceFile | Out-Null
}

# Per-user hourly memory maintenance (no administrator task credentials).
& (Join-Path $PSScriptRoot 'codex/setup-memory.ps1')

$insidersBin = "$env:LOCALAPPDATA\Programs\Microsoft VS Code Insiders\bin"
New-Item -Path "$insidersBin\code.cmd" -ItemType SymbolicLink -Value "$insidersBin\code-insiders.cmd" -Force | Out-Null

. $PROFILE
. $PROFILE.CurrentUserAllHosts
