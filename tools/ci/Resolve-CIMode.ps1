param(
  [string]$DiffMode = $env:DIFF_MODE,
  [string]$PSSAMode = $env:PSSA_MODE,
  [string]$ValidationMode = $env:MANIFEST_VALIDATION_MODE
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-CIMode {
  param(
    [string]$DiffMode,
    [string]$PSSAMode,
    [string]$ValidationMode
  )

  $out = [ordered]@{}
  $out.DiffMode = if ($DiffMode -and $DiffMode.Trim() -ne '') { $DiffMode.Trim().ToLower() } else { 'report' }
  $out.PSSAMode = if ($PSSAMode -and $PSSAMode.Trim() -ne '') { $PSSAMode.Trim().ToLower() } else { 'baseline' }
  $out.ValidationMode = if ($ValidationMode -and $ValidationMode.Trim() -ne '') { $ValidationMode.Trim().ToLower() } else { 'baseline' }

  $allowedDiff = @('report','gate')
  $allowedPssa = @('baseline','strict')
  $allowedVal = @('baseline','strict')

  if ($allowedDiff -notcontains $out.DiffMode) { throw "Invalid DiffMode: $($out.DiffMode)" }
  if ($allowedPssa -notcontains $out.PSSAMode) { throw "Invalid PSSAMode: $($out.PSSAMode)" }
  if ($allowedVal -notcontains $out.ValidationMode) { throw "Invalid ValidationMode: $($out.ValidationMode)" }

  # Enforce invariants
  if ($out.PSSAMode -eq 'strict') {
    if (-not $env:PSSA_BASELINE_PATH -or $env:PSSA_BASELINE_PATH.Trim() -eq '') {
      throw "PSSA strict mode requires PSSA_BASELINE_PATH to be set in the environment"
    }
  }

  # Determine human label using a stable bitmask score
  $score = 0
  if ($out.DiffMode -eq 'gate') { $score += 4 }
  if ($out.PSSAMode -eq 'strict') { $score += 2 }
  if ($out.ValidationMode -eq 'strict') { $score += 1 }

  switch ($score) {
    0 { $out.Label = 'dev' }
    1 { $out.Label = 'dev' }
    2 { $out.Label = 'dev' }
    3 { $out.Label = 'pr' }
    4 { $out.Label = 'audit' }
    5 { $out.Label = 'audit' }
    6 { $out.Label = 'main' }
    7 { $out.Label = 'main' }
    default { $out.Label = 'audit' }
  }

  # Compute enforcement grade (separate from human label)
  $out.Grade = switch ($score) {
    0 { 'low' }
    1 { 'low' }
    2 { 'medium' }
    3 { 'medium' }
    4 { 'high' }
    5 { 'high' }
    6 { 'critical' }
    7 { 'critical' }
    default { 'high' }
  }

  return $out
}

try {
  $cfg = Resolve-CIMode -DiffMode $DiffMode -PSSAMode $PSSAMode -ValidationMode $ValidationMode
  Write-Host "[cimode] Resolved: diff=$($cfg.DiffMode) pssa=$($cfg.PSSAMode) validation=$($cfg.ValidationMode) label=$($cfg.Label)"
  # Emit ci-mode.json for downstream consumers at a stable workspace path
  $workspace = if ($env:GITHUB_WORKSPACE -and $env:GITHUB_WORKSPACE.Trim() -ne '') { $env:GITHUB_WORKSPACE } else { (Get-Location).Path }
  $outPath = Join-Path -Path $workspace -ChildPath 'ci-mode.json'
  ($cfg | ConvertTo-Json -Depth 5) | Set-Content -Path $outPath -Encoding UTF8 -Force
  $fullPath = (Get-Item -Path $outPath).FullName
  if ($env:GITHUB_ENV) {
    "CI_MODE_LABEL=$($cfg.Label)" | Out-File -FilePath $env:GITHUB_ENV -Encoding utf8 -Append
    "CI_MODE_JSON_PATH=$fullPath" | Out-File -FilePath $env:GITHUB_ENV -Encoding utf8 -Append
  }
  # Also write outputs for GitHub Actions job outputs if available
  if ($env:GITHUB_OUTPUT) {
    "ci_mode_label=$($cfg.Label)" | Out-File -FilePath $env:GITHUB_OUTPUT -Encoding utf8 -Append
    "ci_mode_json=$fullPath" | Out-File -FilePath $env:GITHUB_OUTPUT -Encoding utf8 -Append
  }
  # Return JSON to stdout for local runs
  ($cfg | ConvertTo-Json -Depth 5) | Write-Host
  exit 0
} catch {
  $msg = $_.Exception.Message
  Write-Host "::error::CI mode resolution failed: $msg"
  exit 1
}
