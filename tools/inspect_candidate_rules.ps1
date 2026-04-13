Set-Location 'G:\moodle'
Import-Module .\tools\AppLocker.PolicyCompiler.psm1 -Force

param(
    [string]$OutDir = "tools\\runs",
    [string]$RunId = $null
)

$runDir = if ($RunId) { Join-Path $OutDir $RunId } else { $OutDir }
$ir = Parse-AppLockerPolicyXml -Path (Join-Path $runDir 'self_heal_candidate_20260412_120352.xml')
 $out = @()
 foreach ($r in $ir.Rules) {
     $p = $null
     if ($r.PSObject.Properties['Condition']) { $p = $r.Condition.Path } elseif ($r.PSObject.Properties['Path']) { $p = $r.Path }
     $rid = $null
     if ($r.PSObject.Properties['RuleId']) { $rid = $r.RuleId } elseif ($r.PSObject.Properties['Id']) { $rid = $r.Id }
     $name = $null
     if ($r.PSObject.Properties['Name']) { $name = $r.Name } elseif ($r.PSObject.Properties['Description']) { $name = $r.Description }
     $action = $null
     if ($r.PSObject.Properties['Action']) { $action = $r.Action } elseif ($r.PSObject.Properties['Action']) { $action = $r.Action }
     $out += [PSCustomObject]@{ RuleId = $rid; Path = $p; Action = $action; Name = $name }
 }
 $out | ConvertTo-Json -Depth 6 | Out-File .\tools\runs\candidate_rules_list.json -Encoding utf8
Write-Output 'WROTE: .\tools\runs\candidate_rules_list.json'