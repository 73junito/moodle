# Prefer run-scoped discovery file under .github/artifacts/<RunId>/discovery-manifests.json
$runId = $env:GITHUB_RUN_ID
if (-not $runId) { $runId = 'local' }
$pathCandidates = @(
  ".github/artifacts/$runId/discovery-manifests.json",
  ".github/artifacts/discovery-manifests.json"
)

$path = $null
foreach ($p in $pathCandidates) { if (Test-Path $p) { $path = $p; break } }
if (-not $path) { Write-Host "Discovery file not found (tried run-scoped and legacy locations): $($pathCandidates -join ', ')"; exit 2 }
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