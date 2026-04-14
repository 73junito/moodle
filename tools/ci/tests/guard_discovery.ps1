<#
Lightweight guard to ensure discovery does not return artifact files.

Exits with code 0 on success, 1 on failure and prints offending paths.
#>
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "[guard] Running discover-manifests.ps1 to validate discovery exclusions"

# Ensure the discovery script runs and writes its artifact
& "$PSScriptRoot/../discover-manifests.ps1"

$repoRoot = (Get-Item $PSScriptRoot).FullName
for ($i = 0; $i -lt 3; $i++) { $repoRoot = Split-Path -Parent $repoRoot }
$discoveryFile = Join-Path $repoRoot '.github/artifacts/discovery-manifests.json'
if (-not (Test-Path $discoveryFile)) {
    Write-Error "Discovery output not found: $discoveryFile"
    exit 1
}

$json = Get-Content $discoveryFile -Raw | ConvertFrom-Json
if ($null -eq $json) { $json = @() }

$offenders = @()
foreach ($item in $json) {
    $p = $item.path
    $name = [System.IO.Path]::GetFileName($p)
    if ($name -like 'validation-report*' -or $name -like 'metadata*' -or $p -like '*\.github\artifacts\*') {
        $offenders += $p
    }
}

if ($offenders.Count -gt 0) {
    Write-Host "::error::discover-manifests returned artifact-like files:" 
    foreach ($o in $offenders) { Write-Host " - $o" }
    exit 1
}

Write-Host "[guard] discover-manifests OK: no artifact files returned"
exit 0
