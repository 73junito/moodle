<#
.SYNOPSIS
    Migration helper: convert a simple whitelist JSON into manifest stubs.

.DESCRIPTION
    Reads a whitelist JSON (array of entries or an object with keys) and
    emits minimal manifest.json stubs into an output directory for further
    editing. This is intentionally conservative (preview mode) and supports
    `-Apply` to actually write files.

.EXAMPLE
    pwsh -NoProfile -File tools/ci/migrate-whitelist-to-manifests.ps1 -WhitelistPath tools/runs/whitelist.json -OutputDir tools/ci/migrations -WhatIf
#>

[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [Parameter(Mandatory=$false)]
    [string]$WhitelistPath = 'tools/runs/whitelist.json',

    [Parameter(Mandatory=$false)]
    [string]$OutputDir = 'tools/ci/migrations',

    [switch]$Apply,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "Migration helper starting. Whitelist: $WhitelistPath → OutputDir: $OutputDir"

if (-not (Test-Path $WhitelistPath)) {
    Write-Host "No whitelist file found at: $WhitelistPath" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Provide one using:"
    Write-Host "  -WhitelistPath .\\path\\to\\whitelist.json"
    Write-Host ""
    exit 1
}

$json = Get-Content $WhitelistPath -Raw | ConvertFrom-Json

# Determine entries: accept array of strings or object/dictionary
$entries = @()
if ($json -is [System.Array]) {
    $entries = $json
} else {
    try {
        foreach ($k in $json.PSObject.Properties.Name) { $entries += $k }
    } catch {
        Write-Host "Unable to interpret whitelist JSON structure" -ForegroundColor Red
        exit 1
    }
}

if ($entries.Count -eq 0) {
    Write-Host "No entries to migrate" -ForegroundColor Yellow
    exit 0
}

if (-not (Test-Path $OutputDir)) {
    if ($Apply) { New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null } else { Write-Host "(Preview) Would create directory: $OutputDir" }
}

 $created = @()
 $skipped = @()
 $updated = @()
foreach ($e in $entries) {
    # Use a safe runId derived from the entry name
    $safe = $e -replace '[^A-Za-z0-9_.-]','-'
    # stable short hash suffix for uniqueness
    $bytes = [System.Text.Encoding]::UTF8.GetBytes([string]$e)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $hash = [System.BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-','').ToLower()
    $short = $hash.Substring(0,6)
    $runId = "migrate-$safe-$short"
    $manifest = [ordered]@{
        source = $e
        version = '1.0'
        runId = $runId
        timestamp = (Get-Date).ToString('o')
        inputs = @()
        outputs = @()
        logging = @{ inlineLogLimitKB = 64 }
    }

    $outPath = Join-Path $OutputDir "$runId.json"
    $body = $manifest | ConvertTo-Json -Depth 6

    if ($Apply) {
        # Idempotency: skip if already present with identical content
        if (Test-Path $outPath) {
            $existing = Get-Content -Raw -Encoding UTF8 -Path $outPath
            if ($existing -eq $body) {
                $skipped += $outPath
                Write-Host "Skipped (unchanged): $outPath"
                continue
            } else {
                if ($Force -or $PSCmdlet.ShouldProcess($outPath, 'Overwrite manifest')) {
                    $body | Set-Content -Path $outPath -Encoding UTF8
                    $updated += $outPath
                    Write-Host "Updated: $outPath"
                } else {
                    Write-Host "Would update (needs -Force): $outPath"
                    $skipped += $outPath
                }
            }
        } else {
            if ($PSCmdlet.ShouldProcess($outPath, 'Write manifest')) {
                # Ensure directory exists
                $dir = Split-Path -Parent $outPath
                if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
                $body | Set-Content -Path $outPath -Encoding UTF8
                $created += $outPath
                Write-Host "Created: $outPath"
            }
        }
    } else {
        Write-Host "(Preview) Would write: $outPath"
    }
}

Write-Host "Migration complete. Entries found: $($entries.Count)"
if ($Apply) {
    Write-Host "Created: $($created.Count)"
    foreach ($c in $created) { Write-Host " - $c" }
    Write-Host "Updated: $($updated.Count)"
    foreach ($u in $updated) { Write-Host " - $u" }
    Write-Host "Skipped (unchanged): $($skipped.Count)"
    foreach ($s in $skipped) { Write-Host " - $s" }
} else {
    Write-Host "(Preview) Would generate: $($entries.Count) manifests under $OutputDir"
}

exit 0
