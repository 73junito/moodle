$json = Get-Content '.github/artifacts/manifest-run-summary.json' -Raw | ConvertFrom-Json
$resolved = $json | Where-Object { $_.runIdResolved -eq $true }
Write-Host ('Total records: ' + $json.Count)
Write-Host ('Resolved runs: ' + $resolved.Count)
foreach ($r in $resolved) {
  Write-Host '---'
  Write-Host ('runId: ' + $r.runId)
  if ($r.PSObject.Properties.Name -contains 'artifactResolutionStatus') { Write-Host ('artifactResolutionStatus: ' + $r.artifactResolutionStatus) } else { Write-Host 'artifactResolutionStatus: <missing>' }
  $ix = '<null>'
  $md = '<null>'
  $vl = '<null>'
  if ($r.artifacts) {
    if ($r.artifacts.indexPath) { $ix = $r.artifacts.indexPath }
    if ($r.artifacts.metadataPath) { $md = $r.artifacts.metadataPath }
    if ($r.artifacts.validationPath) { $vl = $r.artifacts.validationPath }
  }
  Write-Host ('artifacts.indexPath: ' + $ix)
  Write-Host ('artifacts.metadataPath: ' + $md)
  Write-Host ('artifacts.validationPath: ' + $vl)
}
