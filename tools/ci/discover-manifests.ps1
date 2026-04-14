# Helper to discover manifests and emit compact JSON for matrix
$ErrorActionPreference = 'Stop'
$items = @()
## broaden discovery to catch common manifest filename patterns and dedupe
$patterns = @(
  '*manifest.json',
  '*-manifest.json'
)

$files = @()
foreach ($p in $patterns) {
  $files += Get-ChildItem -Path . -Recurse -Filter $p -File -ErrorAction SilentlyContinue
}

# Also include migrated and runs folders explicitly so generated stubs are discoverable
if (Test-Path 'tools/ci/migrations') {
  $files += Get-ChildItem -Path 'tools/ci/migrations' -Recurse -Filter '*.json' -File -ErrorAction SilentlyContinue
}
if (Test-Path 'tools/runs') {
  $files += Get-ChildItem -Path 'tools/runs' -Recurse -Filter '*.json' -File -ErrorAction SilentlyContinue
}
if (Test-Path 'tools' ) {
  # skip including top-level capability manifest here — it's not a run manifest
  # capability-manifest.json is an index document and not intended for per-run validation
}

# Deduplicate and then exclude known artifact filename patterns to avoid treating outputs as manifests
$files = $files | Sort-Object FullName -Unique | Where-Object { 
  $_.Name -notlike 'validation-report*' -and $_.Name -notlike 'metadata*' -and $_.Name -notlike '*.report*.json' -and $_.Name -ine 'capability-manifest.json'
}

# compute CI fingerprint to invalidate caches when CI changes
$ciFiles = @('tools/ci/ci_validate_manifest.ps1','tools/ci/run.ps1')
$ciContent = ''
foreach ($c in $ciFiles) { if (Test-Path $c) { $ciContent += (Get-Content $c -Raw) } }
$ciHash = ''
if ($ciContent -ne '') {
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($ciContent)
  $ms = New-Object System.IO.MemoryStream(, $bytes)
  $ciHash = (Get-FileHash -InputStream $ms -Algorithm SHA256).Hash.ToLower()
}

foreach ($f in $files) {
  $path = $f.FullName
  $manifestDir = Split-Path -Parent $path
  $runId = $null
  try {
    $json = Get-Content $path -Raw | ConvertFrom-Json
    if ($json -and $json.runId) { $runId = [string]$json.runId }
  } catch { $json = $null }

  # Manifest schema gate: require runId and at least one of inputs/outputs/steps, except for the capability manifest
  $isCapability = ($f.Name -ieq 'capability-manifest.json')
  if (-not $isCapability) {
    if ($null -eq $json -or -not $json.PSObject.Properties.Name -contains 'runId') { continue }
    $hasIO = ($json.PSObject.Properties.Name -contains 'inputs') -or ($json.PSObject.Properties.Name -contains 'outputs') -or ($json.PSObject.Properties.Name -contains 'steps')
    if (-not $hasIO) { continue }
  }
  if (-not $runId) { $runId = Split-Path -Leaf $manifestDir }

  # compute manifest hash base: manifest content + referenced inputs + ciHash
  $manifestContent = Get-Content $path -Raw
  $inputsContent = ''
  if ($json -and $null -ne $json.inputs) {
    foreach ($inp in $json.inputs) {
      $p = Join-Path $manifestDir $inp
      if (Test-Path $p -PathType Leaf) { $inputsContent += (Get-Content $p -Raw) }
    }
  }
  $hashBase = $manifestContent + $inputsContent + $ciHash
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($hashBase)
  $ms = New-Object System.IO.MemoryStream(, $bytes)
  $hash = (Get-FileHash -InputStream $ms -Algorithm SHA256).Hash.ToLower()

  # classify manifest source for downstream filtering/auditing
  $source = 'other'
  $norm = $path.ToLower()
  if ($norm -like '*\tools\ci\migrations\*') { $source = 'migrations' }
  elseif ($norm -like '*\tools\runs\*') { $source = 'runs' }
  elseif ($norm -like '*capability-manifest.json') { $source = 'capability' }

  $items += [pscustomobject]@{ path = [string]$path; runId = [string]$runId; hash = [string]$hash; source = [string]$source }
}

## Exclude intentionally broken test manifests from discovery
# discovery items are PSCustomObjects with a `path` property, not FileInfo
$items = $items | Where-Object { $_.path -notmatch 'broken-manifest' }

if ($items.Count -eq 0) { $json = '[]' } else { $json = $items | ConvertTo-Json -Depth 10 -Compress }
Write-Host $json

# ensure artifact dir exists (fresh checkouts may not have it)
$dir = '.github/artifacts'
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

# also write to a file for eyeballing
Set-Content -Path (Join-Path $dir 'discovery-manifests.json') -Value $json -Encoding UTF8 -Force
Write-Host "Wrote $dir/discovery-manifests.json"