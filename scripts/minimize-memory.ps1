[CmdletBinding(DefaultParameterSetName = 'Interactive')]
param(
    [Parameter(ParameterSetName = 'NonInteractive')][switch]$NonInteractive,
    [Parameter(ParameterSetName = 'Revert')][switch]$Revert,
    [Parameter(ParameterSetName = 'Backup')][switch]$BackupOnly,
    [Parameter(ParameterSetName = 'Status')][switch]$Status,
    [Parameter(ParameterSetName = 'Export')][string]$ExportConfig,
    [Parameter(ParameterSetName = 'Import')][string]$ImportConfig
)

$currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]$currentIdentity
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "`n  Requesting administrator privileges..." -ForegroundColor Yellow
    $passArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    if ($NonInteractive)  { $passArgs += ' -NonInteractive' }
    if ($Revert)          { $passArgs += ' -Revert' }
    if ($BackupOnly)      { $passArgs += ' -BackupOnly' }
    if ($Status)          { $passArgs += ' -Status' }
    if ($ExportConfig)    { $passArgs += " -ExportConfig `"$ExportConfig`"" }
    if ($ImportConfig)    { $passArgs += " -ImportConfig `"$ImportConfig`"" }
    foreach ($cmd in @('sudo','gsudo')) {
        if (Get-Command $cmd -ErrorAction SilentlyContinue) {
            $sudoArgs = @('powershell.exe') + ($passArgs -split ' ')
            & $cmd @sudoArgs
            exit $LASTEXITCODE
        }
    }
    try {
        Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $passArgs
        exit 0
    } catch {
        Write-Host "  Failed to elevate: $_" -ForegroundColor Red; exit 1
    }
}

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:BackupDir    = Join-Path $env:ProgramData 'MemoryOptimizer'
$script:BackupFile   = Join-Path $script:BackupDir 'backup.json'
$script:E            = [char]27
$script:RebootNeeded = $false
$script:StatusCache    = @{}
$script:SchedTaskCache = $null
$script:CacheDirty     = $true

function C ([string]$Text, [int]$Color=252, [switch]$Bold) {
    $b = if ($Bold) { "$script:E[1m" } else { '' }
    return "$b$script:E[38;5;${Color}m$Text$script:E[0m"
}
function Write-Ok   ([string]$T) { Write-Host "  $(C ([char]0x2713).ToString() 40) $T" }
function Write-Warn ([string]$T) { Write-Host "  $(C ([char]0x26A0).ToString() 214) $T" }
function Write-Err  ([string]$T) { Write-Host "  $(C ([char]0x2717).ToString() 196) $T" }
function Write-Inf  ([string]$T) { Write-Host "  $(C '>' 75) $T" }

function Write-Header ([string]$Text) {
    Write-Host ''
    Write-Host "  $(C $Text 39 -Bold)"
    Write-Host "  $(C ($([char]0x2500).ToString() * ($Text.Length + 2)) 239)"
}

function Get-RegValue ([string]$Path, [string]$Name) {
    try { $item = Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop; return $item.$Name }
    catch { return $null }
}
function Set-RegValue ([string]$Path, [string]$Name, $Value, [string]$Type='DWord') {
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type
}
function Remove-RegValue ([string]$Path, [string]$Name) {
    try { Remove-ItemProperty -Path $Path -Name $Name -ErrorAction Stop } catch {}
}

function Save-BackupData ([hashtable]$Data) {
    if (-not (Test-Path $script:BackupDir)) { New-Item -ItemType Directory -Path $script:BackupDir -Force | Out-Null }
    $wrapper = @{ Timestamp = (Get-Date -Format 'o'); Version = 2; Features = $Data }
    $wrapper | ConvertTo-Json -Depth 10 | Set-Content -Path $script:BackupFile -Encoding UTF8
    Write-Ok "Backup saved to $script:BackupFile"
}

function Get-BackupData ([string]$Path = $script:BackupFile) {
    if (Test-Path $Path) {
        try {
            $raw = Get-Content $Path -Raw | ConvertFrom-Json
            if ($raw.Features) { return $raw } else { return @{ Features = $raw } }
        } catch {
            Write-Warn "Failed to parse backup file: $_"
            return $null
        }
    }
    return $null
}

function Test-BackupFile ([string]$Path) {
    if (-not (Test-Path $Path)) { return @{ Valid = $false; Reason = 'File does not exist' } }
    try {
        $raw = Get-Content $Path -Raw | ConvertFrom-Json
        if (-not $raw) { return @{ Valid = $false; Reason = 'Empty or invalid JSON' } }
        if (-not $raw.Features -and -not $raw.PSObject.Properties['Features']) {
            return @{ Valid = $false; Reason = 'Missing Features section' }
        }
        $featureCount = 0
        $raw.Features.PSObject.Properties | ForEach-Object { $featureCount++ }
        $ts = if ($raw.Timestamp) { $raw.Timestamp } else { 'unknown' }
        return @{ Valid = $true; Reason = "Valid backup: $featureCount feature(s), timestamp: $ts" }
    } catch {
        return @{ Valid = $false; Reason = "Parse error: $_" }
    }
}

function Export-SelectionConfig ([string]$Path) {
    $config = @{ Timestamp = (Get-Date -Format 'o'); Version = 1; Selections = $script:Selections }
    $config | ConvertTo-Json -Depth 5 | Set-Content -Path $Path -Encoding UTF8
    Write-Ok "Configuration exported to $Path"
}

function Import-SelectionConfig ([string]$Path) {
    if (-not (Test-Path $Path)) { Write-Err "File not found: $Path"; return $false }
    try {
        $config = Get-Content $Path -Raw | ConvertFrom-Json
        if (-not $config.Selections) { Write-Err 'Invalid config: no Selections found'; return $false }
        $imported = 0
        $config.Selections.PSObject.Properties | ForEach-Object {
            if ($script:Features.Contains($_.Name) -and $_.Value -in @('enable','disable','skip')) {
                $script:Selections[$_.Name] = $_.Value
                $imported++
            }
        }
        Write-Ok "Imported $imported feature selection(s) from $Path"
        return $true
    } catch {
        Write-Err "Failed to parse config: $_"
        return $false
    }
}

function Initialize-StatusCache {
    if (-not $script:CacheDirty) { return }
    $script:StatusCache = @{}
    try { $script:SchedTaskCache = @(Get-ScheduledTask -ErrorAction SilentlyContinue) }
    catch { $script:SchedTaskCache = @() }
    foreach ($fKey in $script:Features.Keys) {
        $script:StatusCache[$script:Features[$fKey].Name] = Compute-FeatureStatus $script:Features[$fKey]
    }
    $script:CacheDirty = $false
}

function Invalidate-StatusCache { $script:CacheDirty = $true }

function Get-FeatureStatus ([hashtable]$Feat) {
    $cacheKey = $Feat.Name
    if ($script:StatusCache.ContainsKey($cacheKey)) { return $script:StatusCache[$cacheKey] }
    $result = Compute-FeatureStatus $Feat
    $script:StatusCache[$cacheKey] = $result
    return $result
}

function Compute-FeatureStatus ([hashtable]$Feat) {
    if ($Feat.Type -eq 'Custom') { return & $Feat.GetStatus }

    $allOpt = $true; $allDef = $true; $found = $false
    $partialDetails = [System.Collections.ArrayList]::new()

    switch ($Feat.Type) {
        'Registry' {
            foreach ($e in $Feat.Entries) {
                $val = Get-RegValue $e.P $e.N
                $found = $true
                $isOpt = ($val -eq $e.O)
                $isDefault = ($null -eq $e.D -and $null -eq $val) -or ($val -eq $e.D)
                if ($isOpt) {
                    [void]$partialDetails.Add("[+] $($e.N)=$val")
                } else {
                    $allOpt = $false
                    $valText = if ($null -eq $val) { 'not set' } else { $val }
                    [void]$partialDetails.Add("[-] $($e.N)=$valText (expected=$($e.O))")
                }
                if (-not $isDefault) { $allDef = $false }
            }
        }
        'Service' {
            foreach ($s in $Feat.Svcs) {
                $svc = Get-Service -Name $s.N -ErrorAction SilentlyContinue
                if ($svc) {
                    $found = $true
                    if ($svc.StartType -eq 'Disabled') {
                        [void]$partialDetails.Add("[+] $($s.N)=Disabled")
                    } else {
                        $allOpt = $false
                        [void]$partialDetails.Add("[-] $($s.N)=$($svc.StartType) (expected=Disabled)")
                    }
                    $def = if ($null -ne $s.D) { $s.D } else { 'Manual' }
                    if ($svc.StartType.ToString() -ne $def) { $allDef = $false }
                }
            }
        }
        'ScheduledTask' {
            foreach ($t in $Feat.Tasks) {
                $tName = ($t -split '\\')[-1]; $tPath = $t -replace '[^\\]+$', ''
                $task = $script:SchedTaskCache | Where-Object { $_.TaskName -eq $tName -and $_.TaskPath -eq $tPath }
                if ($task) {
                    $found = $true
                    if ($task.State -eq 'Disabled') {
                        [void]$partialDetails.Add("[+] $tName=Disabled")
                    } else {
                        $allOpt = $false
                        [void]$partialDetails.Add("[-] $tName=$($task.State) (expected=Disabled)")
                    }
                    if ($task.State -eq 'Disabled') { $allDef = $false }
                }
            }
        }
    }

    if (-not $found) { return @{ Optimized = $null; Text = 'N/A'; Details = @() } }
    if ($allOpt) { return @{ Optimized = $true;  Text = 'APPLIED'; Details = @() } }
    if ($allDef) { return @{ Optimized = $false; Text = 'DEFAULT'; Details = @() } }
    return @{ Optimized = $false; Text = 'PARTIAL'; Details = @($partialDetails) }
}

function Invoke-FeatureBackup ([hashtable]$Feat) {
    if ($Feat.Type -eq 'Custom') { return & $Feat.Backup }
    $bk = @{}
    switch ($Feat.Type) {
        'Registry' {
            foreach ($e in $Feat.Entries) { $bk["$($e.P)|$($e.N)"] = Get-RegValue $e.P $e.N }
        }
        'Service' {
            foreach ($s in $Feat.Svcs) {
                $svc = Get-Service -Name $s.N -ErrorAction SilentlyContinue
                if ($svc) { $bk[$s.N] = $svc.StartType.ToString() }
            }
        }
        'ScheduledTask' {
            foreach ($t in $Feat.Tasks) {
                try {
                    $tName = ($t -split '\\')[-1]; $tPath = $t -replace '[^\\]+$', ''
                    $task = Get-ScheduledTask -TaskName $tName -TaskPath $tPath -ErrorAction Stop
                    $bk[$t] = $task.State.ToString()
                } catch {}
            }
        }
    }
    return $bk
}

function Invoke-FeatureApply ([hashtable]$Feat) {
    if ($Feat.Type -eq 'Custom') { return & $Feat.Apply }
    $bk = @{}
    switch ($Feat.Type) {
        'Registry' {
            foreach ($e in $Feat.Entries) {
                $bk["$($e.P)|$($e.N)"] = Get-RegValue $e.P $e.N
                $type = if ($e.ContainsKey('T')) { $e['T'] } else { 'DWord' }
                Set-RegValue $e.P $e.N $e.O $type
            }
            Write-Ok "$($Feat.ActionLabel): $($Feat.Name)"
        }
        'Service' {
            foreach ($s in $Feat.Svcs) {
                $svc = Get-Service -Name $s.N -ErrorAction SilentlyContinue
                if ($svc) {
                    $bk[$s.N] = $svc.StartType.ToString()
                    try {
                        Set-Service -Name $s.N -StartupType Disabled -ErrorAction Stop
                        if ($svc.Status -eq 'Running') { Stop-Service -Name $s.N -Force -ErrorAction SilentlyContinue }
                    } catch { Write-Warn "Could not disable $($s.N): $_" }
                }
            }
            Write-Ok "$($Feat.ActionLabel): $($Feat.Name)"
        }
        'ScheduledTask' {
            foreach ($t in $Feat.Tasks) {
                try {
                    $tName = ($t -split '\\')[-1]; $tPath = $t -replace '[^\\]+$', ''
                    $task = Get-ScheduledTask -TaskName $tName -TaskPath $tPath -ErrorAction Stop
                    $bk[$t] = $task.State.ToString()
                    if ($task.State -ne 'Disabled') { $task | Disable-ScheduledTask -ErrorAction Stop | Out-Null }
                } catch { Write-Warn "Task not found: $t" }
            }
            Write-Ok "$($Feat.ActionLabel): $($Feat.Name)"
        }
    }
    return $bk
}

function Invoke-FeatureRevert ([hashtable]$Feat, $Backup) {
    if ($Feat.Type -eq 'Custom') { & $Feat.Revert $Backup; return }
    $bk = @{}
    if ($Backup) {
        if ($Backup -is [hashtable]) { $bk = $Backup }
        else { $Backup.PSObject.Properties | ForEach-Object { $bk[$_.Name] = $_.Value } }
    }

    switch ($Feat.Type) {
        'Registry' {
            foreach ($e in $Feat.Entries) {
                $key = "$($e.P)|$($e.N)"
                $prev = if ($bk.ContainsKey($key)) { $bk[$key] } else { $null }
                if ($null -ne $prev) {
                    $type = if ($e.ContainsKey('T')) { $e['T'] } else { 'DWord' }
                    Set-RegValue $e.P $e.N $prev $type
                } elseif ($null -ne $e.D) {
                    $type = if ($e.ContainsKey('T')) { $e['T'] } else { 'DWord' }
                    Set-RegValue $e.P $e.N $e.D $type
                } else {
                    Remove-RegValue $e.P $e.N
                }
            }
            Write-Ok "$($Feat.RevertLabel): $($Feat.Name)"
        }
        'Service' {
            foreach ($s in $Feat.Svcs) {
                $target = if ($bk.ContainsKey($s.N)) { $bk[$s.N] }
                           elseif ($null -ne $s.D) { $s.D }
                           else { 'Manual' }
                try { Set-Service -Name $s.N -StartupType $target -ErrorAction Stop }
                catch { Write-Warn "Could not restore $($s.N): $_" }
            }
            Write-Ok "$($Feat.RevertLabel): $($Feat.Name)"
        }
        'ScheduledTask' {
            foreach ($t in $Feat.Tasks) {
                try {
                    $tName = ($t -split '\\')[-1]; $tPath = $t -replace '[^\\]+$', ''
                    $task = Get-ScheduledTask -TaskName $tName -TaskPath $tPath -ErrorAction Stop
                    $task | Enable-ScheduledTask -ErrorAction Stop | Out-Null
                } catch {}
            }
            Write-Ok "$($Feat.RevertLabel): $($Feat.Name)"
        }
    }
}

$script:Features = [ordered]@{}
$F = $script:Features

$F['CpuMitigations'] = @{
    Name   = 'Disable CPU Exploit Mitigations (Spectre/Meltdown)'
    ActionLabel = 'APPLY'; RevertLabel = 'REVERT'
    Desc   = 'Disables Spectre, Meltdown, MDS and other CPU speculative execution mitigations via FeatureSettingsOverride registry keys.'
    Rec    = 'Disable on personal desktops for ~2-5% CPU overhead savings and reduced kernel memory usage.'
    Side   = 'Removes protection against speculative execution side-channel attacks. Negligible risk on single-user desktops.'
    Skip   = 'Multi-tenant servers, VMs running untrusted code, shared workstations, security-sensitive environments.'
    Reboot = $true; Impact = 'High'; Default = 'enable'
    Type   = 'Registry'
    Entries = @(
        @{ P='HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'; N='FeatureSettingsOverride'; O=3; D=0 },
        @{ P='HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'; N='FeatureSettingsOverrideMask'; O=3; D=3 }
    )
}

$F['VBS'] = @{
    Name   = 'Disable Virtualization Based Security (VBS/HVCI)'
    ActionLabel = 'APPLY'; RevertLabel = 'REVERT'
    Desc   = 'Permanently disables VBS, HVCI, and Credential Guard via registry and bcdedit. Prevents re-enabling after reboot. Does not touch Virtual Machine Platform.'
    Rec    = 'Disable to free significant memory. Most impactful single change for memory savings.'
    Side   = 'Disables Credential Guard (LSASS credential isolation) and kernel code integrity enforcement.'
    Skip   = 'Enterprise environments requiring Credential Guard, systems handling sensitive credentials.'
    Reboot = $true; Impact = 'High'; Default = 'enable'
    Type   = 'Custom'
    GetStatus = {
        $allOk = $true
        $partialDetails = [System.Collections.ArrayList]::new()
        $checks = @(
            @{ P='HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard'; N='EnableVirtualizationBasedSecurity'; E=0 },
            @{ P='HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity'; N='Enabled'; E=0 },
            @{ P='HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard'; N='LsaCfgFlags'; E=0 },
            @{ P='HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard'; N='RequirePlatformSecurityFeatures'; E=0 }
        )
        foreach ($chk in $checks) {
            $val = Get-RegValue $chk.P $chk.N
            if ($val -eq $chk.E) {
                [void]$partialDetails.Add("[+] $($chk.N)=$val")
            } else {
                $allOk = $false
                $valText = if ($null -eq $val) { 'not set' } else { $val }
                [void]$partialDetails.Add("[-] $($chk.N)=$valText (expected=$($chk.E))")
            }
        }
        try {
            $bcdOut = (& bcdedit /enum '{current}' 2>$null) -join "`n"
            if ($bcdOut -match 'hypervisorlaunchtype\s+Off') {
                [void]$partialDetails.Add('[+] hypervisorlaunchtype=Off')
            } else {
                $allOk = $false
                [void]$partialDetails.Add('[-] hypervisorlaunchtype not set to Off')
            }
        } catch {
            $allOk = $false
            [void]$partialDetails.Add('[-] Could not check bcdedit')
        }
        if ($allOk) { return @{ Optimized = $true; Text = 'APPLIED'; Details = @() } }
        if ($partialDetails.Count -ge 5) { return @{ Optimized = $false; Text = 'DEFAULT'; Details = @() } }
        return @{ Optimized = $false; Text = 'PARTIAL'; Details = @($partialDetails) }
    }
    Apply = {
        $bk = @{}
        $entries = @(
            @{ P='HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard'; N='EnableVirtualizationBasedSecurity' },
            @{ P='HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity'; N='Enabled' },
            @{ P='HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard'; N='LsaCfgFlags' },
            @{ P='HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard'; N='RequirePlatformSecurityFeatures' }
        )
        foreach ($e in $entries) { $bk["$($e.P)|$($e.N)"] = Get-RegValue $e.P $e.N }
        Set-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard' 'EnableVirtualizationBasedSecurity' 0
        Set-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' 'Enabled' 0
        Set-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard' 'LsaCfgFlags' 0
        Set-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard' 'RequirePlatformSecurityFeatures' 0
        Set-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' 'WasEnabledBy' 0
        try {
            $bcdOut = (& bcdedit /enum '{current}' 2>$null) -join "`n"
            $hvMatch = [regex]::Match($bcdOut, 'hypervisorlaunchtype\s+(\S+)')
            if ($hvMatch.Success) { $bk['hypervisorlaunchtype'] = $hvMatch.Groups[1].Value }
            & bcdedit /set hypervisorlaunchtype off 2>$null | Out-Null
        } catch {}
        Write-Ok 'APPLY: Disable Virtualization Based Security (VBS/HVCI)'
        return $bk
    }
    Revert = {
        param($Backup)
        $bk = @{}
        if ($Backup) {
            if ($Backup -is [hashtable]) { $bk = $Backup }
            else { $Backup.PSObject.Properties | ForEach-Object { $bk[$_.Name] = $_.Value } }
        }
        $restores = @(
            @{ P='HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard'; N='EnableVirtualizationBasedSecurity'; D=1 },
            @{ P='HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity'; N='Enabled'; D=1 },
            @{ P='HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard'; N='LsaCfgFlags'; D=0 },
            @{ P='HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard'; N='RequirePlatformSecurityFeatures'; D=0 }
        )
        foreach ($r in $restores) {
            $key = "$($r.P)|$($r.N)"
            $val = if ($bk.ContainsKey($key) -and $null -ne $bk[$key]) { $bk[$key] } else { $r.D }
            Set-RegValue $r.P $r.N $val
        }
        Remove-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' 'WasEnabledBy'
        try { & bcdedit /set hypervisorlaunchtype auto 2>$null | Out-Null } catch {}
        Write-Ok 'REVERT: Disable Virtualization Based Security (VBS/HVCI)'
    }
    Backup = {
        $bk = @{}
        $entries = @(
            @{ P='HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard'; N='EnableVirtualizationBasedSecurity' },
            @{ P='HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity'; N='Enabled' },
            @{ P='HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard'; N='LsaCfgFlags' },
            @{ P='HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard'; N='RequirePlatformSecurityFeatures' }
        )
        foreach ($e in $entries) { $bk["$($e.P)|$($e.N)"] = Get-RegValue $e.P $e.N }
        try {
            $bcdOut = (& bcdedit /enum '{current}' 2>$null) -join "`n"
            $hvMatch = [regex]::Match($bcdOut, 'hypervisorlaunchtype\s+(\S+)')
            if ($hvMatch.Success) { $bk['hypervisorlaunchtype'] = $hvMatch.Groups[1].Value }
        } catch {}
        return $bk
    }
}

$F['XboxServices'] = @{
    Name   = 'Disable Xbox Gaming Services'
    ActionLabel = 'APPLY'; RevertLabel = 'REVERT'
    Desc   = 'Disables Xbox achievement sync, authentication, networking, and accessory support.'
    Rec    = 'Disable unless you actively use Xbox features, Game Pass, or Xbox wireless controllers.'
    Side   = 'Xbox app features stop working, Game Pass may fail, Xbox wireless controller pairing breaks.'
    Skip   = 'If you use Xbox Game Pass, Xbox app, or Xbox wireless controllers.'
    Reboot = $false; Impact = 'Low'; Default = 'enable'
    Type   = 'Service'
    Svcs   = @(
        @{ N='XblGameSave';    D='Manual' },
        @{ N='XblAuthManager'; D='Manual' },
        @{ N='XboxNetApiSvc';  D='Manual' },
        @{ N='XboxGipSvc';     D='Manual' }
    )
}

$F['TelemetryServices'] = @{
    Name   = 'Disable Telemetry & Diagnostics Services'
    ActionLabel = 'APPLY'; RevertLabel = 'REVERT'
    Desc   = 'Disables Connected User Experiences (DiagTrack) and WAP Push. DiagTrack can use 50-150MB RAM.'
    Rec    = 'Disable to save memory and reduce background I/O.'
    Side   = 'Windows telemetry stops. Some diagnostic features show limited info.'
    Skip   = 'If enterprise policies require telemetry.'
    Reboot = $false; Impact = 'Medium'; Default = 'enable'
    Type   = 'Service'
    Svcs   = @(
        @{ N='DiagTrack';        D='Automatic' },
        @{ N='dmwappushservice'; D='Manual' }
    )
}

$F['FaxService'] = @{
    Name   = 'Disable Fax Service'
    ActionLabel = 'APPLY'; RevertLabel = 'REVERT'
    Desc   = 'Disables the Windows Fax service for sending/receiving faxes via fax modem.'
    Rec    = 'Safe to disable. Almost nobody uses fax modems anymore.'
    Side   = 'Cannot send/receive faxes via Windows Fax and Scan.'
    Skip   = 'If you have a fax modem and actively use Windows Fax and Scan.'
    Reboot = $false; Impact = 'Low'; Default = 'enable'
    Type   = 'Service'
    Svcs   = @( @{ N='Fax'; D='Manual' } )
}

$F['RetailDemo'] = @{
    Name   = 'Disable Retail Demo Service'
    ActionLabel = 'APPLY'; RevertLabel = 'REVERT'
    Desc   = 'Disables the Retail Demo experience used in store display units.'
    Rec    = 'Safe to disable on all personal and enterprise PCs.'
    Side   = 'Retail demo mode unavailable (only used in stores).'
    Skip   = 'Only on retail store display kiosks.'
    Reboot = $false; Impact = 'Low'; Default = 'enable'
    Type   = 'Service'
    Svcs   = @( @{ N='RetailDemo'; D='Manual' } )
}

$F['WMPNetworkSvc'] = @{
    Name   = 'Disable Windows Media Player Network Sharing'
    ActionLabel = 'APPLY'; RevertLabel = 'REVERT'
    Desc   = 'Disables WMP DLNA/UPnP media streaming to other devices on the network.'
    Rec    = 'Disable if you use VLC, Plex, or other media players.'
    Side   = 'Cannot stream media from WMP to DLNA devices (TVs, receivers).'
    Skip   = 'If you use WMP as a DLNA media server.'
    Reboot = $false; Impact = 'Low'; Default = 'enable'
    Type   = 'Service'
    Svcs   = @( @{ N='WMPNetworkSvc'; D='Manual' } )
}

$F['TabletInputService'] = @{
    Name   = 'Disable Tablet PC Input Service'
    ActionLabel = 'APPLY'; RevertLabel = 'REVERT'
    Desc   = 'Disables pen, touch, and tablet input services for handwriting recognition and gestures.'
    Rec    = 'Disable on desktops without touchscreen or pen input.'
    Side   = 'Pen input, touch gestures, and handwriting recognition stop working.'
    Skip   = 'If you have a touchscreen, pen/stylus, or use handwriting input.'
    Reboot = $false; Impact = 'Low'; Default = 'enable'
    Type   = 'Service'
    Svcs   = @( @{ N='TabletInputService'; D='Manual' } )
}

$F['PhoneSvc'] = @{
    Name   = 'Disable Phone Service'
    ActionLabel = 'APPLY'; RevertLabel = 'REVERT'
    Desc   = 'Disables the telephony state management service used by Phone Link and VoIP.'
    Rec    = 'Disable if you do not use Phone Link or VoIP calling features.'
    Side   = 'Phone Link app stops working. VoIP integration features disabled.'
    Skip   = 'If you use Phone Link or Windows telephony features.'
    Reboot = $false; Impact = 'Low'; Default = 'enable'
    Type   = 'Service'
    Svcs   = @( @{ N='PhoneSvc'; D='Manual' } )
}

$F['NFCPayments'] = @{
    Name   = 'Disable NFC/Payments Service (SEMgrSvc)'
    ActionLabel = 'APPLY'; RevertLabel = 'REVERT'
    Desc   = 'Disables the Secure Element Manager for NFC-based payments and secure element access.'
    Rec    = 'Disable on PCs without NFC hardware or tap-to-pay usage.'
    Side   = 'NFC payments and secure element features stop working.'
    Skip   = 'If your device has NFC and you use tap-to-pay or NFC features.'
    Reboot = $false; Impact = 'Low'; Default = 'enable'
    Type   = 'Service'
    Svcs   = @( @{ N='SEMgrSvc'; D='Manual' } )
}

$F['MapsBroker'] = @{
    Name   = 'Disable Maps Download Manager (MapsBroker)'
    ActionLabel = 'APPLY'; RevertLabel = 'REVERT'
    Desc   = 'Disables the background service that downloads and updates offline map data.'
    Rec    = 'Disable if you do not use Windows Maps or offline navigation.'
    Side   = 'Offline maps will not auto-update. Windows Maps app may show stale data.'
    Skip   = 'If you use Windows Maps for offline navigation.'
    Reboot = $false; Impact = 'Low'; Default = 'enable'
    Type   = 'Service'
    Svcs   = @( @{ N='MapsBroker'; D='Automatic' } )
}

$F['NetworkServices'] = @{
    Name   = 'Disable Legacy Network Services'
    ActionLabel = 'APPLY'; RevertLabel = 'REVERT'
    Desc   = 'Disables Internet Connection Sharing, Remote Registry, and Distributed Link Tracking Client.'
    Rec    = 'Disable unless you use ICS, remote registry editing, or NTFS link tracking across volumes.'
    Side   = 'ICS/hotspot sharing stops, remote registry disabled (security improvement), shortcut tracking breaks.'
    Skip   = 'If you share internet via ICS or administer registries remotely.'
    Reboot = $false; Impact = 'Low'; Default = 'enable'
    Type   = 'Service'
    Svcs   = @(
        @{ N='SharedAccess';   D='Manual' },
        @{ N='RemoteRegistry'; D='Manual' },
        @{ N='TrkWks';         D='Automatic' }
    )
}

$F['RemoteDesktopClient'] = @{
    Name   = 'Disable Remote Desktop Client Services'
    ActionLabel = 'APPLY'; RevertLabel = 'REVERT'
    Desc   = 'Disables Remote Desktop Services and UmRdpService for remote connections.'
    Rec    = 'Disable if you never use Remote Desktop.'
    Side   = 'Cannot receive Remote Desktop connections.'
    Skip   = 'If you use Remote Desktop to connect to this PC.'
    Reboot = $false; Impact = 'Low'; Default = 'skip'
    Type   = 'Service'
    Svcs   = @(
        @{ N='TermService';   D='Manual' },
        @{ N='UmRdpService';  D='Manual' }
    )
}

$F['WorkFolders'] = @{
    Name   = 'Disable Work Folders Client'
    ActionLabel = 'APPLY'; RevertLabel = 'REVERT'
    Desc   = 'Disables the Work Folders file sync service used in enterprise environments.'
    Rec    = 'Disable on personal PCs without enterprise file sync.'
    Side   = 'Work Folders file synchronization stops.'
    Skip   = 'If your organization uses Work Folders for file sync.'
    Reboot = $false; Impact = 'Low'; Default = 'enable'
    Type   = 'Service'
    Svcs   = @( @{ N='workfolderssvc'; D='Manual' } )
}

$F['SearchService'] = @{
    Name   = 'Disable Windows Search Indexer (WSearch)'
    ActionLabel = 'APPLY'; RevertLabel = 'REVERT'
    Desc   = 'Disables the search indexing service. Uses 100-500MB+ RAM and continuous disk I/O.'
    Rec    = 'Disable if you use Everything, Listary, or rarely search from Start.'
    Side   = 'Start menu search, Explorer search, and Outlook desktop search become much slower.'
    Skip   = 'If you rely on fast Start menu search or Outlook desktop search.'
    Reboot = $true; Impact = 'Medium'; Default = 'skip'
    Type   = 'Service'
    Svcs   = @( @{ N='WSearch'; D='Automatic' } )
}

$F['SuperfetchService'] = @{
    Name   = 'Disable SysMain (Superfetch/Prefetch)'
    ActionLabel = 'APPLY'; RevertLabel = 'REVERT'
    Desc   = 'Disables SysMain which preloads frequently-used apps into RAM. Uses 200-800MB of standby memory.'
    Rec    = 'Disable on SSD-based systems where prefetching provides minimal benefit.'
    Side   = 'First launch of frequently-used apps may be slightly slower. Negligible on SSDs.'
    Skip   = 'On HDD-only systems where prefetching significantly improves launch times.'
    Reboot = $true; Impact = 'Medium'; Default = 'enable'
    Type   = 'Service'
    Svcs   = @( @{ N='SysMain'; D='Automatic' } )
}

$F['InsiderService'] = @{
    Name   = 'Disable Windows Insider Service'
    ActionLabel = 'APPLY'; RevertLabel = 'REVERT'
    Desc   = 'Disables the Windows Insider Program service that manages preview builds.'
    Rec    = 'Disable if not enrolled in Insider Program.'
    Side   = 'Cannot join or receive Insider Preview builds.'
    Skip   = 'If you are enrolled in Windows Insider Program.'
    Reboot = $false; Impact = 'Low'; Default = 'enable'
    Type   = 'Service'
    Svcs   = @( @{ N='wisvc'; D='Manual' } )
}

$F['LocationService'] = @{
    Name   = 'Disable Location Service'
    ActionLabel = 'APPLY'; RevertLabel = 'REVERT'
    Desc   = 'Disables the system location service providing GPS/Wi-Fi location to apps.'
    Rec    = 'Disable on desktops where location-aware apps are not needed.'
    Side   = 'Weather, Maps, Find My Device and location-based features stop working.'
    Skip   = 'If you use location-dependent apps or Find My Device on a laptop.'
    Reboot = $false; Impact = 'Low'; Default = 'enable'
    Type   = 'Service'
    Svcs   = @( @{ N='lfsvc'; D='Manual' } )
}

$F['PrintSpooler'] = @{
    Name   = 'Disable Print Spooler Service'
    ActionLabel = 'APPLY'; RevertLabel = 'REVERT'
    Desc   = 'Disables the Print Spooler. Source of multiple critical vulnerabilities (PrintNightmare). Uses ~20-40MB.'
    Rec    = 'Disable if you have no printers. Reduces attack surface.'
    Side   = 'Cannot print to any local or network printer. Print-to-PDF still works.'
    Skip   = 'If you print to any physical or network printer.'
    Reboot = $false; Impact = 'Low'; Default = 'skip'
    Type   = 'Service'
    Svcs   = @( @{ N='Spooler'; D='Automatic' } )
}

$F['ErrorReporting'] = @{
    Name   = 'Disable Windows Error Reporting (WerSvc)'
    ActionLabel = 'APPLY'; RevertLabel = 'REVERT'
    Desc   = 'Disables crash dump collection and reporting to Microsoft.'
    Rec    = 'Disable to reduce background memory and disk usage.'
    Side   = 'Crash reports not sent. Reliability Monitor will be empty.'
    Skip   = 'If you rely on Windows Error Reporting for crash analytics.'
    Reboot = $false; Impact = 'Low'; Default = 'enable'
    Type   = 'Service'
    Svcs   = @( @{ N='WerSvc'; D='Manual' } )
}

$F['BrowserPolicies'] = @{
    Name   = 'Set Chrome/Edge Security Policies (Memory Saving)'
    ActionLabel = 'APPLY'; RevertLabel = 'REVERT'
    Desc   = 'Disables renderer code integrity, app container sandboxing. Enables High Efficiency Mode. Disables background mode.'
    Rec    = 'Enable to reduce per-tab memory overhead by ~10-30MB.'
    Side   = 'Slightly reduced browser sandbox security. Background extensions stop when browser is closed.'
    Skip   = 'On shared/kiosk machines where browser sandbox integrity is critical.'
    Reboot = $false; Impact = 'Medium'; Default = 'enable'
    Type   = 'Registry'
    Entries = @(
        @{ P='HKLM:\SOFTWARE\Policies\Google\Chrome'; N='RendererCodeIntegrityEnabled'; O=0; D=$null },
        @{ P='HKLM:\SOFTWARE\Policies\Google\Chrome'; N='RendererAppContainerEnabled';  O=0; D=$null },
        @{ P='HKLM:\SOFTWARE\Policies\Google\Chrome'; N='HighEfficiencyModeEnabled';    O=1; D=$null },
        @{ P='HKLM:\SOFTWARE\Policies\Google\Chrome'; N='BackgroundModeEnabled';        O=0; D=$null },
        @{ P='HKLM:\SOFTWARE\Policies\Google\Chrome'; N='HardwareSecureDecryptionDisabled'; O=1; D=$null },
        @{ P='HKLM:\SOFTWARE\Policies\Microsoft\Edge'; N='RendererCodeIntegrityEnabled'; O=0; D=$null },
        @{ P='HKLM:\SOFTWARE\Policies\Microsoft\Edge'; N='RendererAppContainerEnabled';  O=0; D=$null },
        @{ P='HKLM:\SOFTWARE\Policies\Microsoft\Edge'; N='HighEfficiencyModeEnabled';    O=1; D=$null },
        @{ P='HKLM:\SOFTWARE\Policies\Microsoft\Edge'; N='BackgroundModeEnabled';        O=0; D=$null },
        @{ P='HKLM:\SOFTWARE\Policies\Microsoft\Edge'; N='HardwareSecureDecryptionDisabled'; O=1; D=$null }
    )
}

$F['BrowserFlags'] = @{
    Name   = 'Set Chrome/Edge Experimental Flags'
    ActionLabel = 'APPLY'; RevertLabel = 'REVERT'
    Desc   = 'Sets performance-oriented chrome://flags: tab discarding, native occlusion, back-forward cache, parallel downloading.'
    Rec    = 'Enable for better tab memory management.'
    Side   = 'Experimental flags may change behavior between browser versions.'
    Skip   = 'If you need deterministic browser behavior.'
    Reboot = $false; Impact = 'Low'; Default = 'enable'
    Type   = 'Custom'
    GetStatus = {
        $anySet = $false
        foreach ($ls in @(
            "$env:LOCALAPPDATA\Google\Chrome\User Data\Local State",
            "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Local State"
        )) {
            if (Test-Path $ls) {
                try {
                    $json = Get-Content $ls -Raw | ConvertFrom-Json
                    if ($json.browser.enabled_labs_experiments -match 'enable-tab-discarding') { $anySet = $true }
                } catch {}
            }
        }
        if ($anySet) { return @{ Optimized = $true; Text = 'APPLIED'; Details = @() } }
        return @{ Optimized = $false; Text = 'DEFAULT'; Details = @() }
    }
    Apply = {
        $bk = @{}
        $memFlags = @(
            'enable-tab-discarding@1', 'calculate-native-win-occlusion@1',
            'back-forward-cache@1', 'enable-parallel-downloading@1'
        )
        foreach ($ls in @(
            "$env:LOCALAPPDATA\Google\Chrome\User Data\Local State",
            "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Local State"
        )) {
            if (Test-Path $ls) {
                try {
                    $json = Get-Content $ls -Raw | ConvertFrom-Json
                    if (-not $json.browser) { $json | Add-Member -NotePropertyName 'browser' -NotePropertyValue ([PSCustomObject]@{}) -Force }
                    $existing = @()
                    try { $existing = @($json.browser.enabled_labs_experiments) } catch {}
                    $bk[$ls] = ($existing -join '|')
                    if (-not $json.browser.enabled_labs_experiments) {
                        $json.browser | Add-Member -NotePropertyName 'enabled_labs_experiments' -NotePropertyValue @() -Force
                    }
                    $flags = [System.Collections.ArrayList]@($json.browser.enabled_labs_experiments)
                    foreach ($mf in $memFlags) {
                        $flagName = ($mf -split '@')[0]
                        $flags = [System.Collections.ArrayList]@($flags | Where-Object { $_ -notmatch "^$flagName@" })
                        [void]$flags.Add($mf)
                    }
                    $json.browser.enabled_labs_experiments = $flags.ToArray()
                    $json | ConvertTo-Json -Depth 20 | Set-Content $ls -Encoding UTF8
                    Write-Ok "Updated flags in $ls"
                } catch { Write-Warn "Could not update ${ls}: $_" }
            }
        }
        return $bk
    }
    Revert = {
        param($Backup)
        $bk = @{}
        if ($Backup) {
            if ($Backup -is [hashtable]) { $bk = $Backup }
            else { $Backup.PSObject.Properties | ForEach-Object { $bk[$_.Name] = $_.Value } }
        }
        foreach ($ls in @(
            "$env:LOCALAPPDATA\Google\Chrome\User Data\Local State",
            "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Local State"
        )) {
            if (Test-Path $ls) {
                try {
                    $json = Get-Content $ls -Raw | ConvertFrom-Json
                    if ($bk.ContainsKey($ls) -and $bk[$ls]) {
                        $json.browser.enabled_labs_experiments = $bk[$ls] -split '\|'
                    } else {
                        $remove = @('enable-tab-discarding','calculate-native-win-occlusion','back-forward-cache','enable-parallel-downloading')
                        $flags = @($json.browser.enabled_labs_experiments | Where-Object { $n = ($_ -split '@')[0]; $n -notin $remove })
                        $json.browser.enabled_labs_experiments = $flags
                    }
                    $json | ConvertTo-Json -Depth 20 | Set-Content $ls -Encoding UTF8
                } catch {}
            }
        }
        Write-Ok 'REVERT: Set Chrome/Edge Experimental Flags'
    }
    Backup = {
        $bk = @{}
        foreach ($ls in @(
            "$env:LOCALAPPDATA\Google\Chrome\User Data\Local State",
            "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Local State"
        )) {
            if (Test-Path $ls) {
                try {
                    $json = Get-Content $ls -Raw | ConvertFrom-Json
                    $bk[$ls] = ($json.browser.enabled_labs_experiments -join '|')
                } catch {}
            }
        }
        return $bk
    }
}

$F['WindowsRecall'] = @{
    Name   = 'Disable Windows Recall (AI Snapshots)'
    ActionLabel = 'APPLY'; RevertLabel = 'REVERT'
    Desc   = 'Disables Windows Recall which periodically screenshots your desktop and uses AI to make them searchable. Uses several GB RAM + disk.'
    Rec    = 'Disable to prevent continuous AI processing and snapshot storage.'
    Side   = 'Recall timeline search unavailable.'
    Skip   = 'If you find Recall search valuable and have ample RAM (32GB+).'
    Reboot = $false; Impact = 'Medium'; Default = 'enable'
    Type   = 'Registry'
    Entries = @(
        @{ P='HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI'; N='DisableAIDataAnalysis'; O=1; D=$null },
        @{ P='HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI'; N='TurnOffSavingSnapshots'; O=1; D=$null }
    )
}

$F['WindowsCopilot'] = @{
    Name   = 'Disable Windows Copilot'
    ActionLabel = 'APPLY'; RevertLabel = 'REVERT'
    Desc   = 'Disables Windows Copilot AI assistant sidebar. Saves ~100-200MB from the background web process.'
    Rec    = 'Disable to save memory from the Copilot sidebar process.'
    Side   = 'Copilot sidebar and Win+C shortcut stop working. Does not affect Copilot in Edge or Office.'
    Skip   = 'If you actively use Windows Copilot.'
    Reboot = $false; Impact = 'Low'; Default = 'enable'
    Type   = 'Registry'
    Entries = @(
        @{ P='HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot'; N='TurnOffWindowsCopilot'; O=1; D=$null },
        @{ P='HKCU:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot'; N='TurnOffWindowsCopilot'; O=1; D=$null }
    )
}

$F['AICloudContent'] = @{
    Name   = 'Disable AI Search, Cloud Content & Spotlight'
    ActionLabel = 'APPLY'; RevertLabel = 'REVERT'
    Desc   = 'Disables AI-powered search suggestions, cloud-optimized content, Spotlight, and app suggestion prompts.'
    Rec    = 'Disable to reduce network and memory usage from cloud content fetching.'
    Side   = 'Search loses web suggestions. Spotlight images and app suggestions stop.'
    Skip   = 'If you enjoy Spotlight lock screen images or web search suggestions.'
    Reboot = $false; Impact = 'Low'; Default = 'enable'
    Type   = 'Registry'
    Entries = @(
        @{ P='HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer';      N='DisableSearchBoxSuggestions'; O=1; D=$null },
        @{ P='HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent';  N='DisableCloudOptimizedContent'; O=1; D=$null },
        @{ P='HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent';  N='DisableWindowsSpotlightFeatures'; O=1; D=$null },
        @{ P='HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent';  N='DisableSoftLanding'; O=1; D=$null }
    )
}

$F['AIScheduledTasks'] = @{
    Name   = 'Disable AI/NPU Scheduled Tasks'
    ActionLabel = 'APPLY'; RevertLabel = 'REVERT'
    Desc   = 'Disables scheduled tasks for Windows AI and Recall that periodically activate the NPU/CPU.'
    Rec    = 'Disable to prevent periodic AI background processing.'
    Side   = 'AI features depending on scheduled processing stop running.'
    Skip   = 'If you use Recall or Copilot+ PC features requiring background AI.'
    Reboot = $false; Impact = 'Low'; Default = 'enable'
    Type   = 'Custom'
    GetStatus = {
        $allDisabled = $true; $found = $false
        $partialDetails = [System.Collections.ArrayList]::new()
        foreach ($tp in @('\Microsoft\Windows\WindowsAI\', '\Microsoft\Windows\Recall\')) {
            Get-ScheduledTask -TaskPath $tp -ErrorAction SilentlyContinue | ForEach-Object {
                $found = $true
                if ($_.State -eq 'Disabled') {
                    [void]$partialDetails.Add("[+] $($_.TaskName)=Disabled")
                } else {
                    $allDisabled = $false
                    [void]$partialDetails.Add("[-] $($_.TaskName)=$($_.State) (expected=Disabled)")
                }
            }
        }
        if (-not $found) { return @{ Optimized = $null; Text = 'N/A'; Details = @() } }
        if ($allDisabled) { return @{ Optimized = $true; Text = 'APPLIED'; Details = @() } }
        return @{ Optimized = $false; Text = 'PARTIAL'; Details = @($partialDetails) }
    }
    Apply = {
        $bk = @{}
        foreach ($tp in @('\Microsoft\Windows\WindowsAI\', '\Microsoft\Windows\Recall\')) {
            Get-ScheduledTask -TaskPath $tp -ErrorAction SilentlyContinue | ForEach-Object {
                $bk["$($_.TaskPath)$($_.TaskName)"] = $_.State.ToString()
                try { $_ | Disable-ScheduledTask -ErrorAction Stop | Out-Null } catch {}
            }
        }
        Write-Ok 'APPLY: Disable AI/NPU Scheduled Tasks'
        return $bk
    }
    Revert = {
        param($Backup)
        foreach ($tp in @('\Microsoft\Windows\WindowsAI\', '\Microsoft\Windows\Recall\')) {
            Get-ScheduledTask -TaskPath $tp -ErrorAction SilentlyContinue | ForEach-Object {
                try { $_ | Enable-ScheduledTask -ErrorAction Stop | Out-Null } catch {}
            }
        }
        Write-Ok 'REVERT: Disable AI/NPU Scheduled Tasks'
    }
    Backup = {
        $bk = @{}
        foreach ($tp in @('\Microsoft\Windows\WindowsAI\', '\Microsoft\Windows\Recall\')) {
            Get-ScheduledTask -TaskPath $tp -ErrorAction SilentlyContinue | ForEach-Object {
                $bk["$($_.TaskPath)$($_.TaskName)"] = $_.State.ToString()
            }
        }
        return $bk
    }
}

$F['TelemetryLevel'] = @{
    Name   = 'Minimize Telemetry Data Collection'
    ActionLabel = 'APPLY'; RevertLabel = 'REVERT'
    Desc   = 'Sets Windows telemetry to Security level (0) the minimum. Default sends considerable diagnostic data.'
    Rec    = 'Set to 0 to minimize data collection overhead and network usage.'
    Side   = 'Some diagnostic features show less data. Windows Update still works.'
    Skip   = 'If enterprise policies require specific telemetry levels.'
    Reboot = $false; Impact = 'Low'; Default = 'enable'
    Type   = 'Registry'
    Entries = @(
        @{ P='HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; N='AllowTelemetry'; O=0; D=$null }
    )
}

$F['DeliveryOptimization'] = @{
    Name   = 'Disable Delivery Optimization P2P'
    ActionLabel = 'APPLY'; RevertLabel = 'REVERT'
    Desc   = 'Disables peer-to-peer delivery of Windows Updates (set to HTTP only).'
    Rec    = 'Disable P2P to reduce background network and memory usage.'
    Side   = 'Updates download only from Microsoft. Slightly slower on LANs with multiple PCs.'
    Skip   = 'On large LANs where P2P update delivery saves internet bandwidth.'
    Reboot = $false; Impact = 'Low'; Default = 'enable'
    Type   = 'Registry'
    Entries = @(
        @{ P='HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization'; N='DODownloadMode'; O=0; D=$null }
    )
}

$F['ActivityHistory'] = @{
    Name   = 'Disable Activity History & Timeline'
    ActionLabel = 'APPLY'; RevertLabel = 'REVERT'
    Desc   = 'Disables Activity History feed, user activity publishing, and uploading. Timeline is effectively deprecated.'
    Rec    = 'Disable to reduce background sync and memory usage.'
    Side   = 'Timeline in Task View stops. Cross-device activity sync stops.'
    Skip   = 'If you use Timeline to resume activities across devices.'
    Reboot = $false; Impact = 'Low'; Default = 'enable'
    Type   = 'Registry'
    Entries = @(
        @{ P='HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'; N='EnableActivityFeed'; O=0; D=$null },
        @{ P='HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'; N='PublishUserActivities'; O=0; D=$null },
        @{ P='HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'; N='UploadUserActivities'; O=0; D=$null }
    )
}

$F['TelemetryTasks'] = @{
    Name   = 'Disable Telemetry & Compatibility Scheduled Tasks'
    ActionLabel = 'APPLY'; RevertLabel = 'REVERT'
    Desc   = 'Disables Compatibility Appraiser, CEIP tasks, Disk Diagnostic, WinSAT, Maps updates, Feedback tasks. Appraiser alone can use 200MB+.'
    Rec    = 'Disable to prevent periodic background scans.'
    Side   = 'Compatibility telemetry stops. WinSAT scores not updated. Offline maps not updated.'
    Skip   = 'If you need compatibility assessment or automatic map updates.'
    Reboot = $false; Impact = 'Low'; Default = 'enable'
    Type   = 'ScheduledTask'
    Tasks  = @(
        '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser',
        '\Microsoft\Windows\Application Experience\ProgramDataUpdater',
        '\Microsoft\Windows\Customer Experience Improvement Program\Consolidator',
        '\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip',
        '\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector',
        '\Microsoft\Windows\Maintenance\WinSAT',
        '\Microsoft\Windows\Maps\MapsUpdateTask',
        '\Microsoft\Windows\Maps\MapsToastTask',
        '\Microsoft\Windows\Feedback\Siuf\DmClient',
        '\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload'
    )
}

$F['VisualEffectsPreset'] = @{
    Name   = 'Set Visual Effects to Best Performance'
    ActionLabel = 'APPLY'; RevertLabel = 'REVERT'
    Desc   = 'Sets system visual effects to "Best Performance" (disables all animations, smooth scrolling, shadows, etc.).'
    Rec    = 'Enable to reduce DWM memory usage by 50-200MB.'
    Side   = 'UI looks flatter and less polished. No smooth scrolling or animated transitions.'
    Skip   = 'If visual quality matters or you do design/creative work.'
    Reboot = $false; Impact = 'Medium'; Default = 'skip'
    Type   = 'Registry'
    Entries = @(
        @{ P='HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects'; N='VisualFXSetting'; O=2; D=0 }
    )
}

$F['WindowTransparency'] = @{
    Name   = 'Disable Window Transparency Effects'
    ActionLabel = 'APPLY'; RevertLabel = 'REVERT'
    Desc   = 'Disables acrylic/mica transparency in taskbar, Start menu, Action Center, and title bars.'
    Rec    = 'Disable to reduce DWM GPU memory usage (~30-50MB).'
    Side   = 'Taskbar and windows lose translucent blur effects. Purely cosmetic.'
    Skip   = 'If you prefer the modern translucent Windows aesthetic.'
    Reboot = $false; Impact = 'Low'; Default = 'enable'
    Type   = 'Registry'
    Entries = @(
        @{ P='HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'; N='EnableTransparency'; O=0; D=1 }
    )
}

$F['MenuAnimations'] = @{
    Name   = 'Disable Menu Animations & Aero Peek'
    ActionLabel = 'APPLY'; RevertLabel = 'REVERT'
    Desc   = 'Disables menu fade/slide animations (MenuShowDelay=0) and Aero Peek (desktop preview on hover).'
    Rec    = 'Disable for snappier UI response.'
    Side   = 'Menus appear instantly without animation. Desktop peek on hover disabled.'
    Skip   = 'If you prefer animated UI transitions.'
    Reboot = $false; Impact = 'Low'; Default = 'enable'
    Type   = 'Custom'
    GetStatus = {
        $delay = Get-RegValue 'HKCU:\Control Panel\Desktop' 'MenuShowDelay'
        $peek  = Get-RegValue 'HKCU:\Software\Microsoft\Windows\DWM' 'EnableAeroPeek'
        $partialDetails = [System.Collections.ArrayList]::new()
        $allOpt = $true; $allDef = $true
        if ($delay -eq '0') {
            [void]$partialDetails.Add('[+] MenuShowDelay=0')
        } else {
            $allOpt = $false
            [void]$partialDetails.Add("[-] MenuShowDelay=$delay (expected=0)")
        }
        if ($delay -eq '0') { $allDef = $false }
        if ($peek -eq 0) {
            [void]$partialDetails.Add('[+] EnableAeroPeek=0')
        } else {
            $allOpt = $false
            [void]$partialDetails.Add("[-] EnableAeroPeek=$peek (expected=0)")
        }
        if ($peek -eq 0) { $allDef = $false }
        if ($allOpt) { return @{ Optimized = $true; Text = 'APPLIED'; Details = @() } }
        if ($allDef) { return @{ Optimized = $false; Text = 'DEFAULT'; Details = @() } }
        return @{ Optimized = $false; Text = 'PARTIAL'; Details = @($partialDetails) }
    }
    Apply = {
        $bk = @{
            MenuShowDelay = Get-RegValue 'HKCU:\Control Panel\Desktop' 'MenuShowDelay'
            EnableAeroPeek = Get-RegValue 'HKCU:\Software\Microsoft\Windows\DWM' 'EnableAeroPeek'
        }
        Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name 'MenuShowDelay' -Value '0' -Type String
        Set-RegValue 'HKCU:\Software\Microsoft\Windows\DWM' 'EnableAeroPeek' 0
        Write-Ok 'APPLY: Disable Menu Animations & Aero Peek'
        return $bk
    }
    Revert = {
        param($Backup)
        $bk = @{}
        if ($Backup) {
            if ($Backup -is [hashtable]) { $bk = $Backup }
            else { $Backup.PSObject.Properties | ForEach-Object { $bk[$_.Name] = $_.Value } }
        }
        $delay = if ($bk.ContainsKey('MenuShowDelay') -and $null -ne $bk['MenuShowDelay']) { $bk['MenuShowDelay'] } else { '400' }
        $peek  = if ($bk.ContainsKey('EnableAeroPeek') -and $null -ne $bk['EnableAeroPeek']) { [int]$bk['EnableAeroPeek'] } else { 1 }
        Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name 'MenuShowDelay' -Value $delay -Type String
        Set-RegValue 'HKCU:\Software\Microsoft\Windows\DWM' 'EnableAeroPeek' $peek
        Write-Ok 'REVERT: Disable Menu Animations & Aero Peek'
    }
    Backup = {
        return @{
            MenuShowDelay = Get-RegValue 'HKCU:\Control Panel\Desktop' 'MenuShowDelay'
            EnableAeroPeek = Get-RegValue 'HKCU:\Software\Microsoft\Windows\DWM' 'EnableAeroPeek'
        }
    }
}

$F['PrefetchRegistry'] = @{
    Name   = 'Disable Prefetch/Superfetch Registry Settings'
    ActionLabel = 'APPLY'; RevertLabel = 'REVERT'
    Desc   = 'Sets EnablePrefetcher and EnableSuperfetch to 0. Controls memory-resident prefetch database.'
    Rec    = 'Disable on SSD systems to eliminate prefetch database overhead.'
    Side   = 'App launch prediction data not maintained. Negligible impact on SSDs.'
    Skip   = 'On HDD-only systems where prefetch provides meaningful speedup.'
    Reboot = $true; Impact = 'Medium'; Default = 'enable'
    Type   = 'Registry'
    Entries = @(
        @{ P='HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters'; N='EnablePrefetcher'; O=0; D=3 },
        @{ P='HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters'; N='EnableSuperfetch'; O=0; D=3 }
    )
}

$F['BackgroundApps'] = @{
    Name   = 'Deny Background Apps'
    ActionLabel = 'APPLY'; RevertLabel = 'REVERT'
    Desc   = 'Denies UWP/Store apps from running in background via group policy.'
    Rec    = 'Deny to prevent Store apps from consuming memory when not visible.'
    Side   = 'Live tiles stop. Store app notifications delayed. Mail will not sync in background.'
    Skip   = 'If you depend on Store app notifications (Mail, Calendar).'
    Reboot = $false; Impact = 'Medium'; Default = 'enable'
    Type   = 'Registry'
    Entries = @(
        @{ P='HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy'; N='LetAppsRunInBackground'; O=2; D=$null }
    )
}

$F['GameBarDVR'] = @{
    Name   = 'Disable Game Bar & Game DVR'
    ActionLabel = 'APPLY'; RevertLabel = 'REVERT'
    Desc   = 'Disables Xbox Game Bar overlay and recording. Saves ~50-100MB from the always-running process.'
    Rec    = 'Disable unless you use Game Bar for screenshots, recording, or FPS counter.'
    Side   = 'Win+G overlay, game recording, and performance monitor overlay stop. Third-party tools unaffected.'
    Skip   = 'If you use Game Bar for screenshots, recording, or Xbox social features.'
    Reboot = $false; Impact = 'Low'; Default = 'enable'
    Type   = 'Registry'
    Entries = @(
        @{ P='HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR'; N='AllowGameDVR'; O=0; D=$null },
        @{ P='HKCU:\System\GameConfigStore'; N='GameDVR_Enabled'; O=0; D=1 }
    )
}

$F['Widgets'] = @{
    Name   = 'Disable Widgets (News & Interests)'
    ActionLabel = 'APPLY'; RevertLabel = 'REVERT'
    Desc   = 'Disables the Widgets panel keeping a background Edge WebView process (~100-200MB).'
    Rec    = 'Disable to save memory from the Widgets WebView process.'
    Side   = 'Widgets panel and taskbar button disappear.'
    Skip   = 'If you use Widgets for weather, news, stocks, or calendar.'
    Reboot = $false; Impact = 'Low'; Default = 'enable'
    Type   = 'Registry'
    Entries = @(
        @{ P='HKLM:\SOFTWARE\Policies\Microsoft\Dsh'; N='AllowNewsAndInterests'; O=0; D=$null }
    )
}

$F['TipsSuggestions'] = @{
    Name   = 'Disable Tips, Suggestions & Ads'
    ActionLabel = 'APPLY'; RevertLabel = 'REVERT'
    Desc   = 'Disables Windows Tips, app suggestions, and promotional content in Start menu and Settings.'
    Rec    = 'Disable to reduce background content fetching.'
    Side   = 'No more tips notifications. App suggestions in Start menu disappear.'
    Skip   = 'If you find Windows tips useful.'
    Reboot = $false; Impact = 'Low'; Default = 'enable'
    Type   = 'Registry'
    Entries = @(
        @{ P='HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; N='SoftLandingEnabled'; O=0; D=1 },
        @{ P='HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; N='SubscribedContent-338389Enabled'; O=0; D=1 }
    )
}

$F['Hibernation'] = @{
    Name   = 'Disable Hibernation (hiberfil.sys)'
    ActionLabel = 'APPLY'; RevertLabel = 'REVERT'
    Desc   = 'Disables hibernation and deletes hiberfil.sys which equals your RAM size. Also disables Fast Startup.'
    Rec    = 'Disable to reclaim disk space equal to RAM size.'
    Side   = 'Cannot hibernate. Fast Startup disabled, adding ~2-5s to boot.'
    Skip   = 'On laptops where hibernate is used for power saving.'
    Reboot = $false; Impact = 'Medium'; Default = 'skip'
    Type   = 'Custom'
    GetStatus = {
        $val = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' 'HibernateEnabled'
        if ($val -eq 0) { return @{ Optimized = $true; Text = 'APPLIED'; Details = @() } }
        return @{ Optimized = $false; Text = 'DEFAULT'; Details = @() }
    }
    Apply = {
        $bk = @{ HibernateEnabled = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' 'HibernateEnabled' }
        & powercfg /hibernate off 2>$null
        Write-Ok 'APPLY: Disable Hibernation (hiberfil.sys)'
        return $bk
    }
    Revert = {
        param($Backup)
        & powercfg /hibernate on 2>$null
        Write-Ok 'REVERT: Disable Hibernation (hiberfil.sys)'
    }
    Backup = {
        return @{ HibernateEnabled = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' 'HibernateEnabled' }
    }
}

$F['NtfsOptimizations'] = @{
    Name   = 'Optimize NTFS Settings (8.3 Names & Last Access)'
    ActionLabel = 'APPLY'; RevertLabel = 'REVERT'
    Desc   = 'Disables 8.3 short filenames (DOS compat) and last-access timestamp updates. Reduces NTFS metadata overhead.'
    Rec    = 'Disable to improve file I/O performance.'
    Side   = 'Very old 16-bit apps may not find files. Last-accessed timestamps become stale.'
    Skip   = 'If you run legacy 16-bit apps or use backup tools depending on last-access timestamps.'
    Reboot = $true; Impact = 'Low'; Default = 'enable'
    Type   = 'Registry'
    Entries = @(
        @{ P='HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem'; N='NtfsDisable8dot3NameCreation'; O=1; D=0 },
        @{ P='HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem'; N='NtfsDisableLastAccessUpdate'; O=1; D=0 }
    )
}

$F['MemoryCompression'] = @{
    Name   = 'Disable Memory Compression'
    ActionLabel = 'APPLY'; RevertLabel = 'REVERT'
    Desc   = 'Disables Windows memory compression which trades CPU for reduced paging. The compressed store uses RAM itself.'
    Rec    = 'Disable if you have 16GB+ RAM.'
    Side   = 'More aggressive paging to disk under extreme memory pressure.'
    Skip   = 'On systems with 8GB or less RAM.'
    Reboot = $true; Impact = 'Medium'; Default = 'skip'
    Type   = 'Custom'
    GetStatus = {
        try {
            $state = Get-MMAgent -ErrorAction Stop
            if (-not $state.MemoryCompression) { return @{ Optimized = $true; Text = 'APPLIED'; Details = @() } }
            return @{ Optimized = $false; Text = 'DEFAULT'; Details = @() }
        } catch { return @{ Optimized = $null; Text = 'UNKNOWN'; Details = @() } }
    }
    Apply = {
        try {
            $state = Get-MMAgent -ErrorAction Stop
            $bk = @{ MemoryCompression = $state.MemoryCompression }
            Disable-MMAgent -MemoryCompression -ErrorAction Stop
            Write-Ok 'APPLY: Disable Memory Compression'
            return $bk
        } catch { Write-Warn "Could not disable memory compression: $_"; return @{} }
    }
    Revert = {
        param($Backup)
        try { Enable-MMAgent -MemoryCompression -ErrorAction Stop }
        catch { Write-Warn "Could not enable memory compression: $_" }
        Write-Ok 'REVERT: Disable Memory Compression'
    }
    Backup = {
        try { $s = Get-MMAgent -ErrorAction Stop; return @{ MemoryCompression = $s.MemoryCompression } }
        catch { return @{} }
    }
}

$F['NetworkThrottling'] = @{
    Name   = 'Disable Network Throttling'
    ActionLabel = 'APPLY'; RevertLabel = 'REVERT'
    Desc   = 'Disables network throttling and adjusts system responsiveness for multimedia tasks.'
    Rec    = 'Disable for full network throughput.'
    Side   = 'Slightly higher CPU during sustained network transfers. Negligible on modern CPUs.'
    Skip   = 'On ancient hardware where CPU is the bottleneck during network transfers.'
    Reboot = $true; Impact = 'Low'; Default = 'enable'
    Type   = 'Registry'
    Entries = @(
        @{ P='HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'; N='NetworkThrottlingIndex'; O=0xFFFFFFFF; D=10; T='DWord' },
        @{ P='HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'; N='SystemResponsiveness'; O=0; D=20 }
    )
}

$F['PageFileOptimization'] = @{
    Name   = 'Optimize Paging Executive & System Cache'
    ActionLabel = 'APPLY'; RevertLabel = 'REVERT'
    Desc   = 'Keeps kernel/drivers in RAM (DisablePagingExecutive=1) and optimizes for programs over file cache.'
    Rec    = 'Enable on 16GB+ RAM systems.'
    Side   = 'More physical RAM used by kernel. Not ideal for low-RAM systems.'
    Skip   = 'On systems with 8GB or less RAM, or file servers.'
    Reboot = $true; Impact = 'Medium'; Default = 'skip'
    Type   = 'Registry'
    Entries = @(
        @{ P='HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'; N='DisablePagingExecutive'; O=1; D=0 },
        @{ P='HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'; N='LargeSystemCache'; O=0; D=0 }
    )
}

$F['PowerThrottling'] = @{
    Name   = 'Disable Power Throttling'
    ActionLabel = 'APPLY'; RevertLabel = 'REVERT'
    Desc   = 'Disables CPU frequency reduction for background processes.'
    Rec    = 'Disable on AC power so background tasks complete faster and release memory sooner.'
    Side   = 'Slightly higher power consumption. Negligible on desktops.'
    Skip   = 'On laptops running on battery.'
    Reboot = $false; Impact = 'Low'; Default = 'enable'
    Type   = 'Registry'
    Entries = @(
        @{ P='HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling'; N='PowerThrottlingOff'; O=1; D=0 }
    )
}

$script:Categories = @(
    @{ Key='CpuSecurity';    Name='CPU & Virtualization Security';  Features=@('CpuMitigations','VBS') },
    @{ Key='Services';       Name='System Services';                Features=@('XboxServices','TelemetryServices','FaxService','RetailDemo','WMPNetworkSvc','TabletInputService','PhoneSvc','NFCPayments','MapsBroker','NetworkServices','RemoteDesktopClient','WorkFolders','SearchService','SuperfetchService','InsiderService','LocationService','PrintSpooler','ErrorReporting') },
    @{ Key='Browser';        Name='Browser Memory';                 Features=@('BrowserPolicies','BrowserFlags') },
    @{ Key='AICloud';        Name='AI & Cloud Features';            Features=@('WindowsRecall','WindowsCopilot','AICloudContent','AIScheduledTasks') },
    @{ Key='Telemetry';      Name='Telemetry & Privacy';            Features=@('TelemetryLevel','DeliveryOptimization','ActivityHistory','TelemetryTasks') },
    @{ Key='VisualEffects';  Name='UI & Visual Effects';            Features=@('VisualEffectsPreset','WindowTransparency','MenuAnimations') },
    @{ Key='SystemTuning';   Name='System Tuning';                  Features=@('PrefetchRegistry','BackgroundApps','GameBarDVR','Widgets','TipsSuggestions','Hibernation','NtfsOptimizations','MemoryCompression','NetworkThrottling','PageFileOptimization','PowerThrottling') }
)

$script:Selections = @{}
foreach ($fKey in $script:Features.Keys) {
    $script:Selections[$fKey] = 'skip'
}

function Invoke-FullBackup {
    Write-Header 'Creating full backup of all configurable settings'
    $backupData = @{}
    foreach ($fKey in $script:Features.Keys) {
        $feat = $script:Features[$fKey]
        Write-Inf "Backing up: $($feat.Name)"
        try { $backupData[$fKey] = Invoke-FeatureBackup $feat }
        catch { Write-Warn "Could not backup ${fKey}: $_" }
    }
    Save-BackupData $backupData
}

function Invoke-ApplyChanges {
    $currentBackup = Get-BackupData
    $newBackupData = @{}
    if ($currentBackup -and $currentBackup.Features) {
        $currentBackup.Features.PSObject.Properties | ForEach-Object { $newBackupData[$_.Name] = $_.Value }
    }

    $enableCount = 0; $disableCount = 0
    foreach ($fKey in $script:Features.Keys) {
        $sel = $script:Selections[$fKey]
        $feat = $script:Features[$fKey]
        if ($sel -eq 'enable') {
            Write-Header "Applying: $($feat.Name)"
            try {
                $result = Invoke-FeatureApply $feat
                if ($result) { $newBackupData[$fKey] = $result }
                if ($feat.Reboot) { $script:RebootNeeded = $true }
                $enableCount++
            } catch { Write-Err "Failed: ${fKey}: $_" }
        }
        elseif ($sel -eq 'disable') {
            Write-Header "Reverting: $($feat.Name)"
            $bkData = if ($newBackupData.ContainsKey($fKey)) { $newBackupData[$fKey] } else { $null }
            try {
                Invoke-FeatureRevert $feat $bkData
                if ($feat.Reboot) { $script:RebootNeeded = $true }
                $disableCount++
            } catch { Write-Err "Failed to revert ${fKey}: $_" }
        }
    }

    if ($newBackupData.Count -gt 0) { Save-BackupData $newBackupData }

    Write-Host ''
    $bar = [char]0x2550
    Write-Host "  $(C "$($bar.ToString() * 42)" 40 -Bold)"
    Write-Ok "$enableCount feature(s) applied, $disableCount feature(s) reverted."
    if ($script:RebootNeeded) { Write-Warn 'A REBOOT is required for some changes to take effect.' }
    Write-Host ''
}

function Invoke-RevertAll ([string]$BackupPath = $script:BackupFile) {
    $backup = Get-BackupData -Path $BackupPath
    $hasBackup = $null -ne $backup -and $null -ne $backup.Features
    if ($hasBackup) { Write-Ok 'Using saved backup for restore' }
    else { Write-Warn 'No backup found. Reverting with best-effort Windows defaults.' }

    foreach ($fKey in $script:Features.Keys) {
        $feat = $script:Features[$fKey]
        Write-Header "Restoring: $($feat.Name)"
        $bkData = $null
        if ($hasBackup) { try { $bkData = $backup.Features.$fKey } catch {} }
        try { Invoke-FeatureRevert $feat $bkData }
        catch { Write-Warn "Could not revert ${fKey}: $_" }
    }

    if ($hasBackup -and $BackupPath -eq $script:BackupFile -and (Test-Path $script:BackupFile)) {
        Remove-Item $script:BackupFile -Force
        Write-Ok 'Backup file removed'
    }

    Write-Host ''
    $bar = [char]0x2550
    Write-Host "  $(C "$($bar.ToString() * 42)" 40 -Bold)"
    Write-Ok 'All settings reverted.'
    Write-Warn 'A REBOOT is required for some changes to take effect.'
    Write-Host ''
}

function Format-StatusText ([hashtable]$StatusInfo) {
    switch ($StatusInfo.Text) {
        'APPLIED'   { return C 'APPLIED' 40 }
        'DEFAULT'   { return C 'DEFAULT' 245 }
        'PARTIAL'   { return C 'PARTIAL' 214 }
        'N/A'       { return C 'N/A' 239 }
        'UNKNOWN'   { return C 'UNKNOWN' 239 }
        default     { return C $StatusInfo.Text 252 }
    }
}

function Format-SelectionIcon ([string]$Sel, [hashtable]$Feat) {
    $aLabel = if ($Feat.ActionLabel) { $Feat.ActionLabel.ToUpperInvariant().PadRight(10) } else { 'APPLY     ' }
    $rLabel = if ($Feat.RevertLabel) { $Feat.RevertLabel.ToUpperInvariant().PadRight(10) } else { 'REVERT    ' }
    switch ($Sel) {
        'enable'  { return "$(C ([char]0x25A0).ToString() 40) $(C $aLabel 40)" }
        'disable' { return "$(C '<' 214) $(C $rLabel 214)" }
        'skip'    { return "$(C ([char]0x2500).ToString() 245) $(C 'SKIP      ' 245)" }
    }
}

function Get-CategorySelectionSummary ([hashtable]$Cat) {
    $en = 0; $rv = 0; $sk = 0
    foreach ($fKey in $Cat.Features) {
        switch ($script:Selections[$fKey]) { 'enable' { $en++ } 'disable' { $rv++ } 'skip' { $sk++ } }
    }
    $catReboot = $false
    foreach ($fKey in $Cat.Features) {
        if ($script:Selections[$fKey] -ne 'skip' -and $script:Features[$fKey].Reboot) { $catReboot = $true }
    }
    return @{ Enable=$en; Disable=$rv; Skip=$sk; Total=$Cat.Features.Count; Reboot=$catReboot }
}

function Format-CategorySelection ([hashtable]$SelSummary) {
    if ($SelSummary.Enable -eq $SelSummary.Total) { return "$(C ([char]0x25A0).ToString() 40) $(C 'APPLY ALL   ' 40)" }
    if ($SelSummary.Disable -eq $SelSummary.Total) { return "$(C '<' 214) $(C 'REVERT ALL  ' 214)" }
    if ($SelSummary.Skip -eq $SelSummary.Total) { return "$(C ([char]0x2500).ToString() 245) $(C 'SKIP ALL    ' 245)" }
    $parts = @()
    if ($SelSummary.Enable  -gt 0) { $parts += "$(C "$($SelSummary.Enable) apply" 40)" }
    if ($SelSummary.Skip    -gt 0) { $parts += "$(C "$($SelSummary.Skip) skip" 245)" }
    if ($SelSummary.Disable -gt 0) { $parts += "$(C "$($SelSummary.Disable) revert" 214)" }
    return "$(C ([char]0x25C6).ToString() 75) $($parts -join $(C ' | ' 239))"
}

function Get-CategoryStatusSummary ([hashtable]$Cat) {
    $total = $Cat.Features.Count
    $optCount = 0; $defCount = 0; $naCount = 0; $partialCount = 0
    foreach ($fKey in $Cat.Features) {
        $status = Get-FeatureStatus $script:Features[$fKey]
        if ($status.Optimized -eq $true) { $optCount++ }
        elseif ($status.Text -eq 'PARTIAL') { $partialCount++ }
        elseif ($status.Optimized -eq $false) { $defCount++ }
        else { $naCount++ }
    }
    $effective = $total - $naCount
    return @{ Total=$total; Optimized=$optCount; Default=$defCount; Partial=$partialCount; NA=$naCount; Effective=$effective }
}

function Format-CategoryStatus ([hashtable]$StatSummary) {
    if ($StatSummary.Effective -eq 0) { return C 'N/A' 239 }
    $parts = @("$($StatSummary.Optimized) applied")
    if ($StatSummary.Partial -gt 0) { $parts += "$($StatSummary.Partial) partial" }
    $text = ($parts -join ', ') + "/$($StatSummary.Effective)"
    if ($StatSummary.Optimized -eq $StatSummary.Effective) { return C $text 40 }
    if ($StatSummary.Optimized -eq 0 -and $StatSummary.Partial -eq 0) { return C $text 245 }
    return C $text 214
}

function Show-Banner {
    $rebootMark = if ($script:RebootNeeded) { C '  * Reboot pending' 214 } else { '' }
    $bar = [char]0x2550
    $vbar = [char]0x2551
    $tl = [char]0x2554; $tr = [char]0x2557; $bl = [char]0x255A; $br = [char]0x255D
    Write-Host ''
    Write-Host "  $(C "$tl$($bar.ToString() * 62)$tr" 39)"
    Write-Host "  $(C "$vbar" 39)  $(C 'Windows Memory Optimizer' 255 -Bold)                                   $(C "$vbar" 39)"
    Write-Host "  $(C "$vbar" 39)  $(C 'Granular per-feature control | Backup | Export/Import' 245)      $(C "$vbar" 39)"
    Write-Host "  $(C "$bl$($bar.ToString() * 62)$br" 39)"
    if ($rebootMark) { Write-Host "  $rebootMark" }

    $hasBackup = Test-Path $script:BackupFile
    if ($hasBackup) {
        $bkTime = (Get-Item $script:BackupFile).LastWriteTime.ToString('yyyy-MM-dd HH:mm')
        Write-Host "  $(C "Backup: $script:BackupFile ($bkTime)" 239)"
    } else {
        Write-Host "  $(C "Backup dir: $script:BackupDir (no backup yet)" 239)"
    }
    Write-Host ''
}

function Show-Status {
    Show-Banner
    Write-Header 'Current System Status'
    Initialize-StatusCache

    foreach ($cat in $script:Categories) {
        Write-Host ''
        Write-Host "  $(C $cat.Name 255 -Bold)"
        foreach ($fKey in $cat.Features) {
            $feat = $script:Features[$fKey]
            $status = Get-FeatureStatus $feat
            $statusText = Format-StatusText $status
            $rebootMark = if ($feat.Reboot) { C ' *' 214 } else { '' }
            Write-Host "    $statusText  $($feat.Name)$rebootMark"
            if ($status.Text -eq 'PARTIAL' -and $status.Details.Count -gt 0) {
                foreach ($d in $status.Details) {
                    $corner = [char]0x2514
                    $dColor = if ($d.StartsWith('[+]')) { 40 } else { 214 }
                    Write-Host "      $(C "  $corner" 239) $(C $d $dColor)"
                }
            }
        }
    }
    Write-Host ''
}

function Read-KeyPress {
    $key = [System.Console]::ReadKey($true)
    if ($key.Key -eq 'UpArrow')    { return 'Up' }
    if ($key.Key -eq 'DownArrow')  { return 'Down' }
    if ($key.Key -eq 'LeftArrow')  { return 'Left' }
    if ($key.Key -eq 'RightArrow') { return 'Right' }
    if ($key.Key -eq 'Enter')      { return 'Enter' }
    if ($key.Key -eq 'Escape')     { return 'Escape' }
    if ($key.Key -eq 'Backspace')  { return 'Back' }
    $c = $key.KeyChar.ToString()
    if ($key.Modifiers -band [ConsoleModifiers]::Shift) { return "Shift+$($c.ToUpperInvariant())" }
    return $c.ToLowerInvariant()
}

function Wrap-Text ([string]$Text, [int]$MaxWidth = 45) {
    $lines = [System.Collections.ArrayList]::new()
    $words = $Text -split ' '
    $line = ''
    foreach ($w in $words) {
        if (($line + ' ' + $w).Length -gt $MaxWidth -and $line.Length -gt 0) {
            [void]$lines.Add($line)
            $line = $w
        } else {
            $line = if ($line) { "$line $w" } else { $w }
        }
    }
    if ($line) { [void]$lines.Add($line) }
    return $lines
}

function Show-CategoryMenu ([hashtable]$Cat) {
    $features = $Cat.Features
    $selectedIdx = 0
    $vbar = [char]0x2502
    $tl = [char]0x250C; $hbar = [char]0x2500; $bl = [char]0x2514
    $bullet = [char]0x2022
    $pointer = [char]0x25BA

    while ($true) {
        [Console]::Clear()
        $rebootText = if ($script:RebootNeeded) { C '  * Reboot pending' 214 } else { '' }

        if ($script:CacheDirty) {
            Write-Host "  $(C 'Loading...' 239)" -NoNewline
            Initialize-StatusCache
            Write-Host "`r              `r" -NoNewline
        }

        Write-Host ''
        Write-Host "  $(C '<' 75) $(C $Cat.Name 255 -Bold)$rebootText"
        Write-Host "  $(C ($hbar.ToString() * ($Cat.Name.Length + 4)) 239)"

        $leftWidth = 55
        $selFeat = $script:Features[$features[$selectedIdx]]
        $selStatus = Get-FeatureStatus $selFeat

        $leftLines = [System.Collections.ArrayList]::new()
        [void]$leftLines.Add('')
        for ($i = 0; $i -lt $features.Count; $i++) {
            $fKey = $features[$i]
            $feat = $script:Features[$fKey]
            $sel  = $script:Selections[$fKey]
            $status = Get-FeatureStatus $feat
            $selIcon = Format-SelectionIcon $sel $feat
            $reboot = if ($feat.Reboot -and $sel -ne 'skip') { C ' *' 214 } else { '' }

            $ptr = if ($i -eq $selectedIdx) { C $pointer.ToString() 75 } else { ' ' }
            $nameColor = if ($i -eq $selectedIdx) { 255 } else { 252 }
            $statusText = Format-StatusText $status
            [void]$leftLines.Add("  $ptr $selIcon  $(C $feat.Name $nameColor)$reboot")
            [void]$leftLines.Add("         [$statusText]")
        }

        $rightLines = [System.Collections.ArrayList]::new()
        [void]$rightLines.Add("$(C "$tl$hbar" 239) $(C $selFeat.Name 255 -Bold)")
        [void]$rightLines.Add("$(C $vbar.ToString() 239)")
        [void]$rightLines.Add("$(C $vbar.ToString() 239) $(C 'Description' 75)")
        foreach ($line in (Wrap-Text $selFeat.Desc 45)) {
            [void]$rightLines.Add("$(C $vbar.ToString() 239)   $line")
        }

        [void]$rightLines.Add("$(C $vbar.ToString() 239)")
        [void]$rightLines.Add("$(C $vbar.ToString() 239) $(C 'Recommended' 40)")
        foreach ($line in (Wrap-Text $selFeat.Rec 45)) {
            [void]$rightLines.Add("$(C $vbar.ToString() 239)   $line")
        }

        [void]$rightLines.Add("$(C $vbar.ToString() 239)")
        [void]$rightLines.Add("$(C $vbar.ToString() 239) $(C 'Side Effects' 214)")
        foreach ($line in (Wrap-Text $selFeat.Side 45)) {
            [void]$rightLines.Add("$(C $vbar.ToString() 239)   $line")
        }

        [void]$rightLines.Add("$(C $vbar.ToString() 239)")
        [void]$rightLines.Add("$(C $vbar.ToString() 239) $(C "Don't Disable If" 196)")
        foreach ($line in (Wrap-Text $selFeat.Skip 45)) {
            [void]$rightLines.Add("$(C $vbar.ToString() 239)   $line")
        }

        [void]$rightLines.Add("$(C $vbar.ToString() 239)")
        $impColor = switch ($selFeat.Impact) { 'Low' { 40 } 'Medium' { 214 } 'High' { 196 } default { 252 } }
        $rebootText2 = if ($selFeat.Reboot) { C 'Yes' 214 } else { C 'No' 40 }
        $statusBadge = Format-StatusText $selStatus
        [void]$rightLines.Add("$(C $vbar.ToString() 239) $(C 'Impact:' 245) $(C $selFeat.Impact $impColor)  $(C 'Reboot:' 245) $rebootText2")
        [void]$rightLines.Add("$(C $vbar.ToString() 239) $(C 'Status:' 245) $statusBadge")

        if ($selStatus.Text -eq 'PARTIAL' -and $selStatus.Details.Count -gt 0) {
            [void]$rightLines.Add("$(C $vbar.ToString() 239)")
            [void]$rightLines.Add("$(C $vbar.ToString() 239) $(C 'Partial status details:' 214)")
            foreach ($d in $selStatus.Details) {
                $dColor = if ($d.StartsWith('[+]')) { 40 } else { 214 }
                [void]$rightLines.Add("$(C $vbar.ToString() 239)   $(C $d $dColor)")
            }
        }

        [void]$rightLines.Add("$(C $bl.ToString() 239)$(C ($hbar.ToString() * 48) 239)")

        $maxLines = [Math]::Max($leftLines.Count, $rightLines.Count)
        for ($row = 0; $row -lt $maxLines; $row++) {
            $left = if ($row -lt $leftLines.Count) { $leftLines[$row] } else { '' }
            $right = if ($row -lt $rightLines.Count) { $rightLines[$row] } else { '' }
            $leftRaw = $left -replace "$([char]27)\[[0-9;]*m", ''
            $pad = [Math]::Max(1, $leftWidth - $leftRaw.Length)
            Write-Host "$left$(' ' * $pad)$(C $vbar.ToString() 239) $right"
        }

        Write-Host ''
        $up = [char]0x2191; $down = [char]0x2193
        Write-Host "  $(C "$up$down" 75) Navigate   $(C 'E' 75) Apply   $(C 'D' 75) Revert   $(C 'S' 75) Skip   $(C '<-' 75)/$(C 'Esc' 75) Back"
        Write-Host "  $(C 'Shift+E' 75) Apply all   $(C 'Shift+D' 75) Revert all   $(C 'Shift+S' 75) Skip all"
        Write-Host ''

        $key = Read-KeyPress

        switch ($key) {
            'Up'      { $selectedIdx = if ($selectedIdx -gt 0) { $selectedIdx - 1 } else { $features.Count - 1 } }
            'Down'    { $selectedIdx = if ($selectedIdx -lt $features.Count - 1) { $selectedIdx + 1 } else { 0 } }
            'e'       { $script:Selections[$features[$selectedIdx]] = 'enable' }
            'd'       { $script:Selections[$features[$selectedIdx]] = 'disable' }
            's'       { $script:Selections[$features[$selectedIdx]] = 'skip' }
            'Shift+E' { foreach ($fKey in $features) { $script:Selections[$fKey] = 'enable' } }
            'Shift+D' { foreach ($fKey in $features) { $script:Selections[$fKey] = 'disable' } }
            'Shift+S' { foreach ($fKey in $features) { $script:Selections[$fKey] = 'skip' } }
            'Left'    { return }
            'Escape'  { return }
            'Back'    { return }
            default   {}
        }
    }
}

function Show-RestoreBackupMenu {
    while ($true) {
        [Console]::Clear()
        Write-Host ''
        Write-Header 'Restore from Backup'
        Write-Host ''
        Write-Host "  $(C "Default backup location: $script:BackupDir" 239)"
        Write-Host ''

        $backupFiles = [System.Collections.ArrayList]::new()
        $seenPaths = @{}
        foreach ($dir in @($script:BackupDir, (Get-Location).Path)) {
            if (Test-Path $dir) {
                Get-ChildItem -Path $dir -Filter '*.json' -File -ErrorAction SilentlyContinue | ForEach-Object {
                    if (-not $seenPaths.ContainsKey($_.FullName)) {
                        $seenPaths[$_.FullName] = $true
                        [void]$backupFiles.Add($_)
                    }
                }
            }
        }

        if ($backupFiles.Count -gt 0) {
            Write-Host "  $(C 'Available backup files:' 245)"
            Write-Host ''
            for ($i = 0; $i -lt $backupFiles.Count; $i++) {
                $bf = $backupFiles[$i]
                $validation = Test-BackupFile $bf.FullName
                $icon = if ($validation.Valid) { C ([char]0x2713).ToString() 40 } else { C ([char]0x2717).ToString() 196 }
                $isDefault = if ($bf.FullName -eq $script:BackupFile) { C ' (default)' 75 } else { '' }
                Write-Host "  $(C "[$($i+1)]" 75) $icon $($bf.Name)$isDefault"
                Write-Host "       $(C $bf.DirectoryName 239)"
                Write-Host "       $(C $validation.Reason 239)"
                Write-Host ''
            }
        } else {
            Write-Warn 'No backup files found in default or current directory'
            Write-Host ''
        }

        Write-Host "  $(C '[M]' 75) Enter path manually"
        Write-Host "  $(C '[B]' 75) Back"
        Write-Host ''
        $choice = Read-Host '  Select'
        $c = $choice.Trim()

        if ($c -match '^\d+$') {
            $idx = [int]$c - 1
            if ($idx -ge 0 -and $idx -lt $backupFiles.Count) {
                $path = $backupFiles[$idx].FullName
                $validation = Test-BackupFile $path
                if ($validation.Valid) {
                    $confirm = Read-Host "  Restore from $($backupFiles[$idx].Name)? [Y/N]"
                    if ($confirm -match '^[Yy]') {
                        Invoke-RevertAll -BackupPath $path
                        Invalidate-StatusCache
                        Read-Host '  Press Enter to continue'
                        return
                    }
                } else {
                    Write-Err "Invalid backup: $($validation.Reason)"
                    Read-Host '  Press Enter to continue'
                }
            }
        }
        elseif ($c -match '^[Mm]$') {
            $manualPath = Read-Host '  Enter full path to backup file'
            if ($manualPath) {
                $validation = Test-BackupFile $manualPath.Trim()
                if ($validation.Valid) {
                    Write-Ok $validation.Reason
                    $confirm = Read-Host '  Restore from this file? [Y/N]'
                    if ($confirm -match '^[Yy]') {
                        Invoke-RevertAll -BackupPath $manualPath.Trim()
                        Invalidate-StatusCache
                        Read-Host '  Press Enter to continue'
                        return
                    }
                } else {
                    Write-Err "Invalid backup: $($validation.Reason)"
                    Read-Host '  Press Enter to continue'
                }
            }
        }
        elseif ($c -match '^[Bb]$') { return }
        else { Write-Warn "Invalid: $c" }
    }
}

function Show-ExportImportMenu {
    while ($true) {
        [Console]::Clear()
        Write-Host ''
        Write-Header 'Export / Import Configuration'
        Write-Host ''
        Write-Host "  $(C 'Export saves your current selections (enable/disable/skip) to a JSON file.' 245)"
        Write-Host "  $(C 'Import loads selections from a previously exported file.' 245)"
        Write-Host ''
        Write-Host "  $(C '[E]' 75) Export current selections"
        Write-Host "  $(C '[I]' 75) Import selections from file"
        Write-Host "  $(C '[B]' 75) Back"
        Write-Host ''
        $choice = Read-Host '  Select'
        $c = $choice.Trim()

        switch -Regex ($c) {
            '^[Ee]$' {
                $defaultPath = Join-Path $script:BackupDir "config-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
                Write-Host "  $(C "Default: $defaultPath" 239)"
                $path = Read-Host '  Export path (Enter for default)'
                if (-not $path) { $path = $defaultPath }
                try {
                    $dir = Split-Path $path -Parent
                    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
                    Export-SelectionConfig $path
                } catch { Write-Err "Export failed: $_" }
                Read-Host '  Press Enter to continue'
            }
            '^[Ii]$' {
                $configFiles = [System.Collections.ArrayList]::new()
                $seenPaths = @{}
                foreach ($dir in @($script:BackupDir, (Get-Location).Path)) {
                    if (Test-Path $dir) {
                        Get-ChildItem -Path $dir -Filter 'config-*.json' -File -ErrorAction SilentlyContinue | ForEach-Object {
                            if (-not $seenPaths.ContainsKey($_.FullName)) {
                                $seenPaths[$_.FullName] = $true
                                [void]$configFiles.Add($_)
                            }
                        }
                    }
                }
                if ($configFiles.Count -gt 0) {
                    Write-Host ''
                    for ($i = 0; $i -lt $configFiles.Count; $i++) {
                        Write-Host "  $(C "[$($i+1)]" 75) $($configFiles[$i].Name)"
                        Write-Host "       $(C $configFiles[$i].DirectoryName 239)"
                    }
                    Write-Host "  $(C '[M]' 75) Enter path manually"
                    Write-Host ''
                    $sel = Read-Host '  Select'
                    if ($sel -match '^\d+$') {
                        $idx = [int]$sel - 1
                        if ($idx -ge 0 -and $idx -lt $configFiles.Count) {
                            Import-SelectionConfig $configFiles[$idx].FullName
                        }
                    } elseif ($sel -match '^[Mm]$') {
                        $manualPath = Read-Host '  Enter full path'
                        if ($manualPath) { Import-SelectionConfig $manualPath.Trim() }
                    }
                } else {
                    $manualPath = Read-Host '  No config files found. Enter path manually'
                    if ($manualPath) { Import-SelectionConfig $manualPath.Trim() }
                }
                Read-Host '  Press Enter to continue'
            }
            '^[Bb]$' { return }
            default { Write-Warn "Invalid: $c" }
        }
    }
}

function Show-Summary {
    Write-Host ''
    Write-Header 'CHANGE PLAN'

    $enableList = @(); $disableList = @(); $skipList = @()
    foreach ($fKey in $script:Features.Keys) {
        $feat = $script:Features[$fKey]
        switch ($script:Selections[$fKey]) {
            'enable'  { $enableList  += $feat }
            'disable' { $disableList += $feat }
            'skip'    { $skipList    += $feat }
        }
    }

    $anyReboot = $false

    if ($enableList.Count -gt 0) {
        Write-Host ''
        Write-Host "  $(C 'APPLY:' 40 -Bold)"
        foreach ($f in $enableList) {
            $rb = if ($f.Reboot) { $anyReboot = $true; C ' *' 214 } else { '' }
            Write-Host "    $(C ([char]0x25A0).ToString() 40) $($f.Name)$rb"
        }
    }

    if ($disableList.Count -gt 0) {
        Write-Host ''
        Write-Host "  $(C 'REVERT:' 214 -Bold)"
        foreach ($f in $disableList) {
            $rb = if ($f.Reboot) { $anyReboot = $true; C ' *' 214 } else { '' }
            Write-Host "    $(C '<' 214) $($f.Name)$rb"
        }
    }

    if ($skipList.Count -gt 0) {
        Write-Host ''
        Write-Host "  $(C 'UNCHANGED:' 245) $(C "$($skipList.Count) feature(s)" 239)"
    }

    Write-Host ''
    if ($anyReboot) {
        Write-Host "  $(C '* REBOOT REQUIRED' 214 -Bold)"
    } else {
        Write-Host "  $(C '* Reboot:' 245) Not required"
    }
    Write-Host ''

    $totalChanges = $enableList.Count + $disableList.Count
    if ($totalChanges -eq 0) {
        Write-Warn 'No changes selected.'
        return $false
    }

    $confirm = Read-Host "  Apply $totalChanges change(s)? [Y/N]"
    return ($confirm.Trim() -match '^[Yy]')
}

function Show-MainMenu {
    $selectedIdx = 0

    while ($true) {
        [Console]::Clear()
        Show-Banner

        if ($script:CacheDirty) {
            Write-Host "  $(C 'Loading status...' 239)" -NoNewline
            Initialize-StatusCache
            Write-Host "`r                          `r" -NoNewline
        }

        $pointer = [char]0x25BA

        Write-Host "  $(C 'Categories:' 245)"
        Write-Host ''

        for ($i = 0; $i -lt $script:Categories.Count; $i++) {
            $cat = $script:Categories[$i]
            $statSummary = Get-CategoryStatusSummary $cat
            $selSummary  = Get-CategorySelectionSummary $cat

            $selText  = Format-CategorySelection $selSummary
            $statText = Format-CategoryStatus $statSummary
            $reboot   = if ($selSummary.Reboot) { C ' *' 214 } else { '' }

            $ptr = if ($i -eq $selectedIdx) { C $pointer.ToString() 75 } else { ' ' }
            $nameColor = if ($i -eq $selectedIdx) { 255 } else { 252 }
            Write-Host "  $ptr $selText   $(C $cat.Name $nameColor)$reboot"
            Write-Host "       $statText"
        }

        Write-Host ''
        $up = [char]0x2191; $down = [char]0x2193
        Write-Host "  $(C "$up$down" 75) Navigate   $(C 'E' 75) Apply   $(C 'D' 75) Revert   $(C 'S' 75) Skip   $(C 'Enter' 75)/$(C '->' 75) Configure"
        Write-Host "  $(C 'Shift+E' 75) Apply all   $(C 'Shift+D' 75) Revert all   $(C 'Shift+S' 75) Skip all"
        Write-Host "  $(C 'A' 75) Apply changes   $(C 'B' 75) Backup   $(C 'R' 75) Restore   $(C 'X' 75) Export/Import   $(C 'I' 75) Status   $(C 'Q' 75) Quit"
        $sq = [char]0x25A0; $tri = '<'; $dash = [char]0x2500
        Write-Host "  $(C 'Legend:' 239) $(C $sq.ToString() 40) $(C 'Apply' 239)  $(C $tri.ToString() 214) $(C 'Revert' 239)  $(C $dash.ToString() 245) $(C 'Skip' 239)  $(C '*' 214) $(C 'Reboot' 239)"
        Write-Host ''

        $key = Read-KeyPress

        switch ($key) {
            'Up'      { $selectedIdx = if ($selectedIdx -gt 0) { $selectedIdx - 1 } else { $script:Categories.Count - 1 } }
            'Down'    { $selectedIdx = if ($selectedIdx -lt $script:Categories.Count - 1) { $selectedIdx + 1 } else { 0 } }
            'Right'   { Show-CategoryMenu $script:Categories[$selectedIdx] }
            'Enter'   { Show-CategoryMenu $script:Categories[$selectedIdx] }
            'e'       { $cat = $script:Categories[$selectedIdx]; foreach ($fKey in $cat.Features) { $script:Selections[$fKey] = 'enable' } }
            'd'       { $cat = $script:Categories[$selectedIdx]; foreach ($fKey in $cat.Features) { $script:Selections[$fKey] = 'disable' } }
            's'       { $cat = $script:Categories[$selectedIdx]; foreach ($fKey in $cat.Features) { $script:Selections[$fKey] = 'skip' } }
            'Shift+E' { foreach ($fKey in $script:Features.Keys) { $script:Selections[$fKey] = 'enable' } }
            'Shift+D' { foreach ($fKey in $script:Features.Keys) { $script:Selections[$fKey] = 'disable' } }
            'Shift+S' { foreach ($fKey in $script:Features.Keys) { $script:Selections[$fKey] = 'skip' } }
            'a'       { if (Show-Summary) { Invoke-ApplyChanges; Invalidate-StatusCache; Read-Host '  Press Enter to continue' } }
            'Shift+A' { if (Show-Summary) { Invoke-ApplyChanges; Invalidate-StatusCache; Read-Host '  Press Enter to continue' } }
            'b'       { Invoke-FullBackup; Invalidate-StatusCache; Read-Host '  Press Enter to continue' }
            'Shift+B' { Invoke-FullBackup; Invalidate-StatusCache; Read-Host '  Press Enter to continue' }
            'x'       { Show-ExportImportMenu }
            'Shift+X' { Show-ExportImportMenu }
            'r'       { Show-RestoreBackupMenu }
            'Shift+R' { Show-RestoreBackupMenu }
            'i'       { [Console]::Clear(); Show-Status; Read-Host '  Press Enter to continue' }
            'Shift+I' { [Console]::Clear(); Show-Status; Read-Host '  Press Enter to continue' }
            'q'       { Write-Host '  Bye!'; return }
            'Shift+Q' { Write-Host '  Bye!'; return }
            'Escape'  { Write-Host '  Bye!'; return }
            default   {}
        }
    }
}

if ($Status) {
    Show-Status
    exit 0
}

if ($BackupOnly) {
    Show-Banner
    Invoke-FullBackup
    exit 0
}

if ($Revert) {
    Show-Banner
    Invoke-RevertAll
    exit 0
}

if ($ExportConfig) {
    Show-Banner
    Export-SelectionConfig $ExportConfig
    exit 0
}

if ($ImportConfig) {
    Show-Banner
    if (Import-SelectionConfig $ImportConfig) {
        if (Show-Summary) { Invoke-ApplyChanges }
    }
    exit 0
}

if ($NonInteractive) {
    Show-Banner
    Write-Ok 'Non-interactive mode: applying all default selections'
    Invoke-ApplyChanges
    exit 0
}

Show-MainMenu
