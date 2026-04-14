$path = '.github/artifacts/discovery-manifests.json'
if (-not (Test-Path $path)) { Write-Host "Discovery file not found: $path"; exit 2 }
$raw = Get-Content $path -Raw
try { $arr = $raw | ConvertFrom-Json } catch { Write-Host 'ConvertFrom-Json failed'; exit 3 }
if ($arr -eq $null -or $arr.Count -eq 0) { Write-Host 'Matrix is empty (no manifests found)'; exit 0 }
$idx = 0
foreach ($it in $arr) {
  $idx++
  if (-not ($it.path -is [string] -and $it.runId -is [string] -and $it.hash -is [string])) {
    Write-Host "INVALID entry at index $idx"
    exit 4
  }
}
Write-Host 'Matrix JSON shape OK (entries validated)'
exit 0