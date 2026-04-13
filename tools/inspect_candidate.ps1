Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'AppLocker.PolicyCompiler.psm1') -Force -ErrorAction Stop
$runs = Join-Path $PSScriptRoot 'runs'
$cand = Get-ChildItem -Path $runs -Filter 'self_heal_candidate_*.xml' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $cand) { Write-Error 'No candidate found'; exit 1 }
Write-Output "Candidate: $($cand.FullName)"
$ir = Parse-AppLockerPolicyXml -Path $cand.FullName
$i = 0
foreach ($r in $ir.Rules) {
    $i++
    Write-Output ('Rule #' + $i)
    Write-Output ($r | ConvertTo-Json -Depth 6)
    Write-Output ''
}
