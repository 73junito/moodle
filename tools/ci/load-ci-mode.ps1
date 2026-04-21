param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
# Load ci-mode.json and export selected preset values to GITHUB_ENV
try {
  $jsonPath = Join-Path -Path (Get-Location) -ChildPath 'tools/ci/ci-mode.json'
  if (-not (Test-Path $jsonPath)) {
    Write-Host "ci-mode.json not found at $jsonPath. Using default CI modes."
    $presetName = 'dev'
    $preset = [pscustomobject]@{ DIFF_MODE='report'; PSSA_MODE='baseline'; MANIFEST_VALIDATION_MODE='baseline' }
  } else {
    $cfg = Get-Content -Raw -Path $jsonPath | ConvertFrom-Json
    $presetName = if ($null -ne $cfg.currentPreset) { $cfg.currentPreset } else { 'dev' }
    $preset = $cfg.presets.$presetName
    if ($null -eq $preset) {
      Write-Host "Preset '$presetName' not found in ci-mode.json. Falling back to 'dev'."
      $presetName = 'dev'
      $preset = $cfg.presets.dev
    }
  }

  foreach ($prop in $preset.PSObject.Properties) {
    "$($prop.Name)=$($prop.Value)" | Out-File -FilePath $env:GITHUB_ENV -Encoding utf8 -Append
  }
  Write-Host "Loaded CI mode preset: $presetName"
} catch {
  Write-Host "::error::Failed to load ci-mode.json: $($_.Exception.Message)"
  exit 1
}
