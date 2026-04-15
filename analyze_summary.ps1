$arr = Get-Content manifest-run-summary.json -Raw | ConvertFrom-Json
$total = $arr.Count
$resolved = ($arr | Where-Object { $_.runId -ne 'unknown' }).Count
$withFlag = ($arr | Where-Object { $_.PSObject.Properties.Name -contains 'runIdResolved' }).Count
Write-Host "total=$total resolvedByRunId=$resolved withRunIdResolvedField=$withFlag"
$arr | Group-Object -Property runId | ForEach-Object { Write-Host "runId=$($_.Name) count=$($_.Count)" }
