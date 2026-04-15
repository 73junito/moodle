$a = Get-Content '.github/artifacts/manifest-run-summary.json' -Raw | ConvertFrom-Json
$resolved = $a | Where-Object { $_.runIdResolved -eq $true }
Write-Host 'resolved count=' $resolved.Count
$bad = $resolved | Where-Object { -not $_.PSObject.Properties.Name -contains 'artifactResolutionStatus' -or -not $_.artifactResolutionStatus -or ($_.artifacts -and $_.artifacts.indexPath -eq $null -and $_.artifactResolutionStatus -ne 'missing_index') }
Write-Host 'resolved with missing/invalid artifacts=' $bad.Count
if ($bad.Count -gt 0) {
  $bad | ForEach-Object { Write-Host ' -' $_.runId 'artifacts.indexPath=' ($_.artifacts.indexPath) 'artifactResolutionStatus=' $_.artifactResolutionStatus }
}
else {
  Write-Host 'All resolved runs have artifactResolutionStatus and non-silent artifact status (or explicit missing_index).'
}
