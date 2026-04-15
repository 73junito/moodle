Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-CIMode {
  param()

  $out = [ordered]@{
    Label = $null
    DiffMode = $null
    PSSAMode = $null
    ValidationMode = $null
    Source = $null
  }

  try {
    $workspace = if ($env:GITHUB_WORKSPACE -and $env:GITHUB_WORKSPACE.Trim() -ne '') { $env:GITHUB_WORKSPACE } else { (Get-Location).Path }
    $ciModePath = Join-Path -Path $workspace -ChildPath 'ci-mode.json'
    if (Test-Path $ciModePath) {
      try {
        $ci = Get-Content $ciModePath -Raw | ConvertFrom-Json -ErrorAction Stop
        $out.Label = if ($ci.Label) { $ci.Label } else { $null }
        $out.DiffMode = if ($ci.DiffMode) { $ci.DiffMode } else { $null }
        $out.PSSAMode = if ($ci.PSSAMode) { $ci.PSSAMode } else { $null }
        $out.ValidationMode = if ($ci.ValidationMode) { $ci.ValidationMode } else { $null }
        $out.Source = 'ci-mode.json'
        return [pscustomobject]$out
      } catch { }
    }

    if ($env:CI_MODE_LABEL) {
      $out.Label = $env:CI_MODE_LABEL
      $out.DiffMode = if ($env:DIFF_MODE) { $env:DIFF_MODE } else { $null }
      $out.PSSAMode = if ($env:PSSA_MODE) { $env:PSSA_MODE } else { $null }
      $out.ValidationMode = if ($env:MANIFEST_VALIDATION_MODE) { $env:MANIFEST_VALIDATION_MODE } else { $null }
      $out.Source = 'CI_MODE_LABEL'
      return [pscustomobject]$out
    }

    # legacy env fallback
    $out.Label = 'dev'
    $out.DiffMode = if ($env:DIFF_MODE) { $env:DIFF_MODE } else { 'report' }
    $out.PSSAMode = if ($env:PSSA_MODE) { $env:PSSA_MODE } else { 'baseline' }
    $out.ValidationMode = if ($env:MANIFEST_VALIDATION_MODE) { $env:MANIFEST_VALIDATION_MODE } else { 'baseline' }
    $out.Source = 'legacy-env'
    return [pscustomobject]$out
  } catch {
    return [pscustomobject]@{ Label='dev'; DiffMode='report'; PSSAMode='baseline'; ValidationMode='baseline'; Source='error' }
  }
}

if ($MyInvocation.InvocationName -ne '.') {
  # When executed directly, emit the object to stdout
  $cm = Get-CIMode
  $cm | ConvertTo-Json -Depth 5
}
