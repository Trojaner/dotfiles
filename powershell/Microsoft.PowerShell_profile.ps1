[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

# Only run the interactive setup below in a real interactive terminal.
# Cheap guard: no runtime C# compilation. The old Add-Type VT check cost ~300ms on every launch.
$argv = [Environment]::GetCommandLineArgs()
if ($argv.Contains('-NonInteractive') -or $argv.Contains('-NoProfile') -or $argv.Contains('-ExecutionPolicy') -or
    [System.Console]::IsOutputRedirected -or -not $Host.UI.SupportsVirtualTerminal) {
    return
}

# ---------------------------------------------------------------------------
# oh-my-posh: cache the generated init script to skip the ~130ms exe spawn on
# every launch. `oh-my-posh init` only emits a 2-line shim that sets a session
# id and dot-sources a generated init.<hash>.ps1; we reproduce that ourselves
# and only re-run the exe when oh-my-posh or the theme file changes.
# ---------------------------------------------------------------------------
$__ompTheme = "$HOME\Documents\PowerShell\posh-theme.json"
$__ompCache = "$HOME\Documents\PowerShell\.omp-init.cache"
$__ompExe   = (Get-Command oh-my-posh -ErrorAction SilentlyContinue).Source

if ($__ompExe -and (Test-Path $__ompTheme)) {
    $env:POSH_THEME = $__ompTheme
    # Invalidation key from file timestamps only (no exe spawn on the fast path).
    $__ompKey = '{0}|{1}' -f (Get-Item $__ompExe).LastWriteTimeUtc.Ticks, (Get-Item $__ompTheme).LastWriteTimeUtc.Ticks

    $__ompInit = $null
    if (Test-Path $__ompCache) {
        $__parts = (Get-Content $__ompCache -Raw) -split "`n", 2
        if ($__parts.Count -eq 2 -and $__parts[0].Trim() -eq $__ompKey -and (Test-Path $__parts[1].Trim())) {
            $__ompInit = $__parts[1].Trim()
        }
    }

    if ($__ompInit) {
        # Fast path: reproduce the init shim without spawning oh-my-posh.exe.
        $env:POSH_SESSION_ID = [guid]::NewGuid().Guid
        & $__ompInit
    } else {
        # Slow path: run the supported init, then cache the generated init.ps1 path.
        $__wrapper = oh-my-posh init pwsh --config $__ompTheme
        $__wrapper | Invoke-Expression
        if ($__wrapper -match "&\s*'([^']+)'") {
            Set-Content -Path $__ompCache -Value ('{0}{1}{2}' -f $__ompKey, "`n", $matches[1]) -NoNewline -Encoding UTF8
        }
    }
} elseif ($__ompExe) {
    oh-my-posh init pwsh --config $__ompTheme | Invoke-Expression
}

if (Test-Path alias:Curl) { 
    Remove-Item alias:Curl 
}

if (Test-Path alias:WGet) { 
    Remove-Item alias:WGet 
}

# PSReadLine drives the line editor, so it must be present before the first keystroke.
Import-Module -Name PSReadLine

# # Invoke-Expression "$(direnv hook pwsh)"

$PSDefaultParameterValues["Out-File:Encoding"] = "utf8"
$PSReadLineOptions = @{
    EditMode                      = 'Windows'
    PredictionSource              = 'History'  # was HistoryAndPlugin; CompletionPredictor plugin removed
    PredictionViewStyle           = 'ListView' 
    HistorySearchCursorMovesToEnd = $true
}

Set-PSReadLineOption @PSReadLineOptions

Set-PSReadLineKeyHandler -Chord 'Ctrl+LeftArrow' -Function BackwardWord
Set-PSReadLineKeyHandler -Chord 'Ctrl+RightArrow' -Function ForwardWord
Set-PSReadLineKeyHandler -Chord 'Ctrl+z' -Function Undo
Set-PSReadLineKeyHandler -Chord 'Ctrl+y' -Function Redo
Set-PSReadlineKeyHandler -Key Tab -Function MenuComplete
Set-PSReadlineKeyHandler -Key UpArrow -Function HistorySearchBackward
Set-PSReadlineKeyHandler -Key DownArrow -Function HistorySearchForward

# ---------------------------------------------------------------------------
# Deferred load: these are not needed for the first prompt or first keystroke,
# so we import them asynchronously right after the prompt paints. This keeps
# time-to-prompt low while still loading everything a moment later.
#   - Terminal-Icons                  : only affects Get-ChildItem output
#   - Microsoft.WinGet.Client         : winget PowerShell cmdlets, rarely used immediately
#   - Microsoft.WinGet.CommandNotFound: suggests `winget install` for unknown commands
#   - VS Code shell integration       : spawns code-insiders (~200ms) to locate its script
# The shared-runspace trick runs the work in the *global* session state, so the
# modules land in this interactive session (a plain background job would not).
# ---------------------------------------------------------------------------
$Deferred = {
    foreach ($m in 'Terminal-Icons', 'Microsoft.WinGet.Client', 'Microsoft.WinGet.CommandNotFound') {
        try { Import-Module -Name $m -ErrorAction Stop } catch { Write-Warning "Deferred import of $m failed: $_" }
    }
    if ($env:TERM_PROGRAM -eq 'vscode' -and (Get-Command code-insiders -ErrorAction SilentlyContinue)) {
        try { . "$(code-insiders --locate-shell-integration-path pwsh)" } catch { }
    }
}

$GlobalState = [psmoduleinfo]::new($false)
$GlobalState.SessionState = $ExecutionContext.SessionState

$__deferredRunspace = [runspacefactory]::CreateRunspace($Host)
$__deferredRunspace.Open()
$__deferredRunspace.SessionStateProxy.PSVariable.Set('GlobalState', $GlobalState)
$__deferredRunspace.SessionStateProxy.PSVariable.Set('Deferred', $Deferred)

$__deferredWorker = [powershell]::Create()
$__deferredWorker.Runspace = $__deferredRunspace
$null = $__deferredWorker.AddScript({
    Start-Sleep -Milliseconds 50   # let the first prompt render before importing
    . $GlobalState { . $Deferred }
}).BeginInvoke()