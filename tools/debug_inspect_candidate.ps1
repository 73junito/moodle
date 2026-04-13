Set-Location 'G:\moodle'
Import-Module .\tools\AppLocker.PolicyCompiler.psm1 -Force

param(
    [string]$OutDir = "tools\\runs",
    [string]$RunId = $null
)

$runDir = if ($RunId) { Join-Path $OutDir $RunId } else { $OutDir }
$xmlPath = Join-Path $runDir 'self_heal_candidate_20260412_120352.xml'
$ir = Parse-AppLockerPolicyXml -Path $xmlPath
Write-Output ($ir.GetType().FullName)
if ($ir.PSObject.Properties['Rules']) { Write-Output ('Rules count: ' + ($ir.Rules.Count)) } else { Write-Output 'No Rules property' }
for ($i=0; $i -lt $ir.Rules.Count; $i++) {
    $r = $ir.Rules[$i]
    $rp = ''
    if ($r.PSObject.Properties['Condition']) { $rp = $r.Condition.Path } elseif ($r.PSObject.Properties['Path']) { $rp = $r.Path }
    $id = $null
    if ($r.PSObject.Properties['RuleId']) { $id = $r.RuleId } elseif ($r.PSObject.Properties['Id']) { $id = $r.Id }
    $type = $null
    if ($r.PSObject.Properties['RuleType']) { $type = $r.RuleType } elseif ($r.PSObject.Properties['Type']) { $type = $r.Type }
    Write-Output "Rule[$i] Type:$type Id:$id Path:$rp"
}
