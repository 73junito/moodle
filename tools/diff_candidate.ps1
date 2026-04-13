Set-Location 'G:\moodle'
Import-Module .\tools\AppLocker.PolicyCompiler.psm1 -Force

param(
	[string]$OutDir = "tools\\runs",
	[string]$RunId = $null
)

$runDir = if ($RunId) { Join-Path $OutDir $RunId } else { $OutDir }
if (Test-Path .\tools\active_policy.xml) { $old = Parse-AppLockerPolicyXml -Path .\tools\active_policy.xml -ErrorAction SilentlyContinue } else { $old = [pscustomobject]@{ Rules = @() } }
$new = Parse-AppLockerPolicyXml -Path (Join-Path $runDir 'self_heal_candidate_20260412_112128.xml') -ErrorAction Stop
$diff = Compare-AppLockerIR -Left $old -Right $new
$diff | Select-Object Added,Removed,Changed | ConvertTo-Json -Depth 10 | Out-File (Join-Path $runDir 'candidate_diff.json') -Encoding utf8
Write-Output ("WROTE: " + (Join-Path $runDir 'candidate_diff.json'))