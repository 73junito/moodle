param(
    [string]$Version = 'v0.20.4'
)

Set-StrictMode -Off

function Log { param($m) $ts = (Get-Date).ToString('s'); Write-Host "[$ts] $m" }

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$setup = Join-Path $scriptDir 'ollama_autodownload_setup.ps1'

if (-not (Test-Path $setup)) {
    Write-Error "Missing setup script: $setup"
    exit 1
}

Log "Invoking ollama setup (ci) version=$Version"
& pwsh -NoProfile -File $setup -Version $Version -RunInstaller
exit $LASTEXITCODE
