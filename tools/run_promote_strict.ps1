Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'AppLocker.PolicyCompiler.psm1') -Force -ErrorAction Stop
$cand = Get-ChildItem -Path (Join-Path $PSScriptRoot 'runs') -Filter 'self_heal_candidate_*.xml' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $cand) { Write-Error 'No candidate found in runs/'; exit 2 }
Write-Output "Using candidate: $($cand.FullName)"
& (Join-Path $PSScriptRoot 'promote_policy.ps1') -CandidatePath $cand.FullName -SimulationReport (Join-Path $PSScriptRoot '..\fixtures\positive_sim.json') -DryRun -StrictParsing -Verbose
