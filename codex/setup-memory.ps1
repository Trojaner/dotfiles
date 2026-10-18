$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'Use codex/setup-memory.sh on Linux or macOS.' }
$repoDir = Split-Path -Parent $PSScriptRoot
$codexDir = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME '.codex' }
$runtimeDir = Join-Path $codexDir 'memory-maintenance'
New-Item -Path $runtimeDir -ItemType Directory -Force | Out-Null
$uv = Get-Command uv -ErrorAction SilentlyContinue
if (-not $uv) {
    & winget install --exact --id astral-sh.uv --scope user --accept-source-agreements --accept-package-agreements
    if ($LASTEXITCODE -ne 0) { throw 'Could not install uv.' }
    $env:PATH = [Environment]::GetEnvironmentVariable('Path', 'User') + ';' + [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $uv = Get-Command uv -ErrorAction Stop
}
$python = Join-Path $runtimeDir 'venv\Scripts\python.exe'
if (-not (Test-Path -LiteralPath $python)) {
    & $uv.Source venv --python 3.12 (Join-Path $runtimeDir 'venv')
    if ($LASTEXITCODE -ne 0) { throw 'Could not create the memory maintenance Python environment.' }
}
& $python (Join-Path $PSScriptRoot 'setup-memory.py') --codex-home $codexDir
if ($LASTEXITCODE -ne 0) { throw 'Memory maintenance installation failed.' }
