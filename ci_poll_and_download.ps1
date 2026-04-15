$run = 24460938422
$repo = '73junito/moodle'
Write-Host "Polling run $run in $repo"
while ($true) {
  $obj = gh run view $run -R $repo --json status,conclusion | ConvertFrom-Json
  $s = $obj.status + ' ' + ($obj.conclusion -ne $null ? $obj.conclusion : 'null')
  Write-Host "status=$s"
  if ($obj.status -ne 'in_progress') { break }
  Start-Sleep -Seconds 10
}
Write-Host "final status=$($obj.status) $($obj.conclusion)"
gh run download $run -R $repo -D ("artifacts_run_" + $run)
Write-Host 'DOWNLOAD_DONE'
