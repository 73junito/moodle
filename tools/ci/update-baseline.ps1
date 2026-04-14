[CmdletBinding(SupportsShouldProcess=$true)]
param(
  [string]$InputPath = '.github/artifacts/pssa-results.json',
  [string]$BaselinePath = 'tools/ci/pssa-baseline.json',
  [switch]$Apply,
  [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "PSSA Baseline Updater"

function Read-PssaResults($path) {
  if (-not (Test-Path $path)) { return $null }
  try { $p = Get-Content $path -Raw | ConvertFrom-Json -ErrorAction Stop; return $p } catch { return $null }
}

function Get-FindingPath($f) {
  if ($f.ScriptName) { return $f.ScriptName }
  if ($f.FileName) { return $f.FileName }
  if ($f.Path) { return $f.Path }
  return ''
}

function Normalize-Message($m) { if (-not $m) { return '' } ; return ($m -replace '\s+',' ' ).Trim() }

function Get-Fingerprint($f) {
  $file = (Get-FindingPath $f) -replace '\\','/'
  $rule = if ($f.RuleName) { $f.RuleName } elseif ($f.Rule) { $f.Rule } else { '' }
  $msg = Normalize-Message $f.Message
  return "$file|$rule|$msg"
}

# Read current findings
$currentRaw = Read-PssaResults -path $InputPath
if ($null -eq $currentRaw) {
  Write-Host "No PSSA results found at: $InputPath"
  exit 0
}

# Normalize to array of findings
$allFindings = @()
if ($currentRaw -is [System.Array]) { $allFindings += $currentRaw } elseif ($currentRaw.Findings) { $allFindings += $currentRaw.Findings } else { $allFindings += $currentRaw }

# build current set keyed by fingerprint
$currentSet = @{}
foreach ($f in $allFindings) {
  $k = Get-Fingerprint $f
  if (-not $k) { continue }
  if (-not $currentSet.ContainsKey($k)) { $currentSet[$k] = $f }
}

# read baseline if exists
$baselineSet = @{}
if (Test-Path $BaselinePath) {
  try {
    $base = Get-Content $BaselinePath -Raw | ConvertFrom-Json -ErrorAction Stop
    foreach ($bf in $base) { $k = Get-Fingerprint $bf; if ($k) { $baselineSet[$k] = $bf } }
  } catch {
    Write-Host ("Warning: could not read baseline {0}: {1}" -f $BaselinePath, $_.Exception.Message)
  }
}

# compute deltas
$newKeys = $currentSet.Keys | Where-Object { -not $baselineSet.ContainsKey($_) }
$existingKeys = $currentSet.Keys | Where-Object { $baselineSet.ContainsKey($_) }
$resolvedKeys = $baselineSet.Keys | Where-Object { -not $currentSet.ContainsKey($_) }

$newCount = ($newKeys | Measure-Object).Count
$existingCount = ($existingKeys | Measure-Object).Count
$resolvedCount = ($resolvedKeys | Measure-Object).Count

Write-Host "PSSA Baseline Update Preview`n"
Write-Host "New findings: $newCount"
Write-Host "Resolved findings: $resolvedCount"
Write-Host "Unchanged: $existingCount`n"

if ($newCount -gt 0) {
  Write-Host "Changes (sample up to 50):`n"
  $i = 0
  foreach ($k in $newKeys) {
    if ($i -ge 50) { break }
    $f = $currentSet[$k]
    $file = Get-FindingPath $f
    $line = if ($f.Line) { $f.Line } else { '' }
    $rule = if ($f.RuleName) { $f.RuleName } elseif ($f.Rule) { $f.Rule } else { '' }
    if ($line) { Write-Host ("+ {0} ({1}:{2})" -f $rule, $file, $line) } else { Write-Host ("+ {0} ({1})" -f $rule, $file) }
    $i++
  }
}

if ($resolvedCount -gt 0) {
  $j = 0
  foreach ($k in $resolvedKeys) {
    if ($j -ge 50) { break }
    $bf = $baselineSet[$k]
    $file = Get-FindingPath $bf
    $line = if ($bf.Line) { $bf.Line } else { '' }
    $rule = if ($bf.RuleName) { $bf.RuleName } elseif ($bf.Rule) { $bf.Rule } else { '' }
    if ($line) { Write-Host ("- {0} ({1}:{2})" -f $rule, $file, $line) } else { Write-Host ("- {0} ({1})" -f $rule, $file) }
    $j++
  }
}

if (-not $Apply) { Write-Host "\nRun with -Apply -Force to write the baseline."; exit 0 }

# Require explicit Force to apply
if ($Apply -and -not $Force) {
  Write-Host "ERROR: Baseline update requires -Force to prevent accidental overwrite"; exit 2
}

# CI guard: only allow baseline write on main
if ($env:CI -and $env:GITHUB_REF) {
  if ($env:GITHUB_REF -ne 'refs/heads/main') {
    Write-Host "ERROR: Baseline updates only allowed on main branch in CI"; exit 3
  }
}

# Confirm and write baseline
if ($PSCmdlet.ShouldProcess($BaselinePath, 'Write baseline')) {
  $outDir = Split-Path -Parent $BaselinePath
  if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
  $vals = $currentSet.Values
  $vals | ConvertTo-Json -Depth 6 | Set-Content -Path $BaselinePath -Encoding UTF8 -Force
  Write-Host "Baseline updated: $BaselinePath"
} else {
  Write-Host "Operation cancelled by ShouldProcess/WhatIf."; exit 0
}
