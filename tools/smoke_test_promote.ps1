$ErrorActionPreference = 'Stop'

# Smoke test for promotion pipeline — parses active + latest candidate,
# diffs, sanity-checks, writes a JSON diff, and invokes promote to stage.

if (Test-Path "$PSScriptRoot\active_policy.xml") {
    $active = (Resolve-Path "$PSScriptRoot\active_policy.xml").Path
} else {
    $a = Get-ChildItem "$PSScriptRoot\runs\*enforce*.xml" -File -Recurse | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($a) { $active = $a.FullName } else { Write-Output 'NO_ACTIVE_POLICY'; exit 2 }
}

$candidateObj = Get-ChildItem "$PSScriptRoot\runs\self_heal_candidate_*.xml" -File | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $candidateObj) { Write-Output 'NO_CANDIDATE'; exit 2 } else { $candidate = $candidateObj.FullName }

Import-Module "$PSScriptRoot\AppLocker.PolicyCompiler.psm1" -Force

Write-Output "Using active: $active"
Write-Output "Using candidate: $candidate"

$irActive = Parse-AppLockerPolicyXml -Path $active
$irCandidate = Parse-AppLockerPolicyXml -Path $candidate

Write-Output "Active rules: $($irActive.Rules.Count)"
Write-Output "Candidate rules: $($irCandidate.Rules.Count)"

$nulls = $irCandidate.Rules | Where-Object { $_ -eq $null }
if ($nulls -and $nulls.Count -gt 0) { Write-Output 'NULL_RULES_DETECTED'; Write-Output $nulls.Count; exit 3 }

$diff = Compare-AppLockerIR -Left $irActive -Right $irCandidate
Write-Output "DIFF_SUMMARY: $($diff.Summary)"

if (-not (Test-Path "$PSScriptRoot\runs")) { New-Item -Path "$PSScriptRoot\runs" -ItemType Directory | Out-Null }
$diff | ConvertTo-Json -Depth 6 | Out-File "$PSScriptRoot\runs\smoke_diff.json" -Encoding utf8

if ($diff.Added.Count -gt 20) { Write-Output 'TOO_MANY_ADDED'; exit 4 }

Write-Output 'Running promote to stage candidate...'
pwsh -NoProfile -File "$PSScriptRoot\promote_policy.ps1" -CandidatePath "$candidate"

if (Test-Path "$PSScriptRoot\policy_state.json") { Get-Content "$PSScriptRoot\policy_state.json" | ConvertFrom-Json | ConvertTo-Json -Depth 6 | Write-Output } else { Write-Output 'NO_STATEFILE' }

Write-Output 'Smoke test completed'
