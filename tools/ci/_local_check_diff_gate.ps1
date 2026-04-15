$mode = 'gate'
if (-not (Test-Path 'manifest-run-diff.json')) { Write-Host 'No diff produced; skipping diff gate'; exit 0 }
$d = Get-Content 'manifest-run-diff.json' -Raw | ConvertFrom-Json
$regs = 0
if ($d -and $d.regressions) { $regs = [int]$d.regressions.Count }
Write-Host "DIFF_MODE=$mode"
Write-Host "Diff regressions: $regs"
if ($mode -eq 'gate' -and $regs -gt 0) { Write-Host 'Would fail (regressions found)'; exit 1 } else { Write-Host 'Would pass'; exit 0 }