Import-Module (Join-Path $PSScriptRoot 'AppLocker.PolicyCompiler.psm1') -Force -ErrorAction Stop

$runs = Join-Path $PSScriptRoot 'runs'
$cand = Get-ChildItem -Path $runs -Filter 'self_heal_candidate_*.xml' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
Write-Output "Candidate: $($cand.FullName)"
$ir = Parse-AppLockerPolicyXml -Path $cand.FullName

$baseline = @('%SystemRoot%\System32\*','%SystemRoot%\*','%ProgramFiles%\*','%ProgramFiles(x86)%\*')

function Normalize-PathForKey {
    param($p)
    if (-not $p) { return $null }
    $s = $p.ToString().Trim()
    $s = $s -replace '\\+','\\'
    $s = $s.Trim('"', "'")
    return $s.ToLowerInvariant()
}

$baselineNorms = @()
foreach ($b in $baseline) {
    $baselineNorms += (Normalize-PathForKey $b)
    $baselineNorms += (Normalize-PathForKey ([Environment]::ExpandEnvironmentVariables($b)))
}
$baselineNorms = $baselineNorms | Sort-Object -Unique
Write-Output "Baseline norms:"
$baselineNorms | ForEach-Object { Write-Output " - $_" }

Write-Output "Parsed rule normalized paths:"
foreach ($r in $ir.Rules) {
    $p = if ($r.PSObject.Properties['Path']) { $r.Path } elseif ($r.PSObject.Properties['Condition']) { $r.Condition.Path } else { $null }
    $pn = Normalize-PathForKey $p
    Write-Output " - $pn"
}

# show which baseline norms matched
foreach ($norm in $baselineNorms) {
    $matches = $ir.Rules | Where-Object {
        $p = if ($_.PSObject.Properties['Path']) { $_.Path } elseif ($_.PSObject.Properties['Condition']) { $_.Condition.Path } else { $null }
        $pn = Normalize-PathForKey $p
        $pn -and ($pn -eq $norm)
    }
    Write-Output "norm '$norm' -> matches: $($matches.Count)"
}
