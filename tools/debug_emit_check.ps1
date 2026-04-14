$SetStrict = $true
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'AppLocker.PolicyCompiler.psm1') -Force -ErrorAction Stop

param(
    [string]$OutDir = "tools\\runs",
    [string]$RunId = $null
)

$ir = Parse-AppLockerPolicyXml -Path './tools/tests/sample_inspect.xml'
$runDir = if ($RunId) { Join-Path $OutDir $RunId } else { $OutDir }
$events = Parse-SimulationReport -Path (Join-Path $runDir '..\fixtures\positive_sim.json')
$suggestions = Suggest-RulesFromEvents -Events $events
$newIR = Merge-SuggestionsIntoIR -IR $ir -Suggestions $suggestions
Write-Output '--- Normalized Rules ---'
$i = 0
foreach ($r in $newIR.Rules) {
    $i++
    Write-Output ('Rule #' + $i)
    Write-Output ($r | ConvertTo-Json -Depth 6)
    Write-Output ''
}
try {
    Emit-CandidatePolicy -IR $newIR -OutPath (Join-Path $runDir 'tmp_candidate.xml') -Verbose
} catch {
    Write-Output '--- EMIT EXCEPTION ---'
    Write-Output ($_ | Out-String)
    if ($_.Exception) { $_.Exception | Format-List * -Force }
}
Write-Output 'done'
