<#
Simple wrapper to run self_heal -> promote pipeline once.

Usage:
  pwsh -NoProfile -File .\tools\run_self_heal_pipeline.ps1 -PolicyXml .\tools\runs\...\enforce.xml -SimulationReport .\tools\runs\...\simulation.txt
#>

param(
    [Parameter(Mandatory=$true)] [string]$PolicyXml,
    [Parameter(Mandatory=$true)] [string]$SimulationReport,
    [switch]$CIAdvance,
    [switch]$StrictParsing
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Output "Run self_heal with PolicyXml=$PolicyXml SimulationReport=$SimulationReport"

# 1. Generate candidate
& (Join-Path $PSScriptRoot 'self_heal.ps1') -PolicyXml $PolicyXml -SimulationReport $SimulationReport -DryRun:$false

# 2. Pick latest candidate
$candidate = Get-ChildItem (Join-Path $PSScriptRoot 'runs\self_heal_candidate_*.xml') -File -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1

if (-not $candidate) {
    Write-Output 'No candidate generated'
    exit 1
}

Write-Output "Latest candidate: $($candidate.FullName)"

# 3. Promote to staged (audit -> staged)
if ($CIAdvance) {
    if ($StrictParsing) {
        & (Join-Path $PSScriptRoot 'promote_policy.ps1') -CandidatePath $candidate.FullName -CIAdvance -SimulationReport $SimulationReport -StrictParsing
    } else {
        & (Join-Path $PSScriptRoot 'promote_policy.ps1') -CandidatePath $candidate.FullName -CIAdvance -SimulationReport $SimulationReport
    }
} else {
    if ($StrictParsing) {
        & (Join-Path $PSScriptRoot 'promote_policy.ps1') -CandidatePath $candidate.FullName -SimulationReport $SimulationReport -StrictParsing
    } else {
        & (Join-Path $PSScriptRoot 'promote_policy.ps1') -CandidatePath $candidate.FullName -SimulationReport $SimulationReport
    }
}

# 4. Re-evaluate promotion state (this will use the recorded state if no CandidatePath passed)
if ($CIAdvance) {
    if ($StrictParsing) { & (Join-Path $PSScriptRoot 'promote_policy.ps1') -CIAdvance -SimulationReport $SimulationReport -StrictParsing } else { & (Join-Path $PSScriptRoot 'promote_policy.ps1') -CIAdvance -SimulationReport $SimulationReport }
} else {
    if ($StrictParsing) { & (Join-Path $PSScriptRoot 'promote_policy.ps1') -SimulationReport $SimulationReport -StrictParsing } else { & (Join-Path $PSScriptRoot 'promote_policy.ps1') -SimulationReport $SimulationReport }
}

Write-Output 'Pipeline run complete. policy_state.json:'
if (Test-Path (Join-Path $PSScriptRoot 'policy_state.json')) { Get-Content (Join-Path $PSScriptRoot 'policy_state.json') | ConvertFrom-Json | ConvertTo-Json -Depth 6 | Write-Output } else { Write-Output 'NO_STATEFILE' }
