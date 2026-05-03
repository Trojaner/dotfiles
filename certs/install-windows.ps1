# Install the Enes Sadık Özbek Root CA into the Windows local machine
# Trusted Root Certification Authorities store. Must be run as Administrator.
#
# Usage (from an elevated PowerShell prompt):
#   powershell -ExecutionPolicy Bypass -File .\install-windows.ps1

[CmdletBinding()]
param(
    [string]$CertFile = (Join-Path $PSScriptRoot 'root-ca.crt')
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $CertFile)) {
    throw "Certificate not found: $CertFile"
}

# Require elevation — installing into LocalMachine\Root needs admin rights.
$identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'This script must be run as Administrator.'
}

Write-Host "Importing $CertFile into Cert:\LocalMachine\Root ..."
$cert = Import-Certificate -FilePath $CertFile -CertStoreLocation Cert:\LocalMachine\Root

Write-Host ''
Write-Host 'Installed. Details:'
Write-Host "  Subject:    $($cert.Subject)"
Write-Host "  Issuer:     $($cert.Issuer)"
Write-Host "  Thumbprint: $($cert.Thumbprint)"
Write-Host "  NotAfter:   $($cert.NotAfter)"
Write-Host ''
Write-Host 'The certificate is now trusted for SSL, code signing, drivers, and other purposes machine-wide.'
