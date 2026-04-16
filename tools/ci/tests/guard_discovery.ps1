<#
Lightweight guard to ensure discovery does not return artifact files.

Exits with code 0 on success, 1 on failure and prints offending paths.
#>
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "[guard] Running discover-manifests.ps1 to validate discovery exclusions"

# Run discovery explicitly to a run-scoped folder (fall back to legacy location for older tooling)
$repoRoot = (Get-Item $PSScriptRoot).FullName
for ($i = 0; $i -lt 3; $i++) { $repoRoot = Split-Path -Parent $repoRoot }
$runId = $env:GITHUB_RUN_ID
if (-not $runId) { $runId = 'local' }
$outDir = Join-Path $repoRoot '.github/artifacts'

& "$PSScriptRoot/../discover-manifests.ps1" -OutDir $outDir -RunId $runId

# Prefer run-scoped discovery output, but allow legacy single-file path for compatibility
$runScopedDir = Join-Path $outDir $runId
$runScopedFile = Join-Path $runScopedDir 'discovery-manifests.json'
$legacyFile = Join-Path $outDir 'discovery-manifests.json'
$candidates = @($runScopedFile, $legacyFile)

$discoveryFile = $null
foreach ($c in $candidates) { if (Test-Path $c) { $discoveryFile = $c; break } }
if (-not $discoveryFile) {
    Write-Error "Discovery output not found (tried run-scoped and legacy locations): $($candidates -join ', ')"
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
