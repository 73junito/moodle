Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'AppLocker.PolicyCompiler.psm1') -Force -ErrorAction Stop
$runs = Join-Path $PSScriptRoot 'runs'
$cand = Get-ChildItem -Path $runs -Filter 'self_heal_candidate_*.xml' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $cand) { Write-Error 'No candidate found'; exit 1 }
Write-Output "Candidate: $($cand.FullName)"
$ir = Parse-AppLockerPolicyXml -Path $cand.FullName
$baseline = $ir.Rules | Where-Object { ($_.Name -and ($_.Name -match 'baseline')) -or ($_.Description -and ($_.Description -match 'baseline')) } | Select-Object -First 1
$auto = $ir.Rules | Where-Object { ($_.Name -and ($_.Name -match 'auto-synth')) -or ($_.Description -and ($_.Description -match 'auto-synth')) } | Select-Object -First 1
Write-Output '--- BASELINE RULE OBJECT ---'
if ($baseline) { $baseline | ConvertTo-Json -Depth 8 | Write-Output } else { Write-Output '<none>' }
Write-Output '--- AUTOSYNTH RULE OBJECT ---'
if ($auto) { $auto | ConvertTo-Json -Depth 8 | Write-Output } else { Write-Output '<none>' }
