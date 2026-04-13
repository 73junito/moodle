$SetLocation = 'G:\moodle'
Set-Location $SetLocation
Import-Module .\tools\AppLocker.PolicyCompiler.psm1 -Force

param(
    [string]$OutDir = "tools\\runs",
    [string]$RunId = $null
)

$runDir = if ($RunId) { Join-Path $OutDir $RunId } else { $OutDir }
$xmlPath = Join-Path $runDir 'self_heal_candidate_20260412_120352.xml'
$newIR = Parse-AppLockerPolicyXml -Path $xmlPath -ErrorAction Stop
$simIR = $newIR | ConvertTo-Json -Depth 10 | ConvertFrom-Json
$baselineInject = @('%SystemRoot%\\System32\\*','%SystemRoot%\\*','%ProgramFiles%\\*','%ProgramFiles(x86)%\\*')
foreach ($b in $baselineInject) {
    $found = $false
    foreach ($r in $simIR.Rules) {
        $rp = $null
        if ($r.PSObject.Properties['Condition']) { $rp = $r.Condition.Path } elseif ($r.PSObject.Properties['Path']) { $rp = $r.Path }
        $ra = if ($r.PSObject.Properties['Action']) { $r.Action } else { $null }
        if ($rp -and ($rp -ieq $b) -and ($ra -ieq 'Allow')) { $found = $true; break }
    }
    if (-not $found) { $simIR.Rules += [PSCustomObject]@{ Id = ([guid]::NewGuid().ToString()); Path = $b; Action = 'Allow'; Type = 'FilePath'; Tier = 'Tier0'; Name = 'baseline allow' } }
}
Write-Output ('simIR rules count: ' + $simIR.Rules.Count)
foreach ($r in $simIR.Rules) { $rp = ''; if ($r.PSObject.Properties['Condition']) { $rp = $r.Condition.Path } elseif ($r.PSObject.Properties['Path']) { $rp = $r.Path }; Write-Output ("Rule Path: $rp; Action:" + ($r.Action -as [string])) }
# Test simulate for notepad
$res = Simulate-Execution -PolicyRules $simIR.Rules -Type 'Exe' -FilePath 'C:\Windows\System32\notepad.exe'
Write-Output ("Simulate result: $($res.Result)")
