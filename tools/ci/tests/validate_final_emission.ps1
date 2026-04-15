param(
  [string]$FinalDebug = '.github/artifacts/manifest-run-final-debug.json',
  [string]$Summary = 'manifest-run-summary.json'
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path $FinalDebug)) { Write-Error "Final-debug file missing: $FinalDebug"; exit 2 }
if (-not (Test-Path $Summary)) { Write-Error "Summary file missing: $Summary"; exit 2 }

$fd = Get-Content $FinalDebug -Raw | ConvertFrom-Json
$sm = Get-Content $Summary -Raw | ConvertFrom-Json

# build maps by runId
$fmap = @{ }
foreach ($r in $fd) { $fmap[$r.runId] = $r }
$smap = @{ }
foreach ($r in $sm) { $smap[$r.runId] = $r }

$errors = @()

# check runId sets
$fids = $fmap.Keys | Sort-Object
$sids = $smap.Keys | Sort-Object
if (-not ($fids -join ',') -eq ($sids -join ',')) {
  $errors += "RunId sets differ between final-debug and summary"
}

# check artifactResolutionStatus and resolved artifact rules
foreach ($runId in $fmap.Keys) {
  $fr = $fmap[$runId]
  if (-not $smap.ContainsKey($runId)) { continue }
  $sr = $smap[$runId]

  $f_ars = if ($fr.PSObject.Properties.Name -contains 'artifactResolutionStatus') { $fr.artifactResolutionStatus } else { $null }
  $s_ars = if ($sr.PSObject.Properties.Name -contains 'artifactResolutionStatus') { $sr.artifactResolutionStatus } else { $null }
  if ($f_ars -ne $s_ars) { $errors += "artifactResolutionStatus mismatch for $($runId): final='$($f_ars)' vs summary='$($s_ars)'" }

  # if runIdResolved true then artifacts must be present or status==missing_index
  $resolved = if ($fr.PSObject.Properties.Name -contains 'runIdResolved') { [bool]$fr.runIdResolved } else { $false }
  $art = if ($sr.PSObject.Properties.Name -contains 'artifacts') { $sr.artifacts } else { $null }
  if ($resolved) {
    if (-not $s_ars) { $errors += "Missing artifactResolutionStatus for resolved run $($runId)" }
    if ($art -eq $null) { $errors += "Artifacts missing object for resolved run $($runId)" }
    else {
      $idx = if ($art.PSObject.Properties.Name -contains 'indexPath') { $art.indexPath } else { $null }
      if (-not $idx -and $s_ars -ne 'missing_index') { $errors += "Resolved run $($runId) has null indexPath but artifactResolutionStatus='$($s_ars)'" }
    }
  }
}

if ($errors.Count -gt 0) {
  Write-Host "Validation FAILED:";
  foreach ($e in $errors) { Write-Host " - $e" }
  exit 1
} else {
  Write-Host "Validation OK: final-debug and summary are consistent"
  exit 0
}
