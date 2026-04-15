param(
  [string]$SummaryPath = 'manifest-run-summary.json',
  [string]$DiffPath = 'manifest-run-diff.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Read-Json($p) { try { if (Test-Path $p) { return Get-Content $p -Raw | ConvertFrom-Json -ErrorAction Stop } } catch { } return $null }

$summary = Read-Json $SummaryPath
$diff = Read-Json $DiffPath

if (-not $summary) { Write-Error "Contract failure: summary missing or invalid ($SummaryPath)"; exit 2 }

# Basic checks
if (-not $summary.PSObject.Properties.Name -contains 'passed' -or -not $summary.PSObject.Properties.Name -contains 'failed') {
  Write-Error 'Contract failure: summary missing required "passed"/"failed" fields'
  exit 2
}

# Ensure no empty runId in diff newRuns
try {
  if ($diff -and $diff.newRuns) {
    foreach ($r in @($diff.newRuns)) {
      if ($null -eq $r.runId -or $r.runId.ToString().Trim() -eq '') { Write-Error "Contract failure: empty runId in diff newRuns"; exit 2 }
    }
  }
} catch { Write-Error "Contract failure reading diff: $($_.Exception.Message)"; exit 2 }

Write-Host 'CI contract: ok'
exit 0