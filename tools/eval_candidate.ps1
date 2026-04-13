Set-Location 'G:\moodle'
Import-Module .\tools\AppLocker.PolicyCompiler.psm1 -Force

param(
	[string]$OutDir = "tools\\runs",
	[string]$RunId = $null
)

$runDir = if ($RunId) { Join-Path $OutDir $RunId } else { $OutDir }
$new = Parse-AppLockerPolicyXml -Path (Join-Path $runDir 'self_heal_candidate_20260412_112128.xml') -ErrorAction Stop
$work = @([PSCustomObject]@{ Path = 'C:\Windows\System32\notepad.exe'; PublisherName = $null; ProductName = $null; BinaryName = 'notepad.exe' })
$res = Evaluate-Workload -PolicyRules $new -Workload $work -Type 'Exe'
$res | ConvertTo-Json -Depth 10 | Out-File (Join-Path $runDir 'eval_notepad.json') -Encoding utf8
Write-Output 'WROTE: ' + (Join-Path $runDir 'eval_notepad.json')