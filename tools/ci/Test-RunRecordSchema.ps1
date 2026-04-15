param(
  [Parameter(Mandatory=$true)]
  [string]$InputJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "[schema-validator] Validating RunRecord v1 JSON: $InputJson"
if (-not (Test-Path $InputJson)) {
  Write-Host "::error::Input JSON not found: $InputJson"
  exit 1
}

try {
  $arr = Get-Content $InputJson -Raw | ConvertFrom-Json -ErrorAction Stop
} catch {
  Write-Host "::error::Failed to parse JSON: $($_.Exception.Message)"
  exit 1
}

if (-not ($arr -is [System.Array])) {
  Write-Host "::error::Top-level JSON must be an array of RunRecord objects"
  exit 1
}

$allowedStatus = @('success','failed','skipped')
$idx = 0
foreach ($rec in $arr) {
  $idx++
  # runId
  if (-not $rec.PSObject.Properties.Name -contains 'runId' -or [string]$rec.runId -eq '') {
    Write-Host "::error::RunRecord[$idx] missing or empty 'runId'"
    exit 1
  }
  # manifestPath
  if (-not $rec.PSObject.Properties.Name -contains 'manifestPath' -or [string]$rec.manifestPath -eq '') {
    Write-Host "::error::RunRecord[$idx] missing or empty 'manifestPath'"
    exit 1
  }
  # status
  if (-not $rec.PSObject.Properties.Name -contains 'status' -or [string]$rec.status -eq '') {
    Write-Host "::error::RunRecord[$idx] missing or empty 'status'"
    exit 1
  }
  $st = [string]$rec.status.ToLower()
  if ($allowedStatus -notcontains $st) {
    Write-Host "::error::RunRecord[$idx] invalid 'status' value: $($rec.status)"
    exit 1
  }
  # artifacts
  if (-not $rec.PSObject.Properties.Name -contains 'artifacts') {
    Write-Host "::error::RunRecord[$idx] missing 'artifacts' object"
    exit 1
  }
  $art = $rec.artifacts
  $requiredArtKeys = @('indexPath','metadataPath','validationPath','pssaPath','stepsPaths')
  foreach ($k in $requiredArtKeys) {
    if (-not $art.PSObject.Properties.Name -contains $k) {
      Write-Host "::error::RunRecord[$idx] artifacts missing key: $k"
      exit 1
    }
  }
  # attemptCount optional but if present should be integer
  if ($rec.PSObject.Properties.Name -contains 'attemptCount') {
    try { [int]$rec.attemptCount | Out-Null } catch { Write-Host "::error::RunRecord[$idx] attemptCount is not an integer"; exit 1 }
  }
}

Write-Host "[schema-validator] RunRecord v1 validation passed: $($arr.Count) records"
exit 0
