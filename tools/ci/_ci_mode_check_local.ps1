$ciPath = Join-Path $PWD 'ci-mode.json'
$ci = $null
if (Test-Path $ciPath) { try { $ci = Get-Content $ciPath -Raw | ConvertFrom-Json -ErrorAction Stop } catch { $ci = $null } }
$label1 = if ($ci -and $ci.Label) { $ci.Label } else { $null }
$label2 = $env:CI_MODE_LABEL
Write-Host "[ci-check] ci-mode.json label = $label1"
Write-Host "[ci-check] env label = $label2"
if ($label1 -and $label2 -and ($label1 -ne $label2)) { Write-Host '::warning::CI mode mismatch between ci-mode.json and CI_MODE_LABEL' }
exit 0
