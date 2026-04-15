# Helper to discover manifests and emit compact JSON for matrix
$ErrorActionPreference = 'Stop'
$items = @()

function Get-IndexManifests {
  param([string]$root = '.')
  Get-ChildItem -Path $root -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -like '*manifest.json' -or $_.Name -like '*-manifest.json' }
}

function Get-ExecutionManifests {
  param([string]$root = '.')
  $dirs = @('tools/ci/migrations','tools/runs')
  $files = @()
  foreach ($d in $dirs) {
    if (Test-Path $d) {
      $files += Get-ChildItem -Path $d -Recurse -File -ErrorAction SilentlyContinue -Filter '*.json'
    }
  }
  return $files
}

function Test-IsValidManifest {
  param($json)
  if (-not $json) { return $false }
  try {
    if ($json.PSObject -and $json.PSObject.Properties.Name -contains 'runId') { return $true }
  } catch {}
  return $false
}

function Get-RunId {
  param($json, $path)
  try {
    if ($json -and $json.PSObject -and $json.PSObject.Properties.Name -contains 'runId') {
      $id = [string]$json.runId
      if (-not [string]::IsNullOrWhiteSpace($id)) { return $id }
    }
  } catch {}
  # unresolved: do not fabricate a runId here
  return $null
}

$indexFiles = Get-IndexManifests -root '.'
$execFiles  = Get-ExecutionManifests -root '.'

$files = @()
if ($indexFiles) { $files += $indexFiles }
if ($execFiles)  { $files += $execFiles }
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

  try { $json = Get-Content $path -Raw | ConvertFrom-Json } catch { $json = $null }

  $isValid = Test-IsValidManifest $json
  $runId = Get-RunId $json $path
  # If runId unresolved, skip emitting (avoid fabricating parent-dir ids that collide)
  if (-not $runId) { continue }

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

  $items += [pscustomobject]@{
    path = [string]$path
    runId = [string]$runId
    hash = [string]$hash
    source = [string]$source
    valid = [bool]$isValid
  }
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