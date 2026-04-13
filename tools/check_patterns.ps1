$SetLocation = 'G:\moodle'
Set-Location $SetLocation
Import-Module .\tools\AppLocker.PolicyCompiler.psm1 -Force

param(
    [string]$OutDir = "tools\\runs",
    [string]$RunId = $null
)

$runDir = if ($RunId) { Join-Path $OutDir $RunId } else { $OutDir }
$xmlPath = Join-Path $runDir 'self_heal_candidate_20260412_120352.xml'
$newIR = Parse-AppLockerPolicyXml -Path $xmlPath
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
foreach ($r in $simIR.Rules) {
    $rp = if ($r.PSObject.Properties['Condition']) { $r.Condition.Path } elseif ($r.PSObject.Properties['Path']) { $r.Path } else { $null }
    if ($rp) {
        $pattern = [Environment]::ExpandEnvironmentVariables($rp)
        $patternNorm = $pattern -replace '\\{2,}','\\'
        Write-Output "Pattern raw: $pattern"
        Write-Output "Pattern norm: $patternNorm"
        Write-Output ('Matches notepad: ' + ('C:\\Windows\\System32\\notepad.exe' -like $patternNorm))
    }
}
$res = Simulate-Execution -PolicyRules $simIR.Rules -Type 'Exe' -FilePath 'C:\\Windows\\System32\\notepad.exe'
Write-Output ('Simulate result: ' + $res.Result)
