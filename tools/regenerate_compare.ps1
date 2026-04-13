# Regenerate compare JSON from existing strict/resilient reports
param(
    [string]$OutDir = "tools\runs"
)
Set-StrictMode -Version Latest
$rRes = Join-Path $OutDir 'ir_validation_report_resilient.json'
$rStr = Join-Path $OutDir 'ir_validation_report_strict.json'
$reportRes = if (Test-Path $rRes) { Get-Content $rRes -Raw | ConvertFrom-Json -Depth 6 } else { $null }
$reportStr = if (Test-Path $rStr) { Get-Content $rStr -Raw | ConvertFrom-Json -Depth 6 } else { $null }
$fields = @('IsValid','RuleCount','BaselineMissing','MalformedRuleCount')
$differences = @()
function AddDiff($k,$v1,$v2){ $differences += [PSCustomObject]@{ Key=$k; Resilient=$v1; Strict=$v2 } }
AddDiff 'ResilientExitCode' ($null) ($null)
foreach ($f in $fields) {
    $v1 = if ($reportRes) { $reportRes.$f } else { $null }
    $v2 = if ($reportStr) { $reportStr.$f } else { $null }
    if ($v1 -ne $v2) { AddDiff $f $v1 $v2 }
}
$idsRes = @(); $idsStr = @()
if ($reportRes -and $reportRes.MalformedRules) { $idsRes = $reportRes.MalformedRules | ForEach-Object { $_.RuleId } }
if ($reportStr -and $reportStr.MalformedRules) { $idsStr = $reportStr.MalformedRules | ForEach-Object { $_.RuleId } }
$onlyInRes = $idsRes | Where-Object { $_ -and ($idsStr -notcontains $_) }
$onlyInStr = $idsStr | Where-Object { $_ -and ($idsRes -notcontains $_) }
if (($onlyInRes.Count -gt 0) -or ($onlyInStr.Count -gt 0)) { AddDiff 'MalformedRulesDelta' ($onlyInRes -join ',') ($onlyInStr -join ',') }
$hint = [PSCustomObject]@{
    StrictExcludedRules = ($reportStr.MalformedRuleCount -as [int])
    ResilientExcludedRules = ($reportRes.MalformedRuleCount -as [int])
    ConsistencyScore = 0.0
}
$matched=0; $total=$fields.Count
foreach ($f in $fields) { if (($reportRes) -and ($reportStr) -and ($reportRes.$f -eq $reportStr.$f)) { $matched++ } }
if ($total -gt 0) { $hint.ConsistencyScore = [math]::Round(($matched / $total),2) }
$compare = [PSCustomObject]@{
    Timestamp = (Get-Date).ToUniversalTime().ToString('o')
    ResilientReport = if ($reportRes) { $reportRes } else { $null }
    StrictReport = if ($reportStr) { $reportStr } else { $null }
    Differences = $differences
    ModeComparisonHint = $hint
}
$comparePath = Join-Path $OutDir 'ir_validation_compare.json'
$compare | ConvertTo-Json -Depth 10 | Out-File -FilePath $comparePath -Encoding UTF8
Write-Output "Comparison written: $comparePath"
