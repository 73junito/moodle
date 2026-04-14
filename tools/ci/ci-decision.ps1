param(
  [string]$CiModePath,
  [string]$SummaryPath = 'manifest-run-summary.json',
  [string]$DiffPath = 'manifest-run-diff.json',
  [string]$OutputPath = 'ci-decision.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Read-Json($p) { try { if (Test-Path $p) { return Get-Content $p -Raw | ConvertFrom-Json -ErrorAction Stop } } catch { } return $null }

# Compute safe defaults for parameters (avoid complex expressions in param defaults)
if (-not $CiModePath -or $CiModePath.Trim() -eq '') {
  if ($env:GITHUB_WORKSPACE -and $env:GITHUB_WORKSPACE.Trim() -ne '') {
    $base = $env:GITHUB_WORKSPACE
  } else {
    $base = (Get-Location).Path
  }
  $CiModePath = Join-Path -Path $base -ChildPath 'ci-mode.json'
}

$ci = Read-Json $CiModePath
$summary = Read-Json $SummaryPath
$diff = Read-Json $DiffPath


# determine mode and provenance
$mode = 'dev'
$mode_source = 'env'
if ($ci -and $ci.Label) { $mode = $ci.Label; $mode_source = $CiModePath } elseif ($env:CI_MODE_LABEL) { $mode = $env:CI_MODE_LABEL; $mode_source = 'env' } else { $mode = 'dev'; $mode_source = 'env' }

# Load ci-rules.json (data-driven rules). Fall back to embedded defaults so CI never breaks.
$rulesPath = Join-Path -Path (Split-Path -Parent $MyInvocation.MyCommand.Definition) -ChildPath 'ci-rules.json'
$rules = $null
$appliedRuleSetVersion = 'embedded:v1'
if (Test-Path $rulesPath) {
  try {
    $rulesTxt = Get-Content $rulesPath -Raw -ErrorAction Stop
    $rules = $rulesTxt | ConvertFrom-Json -ErrorAction Stop
    try { $appliedRuleSetVersion = (Get-FileHash -Path $rulesPath -Algorithm SHA256).Hash.ToLower() } catch { $appliedRuleSetVersion = 'filepresent:unknownhash' }
  } catch { $rules = $null }
}
if (-not $rules) {
  $rules = [ordered]@{
    priority = @('diff','validation','pssa')
    defaults = [ordered]@{
      diff = [ordered]@{ enabled = $true; threshold = 1 }
      validation = [ordered]@{ enabled = $true }
      pssa = [ordered]@{ enabled = $false; threshold = 1 }
    }
    modeOverrides = [ordered]@{
      dev = [ordered]@{ diff = [ordered]@{ enabled = $false }; validation = [ordered]@{ enabled = $false }; pssa = [ordered]@{ enabled = $false } }
      pr = [ordered]@{ diff = [ordered]@{ enabled = $true; threshold = 1 }; validation = [ordered]@{ enabled = $true }; pssa = [ordered]@{ enabled = $false } }
      main = [ordered]@{ diff = [ordered]@{ enabled = $true; threshold = 1 }; validation = [ordered]@{ enabled = $true }; pssa = [ordered]@{ enabled = $true; threshold = 1 } }
    }
  }
  $appliedRuleSetVersion = 'embedded:v1'
}

# Build effective rules for current mode by merging defaults and overrides
$effective = [ordered]@{}
$defaults = $rules.defaults
foreach ($k in $defaults.PSObject.Properties.Name) {
  $effective[$k] = @{}
  foreach ($p in ($defaults.$k).PSObject.Properties.Name) { $effective[$k][$p] = $defaults.$k.$p }
  if ($rules.modeOverrides -and $rules.modeOverrides.$mode) {
    $ov = $rules.modeOverrides.$mode
    if ($ov.PSObject.Properties.Name -contains $k) {
      foreach ($prop in ($ov.$k).PSObject.Properties.Name) { $effective[$k][$prop] = $ov.$k.$prop }
    }
  }
}

# Signals and provenance counters
$signals = [ordered]@{ diff = $false; validation = $false; pssa = $false }
$prov = [ordered]@{ diff_regressions = 0; validation_failures = 0; pssa_new_findings = 0; mode_source = $mode_source }

# diff signal: count regressions
try {
  if ($diff -and $diff.PSObject.Properties.Name -contains 'regressions') {
    $regs = @($diff.regressions).Count
    $prov.diff_regressions = $regs
    $diffRule = $effective['diff']
    if ($diffRule.enabled -and ($regs -ge ($diffRule.threshold -as [int]))) { $signals.diff = $true }
  }
} catch { }

# validation signal: count failures and post errors
$valCount = 0
if ($summary) {
  foreach ($r in @($summary)) {
    try {
      if ($r.status -and $r.status.ToString().ToLower() -eq 'failed') { $valCount += 1 }
      if ($r.validation -and $r.validation.post -and $r.validation.post.PSObject.Properties.Name -contains 'errors') { $valCount += @($r.validation.post.errors).Count }
    } catch { }
  }
}
$prov.validation_failures = $valCount
$valRule = $effective['validation']
if ($valRule.enabled -and $valCount -gt 0) { $signals.validation = $true }

# pssa signal: count newFindings/newSamples
$pssaCount = 0
if ($summary) {
  foreach ($r in @($summary)) {
    try {
      if ($r.pssa -and $r.pssa.PSObject.Properties.Name -contains 'newFindings') { $pssaCount += ([int]$r.pssa.newFindings) }
      if ($r.pssa -and $r.pssa.PSObject.Properties.Name -contains 'newSamples') { $pssaCount += @($r.pssa.newSamples).Count }
    } catch { }
  }
}
$prov.pssa_new_findings = $pssaCount
$pssaRule = $effective['pssa']
if ($pssaRule.enabled -and ($pssaCount -ge ($pssaRule.threshold -as [int]))) { $signals.pssa = $true }

# Decision by configured priority
# Default to fail to avoid silent green when inputs are corrupted.
$decision = 'fail'
$reason = 'no_signals_evaluated'
$ruleEvaluationTrace = @()
# track whether any rule traces were produced
$anyRuleTrace = $false

# Helper: get actual numeric value for a signal
function Get-SignalActual($name, $prov) {
  switch ($name) {
    'diff' { return $prov.diff_regressions }
    'validation' { return $prov.validation_failures }
    'pssa' { return $prov.pssa_new_findings }
    default { return 0 }
  }
}

foreach ($sig in $rules.priority) {
  # robust key check using Keys collection (works for ordered hashtable)
  if (-not ($effective.Keys -contains $sig)) { continue }

  $rawRule = $effective[$sig]
  # normalize rule access: support hashtable or PSCustomObject
  $enabled = $false
  $threshold = $null
  try {
    if ($rawRule -is [System.Collections.IDictionary]) {
      $enabled = $rawRule['enabled'] -as [bool]
      if ($rawRule.Contains('threshold')) { $threshold = $rawRule['threshold'] }
    } else {
      $enabled = $rawRule.enabled -as [bool]
      if ($rawRule.PSObject.Properties.Name -contains 'threshold') { $threshold = $rawRule.threshold }
    }
  } catch { }

  $actual = Get-SignalActual $sig $prov
  $traceItem = [ordered]@{ signal = $sig; enabled = $enabled; threshold = $threshold; actual = $actual }
  $ruleEvaluationTrace += $traceItem
  $anyRuleTrace = $true

  if ($enabled) {
    if ($sig -eq 'diff' -and $threshold -ne $null -and ($actual -ge ($threshold -as [int]))) { $decision = 'fail'; $reason = 'diff_regressions'; break }
    if ($sig -eq 'validation' -and ($actual -gt 0)) { $decision = 'fail'; $reason = 'validation_failures'; break }
    if ($sig -eq 'pssa' -and $threshold -ne $null -and ($actual -ge ($threshold -as [int]))) { $decision = 'fail'; $reason = 'pssa_new_findings'; break }
  }
}

# Mode-aware enforcement: in strict modes, any observed violations should not silently pass
$modeStrict = @('main','audit') -contains $mode
if ($modeStrict -and $decision -eq 'pass' -and ($prov.diff_regressions -gt 0 -or $prov.validation_failures -gt 0 -or $prov.pssa_new_findings -gt 0)) {
  $decision = 'fail'
  $reason = 'mode_enforced_violations'
  $ruleEvaluationTrace += [ordered]@{ signal = 'mode_enforcement'; enabled = $true; threshold = $null; actual = @{ diff = $prov.diff_regressions; validation = $prov.validation_failures; pssa = $prov.pssa_new_findings } }
}

# If we produced rule traces and no rule triggered a failure, consider the evaluation valid and set pass
if ($anyRuleTrace -and $decision -eq 'fail' -and $reason -eq 'no_signals_evaluated') {
  $decision = 'pass'
  $reason = 'none'
}

# Safety: do not emit empty/unknown decision
if (-not $decision -or $decision.ToString().Trim() -eq '') {
  $decision = 'fail'
  $reason = 'invalid_empty_decision'
}

$out = [ordered]@{
  decision = $decision
  reason = $reason
  mode = $mode
  mode_source = $prov.mode_source
  signals = $signals
  provenance = $prov
  appliedRuleSetVersion = $appliedRuleSetVersion
  ruleEvaluationTrace = $ruleEvaluationTrace
  timestamp = (Get-Date).ToString('o')
}

($out | ConvertTo-Json -Depth 10) | Set-Content -Path $OutputPath -Encoding UTF8 -Force
Write-Host "[ci-decision] Wrote decision to $OutputPath"
($out | ConvertTo-Json -Depth 10) | Write-Host
exit 0
