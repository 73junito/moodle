<#
Deterministic 3-phase CI runner for self_heal:
 Phase 1: Execute resilient and strict runs into per-run directories
 Phase 2: Evaluate reports and build compare JSON
 Phase 3: Decide CI exit code based on artifact presence (strict non-zero allowed)
#>
param(
    [Parameter(Mandatory=$true)][string]$PolicyXml,
    [Parameter(Mandatory=$true)][string]$SimulationReport,
    [string]$OutDir = (Join-Path $PSScriptRoot 'runs'),
    [switch]$FailOnDivergence,
    [string]$RunId
)

Set-StrictMode -Version Latest
function Log { param($m) $ts = (Get-Date).ToString('s'); Write-Host "[$ts] $m" }

if (-not (Test-Path $PolicyXml)) { Write-Error "PolicyXml not found: $PolicyXml"; exit 2 }
if (-not (Test-Path $SimulationReport)) { Write-Error "SimulationReport not found: $SimulationReport"; exit 2 }
if (-not (Test-Path (Join-Path $PSScriptRoot 'self_heal.ps1'))) { Write-Error "self_heal.ps1 not found"; exit 2 }

if (-not (Test-Path $OutDir)) { New-Item -Path $OutDir -ItemType Directory | Out-Null }

$# Phase 1: Execute
# Use provided RunId when given, otherwise generate deterministic run id
if ($RunId) { $runId = $RunId } else { $runId = "run_{0}_{1}" -f (Get-Date).ToString('yyyyMMdd_HHmmss'), ([guid]::NewGuid().ToString().Substring(0,8)) }
$runDir = Join-Path $OutDir $runId
New-Item -Path $runDir -ItemType Directory | Out-Null
$resDir = Join-Path $runDir 'resilient'
$strDir = Join-Path $runDir 'strict'
New-Item -Path $resDir -ItemType Directory | Out-Null
New-Item -Path $strDir -ItemType Directory | Out-Null

function RunSelfHeal($isStrict, [string]$destReport) {
    $args = @('-NoProfile','-File',(Join-Path $PSScriptRoot 'self_heal.ps1'),'-PolicyXml',$PolicyXml,'-SimulationReport',$SimulationReport,'-DryRun','-ReportPath',$destReport)
    if ($isStrict) { $args += '-StrictMode' }
    Log ("Running self_heal (StrictMode=$isStrict) -> $destReport")
    $p = Start-Process -FilePath pwsh -ArgumentList $args -Wait -NoNewWindow -PassThru -ErrorAction SilentlyContinue
    return [int]$p.ExitCode
}

# Run resilient
$resReport = Join-Path $resDir 'ir_validation_report.json'
 $exitRes = [int](RunSelfHeal -isStrict:$false -destReport $resReport)
 if ($exitRes -ne 0) { Log "Resilient run exited non-zero: $exitRes"; Log "Resilient run must succeed; failing CI"; exit 3 }

# Run strict (non-zero exit expected for validation failure)
$strReport = Join-Path $strDir 'ir_validation_report.json'
$exitStr = RunSelfHeal -isStrict:$true -destReport $strReport
Log "Strict run exit code: $exitStr (non-zero is expected for validation failures)"


# Phase 2: Evaluate
Log "Loading reports from $runDir"
$reportRes = if (Test-Path $resReport) { Get-Content $resReport -Raw | ConvertFrom-Json -Depth 8 } else { $null }
$reportStr = if (Test-Path $strReport) { Get-Content $strReport -Raw | ConvertFrom-Json -Depth 8 } else { $null }

# Capture git commit for traceability if available
$gitCommit = $null
try {
    $gitCommit = (& git -C $PSScriptRoot rev-parse --short HEAD) 2>$null
} catch { $gitCommit = $null }

# Write run metadata for reproducibility
$meta = [PSCustomObject]@{
    RunId = $runId
    GitCommit = $gitCommit
    Timestamp = (Get-Date).ToUniversalTime().ToString('o')
}
$metaPath = Join-Path $runDir 'metadata.json'
$meta | ConvertTo-Json -Depth 3 | Out-File -FilePath $metaPath -Encoding UTF8
Log "Run metadata written: $metaPath"

$differences = @()
function AddDiff($k,$v1,$v2) { $differences += [PSCustomObject]@{ Key=$k; Resilient=$v1; Strict=$v2 } }

AddDiff 'ResilientExitCode' $exitRes $exitStr

$fields = @('IsValid','RuleCount','BaselineMissing','MalformedRuleCount')
foreach ($f in $fields) {
    $v1 = if ($reportRes) { $reportRes.$f } else { $null }
    $v2 = if ($reportStr) { $reportStr.$f } else { $null }
    if ($v1 -ne $v2) { AddDiff $f $v1 $v2 }
}

$idsRes = @(); $idsStr = @()
if ($reportRes -and $reportRes.MalformedRules) { $idsRes = $reportRes.MalformedRules | ForEach-Object { $_.RuleId } }
if ($reportStr -and $reportStr.MalformedRules) { $idsStr = $reportStr.MalformedRules | ForEach-Object { $_.RuleId } }
$onlyInRes = @(); $onlyInStr = @()
if ($idsRes) { $onlyInRes = $idsRes | Where-Object { $_ -and ($idsStr -notcontains $_) } }
if ($idsStr) { $onlyInStr = $idsStr | Where-Object { $_ -and ($idsRes -notcontains $_) } }
if ( ( ($onlyInRes) -and ( ($onlyInRes | Measure-Object).Count -gt 0 ) ) -or ( ($onlyInStr) -and ( ($onlyInStr | Measure-Object).Count -gt 0 ) ) ) {
    AddDiff 'MalformedRulesDelta' ($onlyInRes -join ',') ($onlyInStr -join ',')
}

$hint = [PSCustomObject]@{
    StrictExcludedRules = ($reportStr.MalformedRuleCount -as [int])
    ResilientExcludedRules = ($reportRes.MalformedRuleCount -as [int])
    ConsistencyScore = 0.0
}
$matched = 0; $total = $fields.Count
foreach ($f in $fields) { if (($reportRes) -and ($reportStr) -and ($reportRes.$f -eq $reportStr.$f)) { $matched++ } }
if ($total -gt 0) { $hint.ConsistencyScore = [math]::Round(($matched / $total),2) }

$compare = [PSCustomObject]@{
    Timestamp = (Get-Date).ToUniversalTime().ToString('o')
    RunId = $runId
    ResilientReport = if ($reportRes) { $reportRes } else { $null }
    StrictReport = if ($reportStr) { $reportStr } else { $null }
    Differences = $differences
    ModeComparisonHint = $hint
}

$comparePath = Join-Path $runDir 'ir_validation_compare.json'
$compare | ConvertTo-Json -Depth 12 | Out-File -FilePath $comparePath -Encoding UTF8
Log "Comparison written: $comparePath"


# Phase 3: Decide CI exit code
if (-not $reportRes) { Log 'Resilient report missing; failing CI'; exit 3 }
if (-not $reportStr) { Log 'Strict report missing; failing CI'; exit 4 }

# Optional divergence check
if ($FailOnDivergence) {
    if ($differences.Count -gt 0) { Log 'Divergence detected and FailOnDivergence set; failing CI'; exit 5 }
}

Log 'All required artifacts present; exiting 0'
exit 0
