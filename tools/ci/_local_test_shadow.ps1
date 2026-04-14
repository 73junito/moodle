Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Prepare test diff
$diff = [ordered]@{ regressions = @(1,2) }
($diff | ConvertTo-Json -Depth 5) | Set-Content -Path (Join-Path (Get-Location).Path 'manifest-run-diff.json') -Encoding UTF8 -Force

# Set environment to mimic workflow
$env:DIFF_MODE = 'gate'
$env:CI_MODE_ENFORCEMENT = 'shadow'

# Dot-source resolver helper
. "$(Join-Path (Get-Location).Path 'tools\ci\Get-CIMode.ps1')"
$cm = Get-CIMode
Write-Host "[TEST] resolved_mode=$($cm.Label) (source=$($cm.Source))"

# Evaluate diff and shadow logic
$d = Get-Content 'manifest-run-diff.json' -Raw | ConvertFrom-Json -ErrorAction Stop
$regs = 0
if ($d -and $d.regressions) { $regs = [int]$d.regressions.Count }

$enforcement = if ($env:CI_MODE_ENFORCEMENT) { $env:CI_MODE_ENFORCEMENT.Trim().ToLower() } else { $null }
$isShadow = ($enforcement -eq 'shadow')
$wouldFail = ($env:DIFF_MODE -eq 'gate' -and $regs -gt 0)
Write-Host "[diff] shadow_mode=$isShadow regressions=$regs would_fail=$wouldFail"
if ($isShadow -and $wouldFail) { Write-Host "::warning::Diff gate would fail ($regs regressions)" }

Write-Host 'Local shadow enforcement test completed (exit 0)'
exit 0
