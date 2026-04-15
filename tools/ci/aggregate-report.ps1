param(
  [string]$ArtifactsDir = '.github/artifacts',
  [string]$OutputJson = 'manifest-run-summary.json',
  [switch]$StrictContract,
  [switch]$TraceRunBuilder,
  [switch]$DebugDump,
  [string]$BaselinePath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Read-JsonFile($path) {
  try { return Get-Content $path -Raw | ConvertFrom-Json -ErrorAction Stop } catch { return $null }
}

# Normalize runId canonicalization in one place
function Normalize-RunId($id) {
  # Return $null for absent/empty ids; final conversion to 'unknown' happens at serialization
  if ($null -eq $id) { return $null }
  try {
    $s = $id.ToString()
    if ([string]::IsNullOrWhiteSpace($s)) { return $null }
    return $s.Trim()
  } catch { return $null }
}

# Resolve canonical runId for an index record with optional fallback.
function Get-CanonicalRunId($Index, $FallbackRunId) {
  if ($null -ne $Index) {
    $v = Get-Prop $Index 'runId'
    if (-not $v) { $v = Get-Prop $Index 'run_id' }
    if (-not $v) { $v = Get-Prop $Index 'id' }
    try {
      if ($v -and -not [string]::IsNullOrWhiteSpace($v.ToString())) { return $v.ToString().Trim() }
    } catch { }
  }
  if ($FallbackRunId -and -not [string]::IsNullOrWhiteSpace($FallbackRunId.ToString())) { return $FallbackRunId.ToString().Trim() }
  return $null
}

# Emit structured trace events (JSONL) when enabled
function Emit-TraceEvent($ArtifactsDir, $eventObj) {
  try {
    $tracePath = Join-Path -Path $ArtifactsDir -ChildPath 'ci-trace.jsonl'
    $line = ($eventObj | ConvertTo-Json -Depth 10 -Compress)
    Add-Content -Path $tracePath -Value $line -Encoding UTF8
    Write-Host "[trace] appended event to: $tracePath"
  } catch {
    Write-Host "[trace] Failed to write trace event: $($_.Exception.Message)"
  }
}

function Get-Prop($obj, $name) {
  if ($null -eq $obj) { return $null }
  try {
    if ($obj.PSObject.Properties.Name -contains $name) { return $obj.$name } else { return $null }
  } catch { return $null }
}

Write-Host "[aggregator] Scanning artifacts under: $ArtifactsDir"
Write-Host "[aggregator] TraceRunBuilder switch = $TraceRunBuilder"

# Make artifacts directory resolution resilient in CI where artifacts
# are downloaded to the workspace root rather than .github/artifacts.
try {
  if ($env:GITHUB_WORKSPACE -and $env:GITHUB_WORKSPACE.Trim() -ne '') { $workspaceRoot = $env:GITHUB_WORKSPACE } else { $workspaceRoot = (Get-Location).Path }
} catch { $workspaceRoot = (Get-Location).Path }

if (-not (Test-Path $ArtifactsDir)) {
  Write-Host "[aggregator] ArtifactsDir not found: $ArtifactsDir"
  $ArtifactsDir = $workspaceRoot
  Write-Host "[aggregator] Falling back to workspace root: $ArtifactsDir"
}

Write-Host "[aggregator] Effective scan root: $ArtifactsDir"
try {
  Get-ChildItem -Path $ArtifactsDir -Recurse -Depth 2 -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName | ForEach-Object { Write-Host "[aggregator] FS: $_" }
} catch { }

# Load CI context for observability (prefer canonical ci-mode.json, then CI_MODE_LABEL, then legacy envs)
$ciMode = $null
try {
  $ciModePath = if ($env:GITHUB_WORKSPACE -and $env:GITHUB_WORKSPACE.Trim() -ne '') { Join-Path $env:GITHUB_WORKSPACE 'ci-mode.json' } else { Join-Path (Get-Location).Path 'ci-mode.json' }    
  if (Test-Path $ciModePath) {
    try { $ciMode = Get-Content $ciModePath -Raw | ConvertFrom-Json -ErrorAction Stop } catch { $ciMode = $null }
  }
} catch { $ciMode = $null }

$ciLabel = $null
if ($ciMode -and (Get-Prop $ciMode 'Label')) { $ciLabel = $ciMode.Label }
elseif ($env:CI_MODE_LABEL) { $ciLabel = $env:CI_MODE_LABEL }
else { $ciLabel = 'dev' }

$ciDiff = if ($ciMode -and (Get-Prop $ciMode 'DiffMode')) { $ciMode.DiffMode } else { if ($env:DIFF_MODE) { $env:DIFF_MODE } else { 'report' } }
$ciPssa = if ($ciMode -and (Get-Prop $ciMode 'PSSAMode')) { $ciMode.PSSAMode } else { if ($env:PSSA_MODE) { $env:PSSA_MODE } else { 'baseline' } }
$ciValidation = if ($ciMode -and (Get-Prop $ciMode 'ValidationMode')) { $ciMode.ValidationMode } else { if ($env:MANIFEST_VALIDATION_MODE) { $env:MANIFEST_VALIDATION_MODE } else { 'baseline' } }

Write-Host "[aggregator] CI mode = label=$ciLabel diff=$ciDiff pssa=$ciPssa validation=$ciValidation"

## Phase 1: index-first aggregation (authoritative)
function Normalize-RunRecord($r) {
  # Lossless normalization: preserve all existing properties emitted by ingestion
  # and return an ordered hashtable containing the same keys/values. This avoids
  # accidental dropping of metadata (e.g. runIdResolved, resolutionSource).
  $out = [ordered]@{}
  if ($null -eq $r) { return $out }
  try {
    foreach ($prop in $r.PSObject.Properties) {
      $out[$prop.Name] = $prop.Value
    }
    # Default: if no explicit runIdResolved flag was set upstream, assume this
    # record was produced from canonical/index ingestion and mark it resolved.
    if (-not $out.PSObject.Properties.Name -contains 'runIdResolved') { $out.runIdResolved = $true }
  } catch {
    # Fallback: ensure at least the runId is present (best-effort)
    if (Get-Prop $r 'runId') { $out.runId = Normalize-RunId (Get-Prop $r 'runId') }
  }
  return $out
}

function Compute-Diff($baselineArr, $currentArr) {
  $bmap = @{}
  foreach ($b in $baselineArr) {
    $bid = Get-CanonicalValue $b 'runId'
    $key = if (-not $bid -or [string]::IsNullOrWhiteSpace([string]$bid)) { 'unknown' } else { [string]$bid }
    $bmap[$key] = $b
  }
  $cmap = @{}
  foreach ($c in $currentArr) {
    $cid = Get-CanonicalValue $c 'runId'
    $key = if (-not $cid -or [string]::IsNullOrWhiteSpace([string]$cid)) { 'unknown' } else { [string]$cid }
    $cmap[$key] = $c
  }

  $newRuns = @(); $removed = @(); $regressions = @(); $improvements = @(); $unchanged = @()     

  # new and changed
  foreach ($runId in $cmap.Keys) {
    if (-not $bmap.ContainsKey($runId)) {
      $src = $cmap[$runId]
      $plainNew = [PSCustomObject]@{
        runId = Get-CanonicalValue $src 'runId'
        runIdResolved = if ((Get-CanonicalValue $src 'runIdResolved') -ne $null) { [bool](Get-CanonicalValue $src 'runIdResolved') } else { $false }
        manifestPath = Get-CanonicalValue $src 'manifestPath'
        source = if (Get-CanonicalValue $src 'source') { Get-CanonicalValue $src 'source' } else { 'unknown' }
        status = if (Get-CanonicalValue $src 'status') { (Get-CanonicalValue $src 'status').ToString().ToLower() } else { 'skipped' }
        artifacts = if (Get-CanonicalValue $src 'artifacts') { Get-CanonicalValue $src 'artifacts' } else { [ordered]@{ indexPath=$null; metadataPath=$null; validationPath=$null; pssaPath=$null; stepsPaths=@() } }
      }
      $newRuns += $plainNew
      continue
    }
    $cur = $cmap[$runId]; $base = $bmap[$runId]
    $entry = [ordered]@{ runId = $runId; statusChange = $null; pssaDelta = $null; validationDelta = $null }

    # status transition
    if ($base.status -ne $cur.status) { $entry.statusChange = "$($base.status) -> $($cur.status)" }

    # pssa delta: if both have findings arrays, compute counts
    $pDelta = [ordered]@{ baseline = $null; current = $null; diff = $null }
    try {
      $bfind = $null; $cfind = $null
      if ($base.pssa -and (Get-Prop $base.pssa 'findings')) { $bfind = @((Get-Prop $base.pssa 'findings')).Count } elseif ($base.pssa -and $base.pssa.PSObject.Properties.Name -contains 'findings') { $bfind = @($base.pssa.findings).Count }
      if ($cur.pssa -and (Get-Prop $cur.pssa 'findings')) { $cfind = @((Get-Prop $cur.pssa 'findings')).Count } elseif ($cur.pssa -and $cur.pssa.PSObject.Properties.Name -contains 'findings') { $cfind = @($cur.pssa.findings).Count }
      if ($bfind -ne $null -or $cfind -ne $null) { $pDelta.baseline = $bfind; $pDelta.current = $cfind; $pDelta.diff = (($cfind -as [int]) - ($bfind -as [int])) }
    } catch { }
    $entry.pssaDelta = $pDelta

    # validation delta: compare error counts if available in post
    $vDelta = [ordered]@{ baselineErrors = $null; currentErrors = $null; newErrors = @(); resolvedErrors = @() }
    try {
      $be = $null; $ce = $null
      if ($base.validation -and $base.validation.post -and (Get-Prop $base.validation.post 'errors')) { $be = @((Get-Prop $base.validation.post 'errors')).Count }
      if ($cur.validation -and $cur.validation.post -and (Get-Prop $cur.validation.post 'errors')) { $ce = @((Get-Prop $cur.validation.post 'errors')).Count }
      $vDelta.baselineErrors = $be; $vDelta.currentErrors = $ce
    } catch { }
    $entry.validationDelta = $vDelta

    # classification rules: regressions/improvements
    $isRegression = $false; $isImprovement = $false
    if ($entry.statusChange -and $entry.statusChange -match 'success -> failed') { $isRegression = $true }
    if ($entry.statusChange -and $entry.statusChange -match 'failed -> success') { $isImprovement = $true }
    if (-not $entry.statusChange -and ($entry.pssaDelta.diff -ne $null) -and ($entry.pssaDelta.diff -gt 0)) { $isRegression = $true }
    if (-not $entry.statusChange -and ($entry.pssaDelta.diff -ne $null) -and ($entry.pssaDelta.diff -lt 0)) { $isImprovement = $true }

    if ($isRegression) { $regressions += $entry } elseif ($isImprovement) { $improvements += $entry } else { $unchanged += $entry }
  }

  # removed runs
  foreach ($runId in $bmap.Keys) {
    if (-not $cmap.ContainsKey($runId)) {
      $src = $bmap[$runId]
      $plainRem = [PSCustomObject]@{
        runId = Get-CanonicalValue $src 'runId'
        runIdResolved = if ((Get-CanonicalValue $src 'runIdResolved') -ne $null) { [bool](Get-CanonicalValue $src 'runIdResolved') } else { $false }
        manifestPath = Get-CanonicalValue $src 'manifestPath'
        source = if (Get-CanonicalValue $src 'source') { Get-CanonicalValue $src 'source' } else { 'unknown' }
        status = if (Get-CanonicalValue $src 'status') { (Get-CanonicalValue $src 'status').ToString().ToLower() } else { 'skipped' }
        artifacts = if (Get-CanonicalValue $src 'artifacts') { Get-CanonicalValue $src 'artifacts' } else { [ordered]@{ indexPath=$null; metadataPath=$null; validationPath=$null; pssaPath=$null; stepsPaths=@() } }
      }
      $removed += $plainRem
    }
  }

  $summary = [ordered]@{
    new = $newRuns.Count
    removed = $removed.Count
    regressions = $regressions.Count
    improvements = $improvements.Count
    unchanged = $unchanged.Count
  }

  return [ordered]@{
    summary = $summary
    regressions = $regressions
    improvements = $improvements
    newRuns = $newRuns
    removedRuns = $removed
    unchanged = $unchanged
  }
}

# NOTE: Baseline diffing is executed after canonical runRecords are available
$runRecords = @()
$handledRunIds = @()
if (Test-Path $ArtifactsDir) {
  $indexFiles = Get-ChildItem -Path $ArtifactsDir -Recurse -Filter 'index.json' -File -ErrorAction SilentlyContinue
  $idxCount = 0
  try { $idxCount = (@($indexFiles)).Count } catch { $idxCount = 0 }
  Write-Host "[debug] indexFiles count = $idxCount"
  foreach ($idxFile in @($indexFiles)) {
    $idx = Read-JsonFile $idxFile.FullName
    if ($null -eq $idx) { continue }
    # Resolve canonical runId (index-first, schema-tolerant, fallback to parent folder)
    $parent = Split-Path -Parent $idxFile.FullName
    $parentLeaf = Split-Path -Leaf $parent
    $idxRunIdRaw = Get-CanonicalRunId $idx $parentLeaf
    $idxRunId = Normalize-RunId $idxRunIdRaw
    if ($idxRunId) { $handledRunIds += $idxRunId }
    Write-Host "[debug] idxRunId resolved from: '$idxRunId' file=$($idxFile.FullName)"

    # canonical artifact keys (always present, explicit null when missing)
    $metaPath = $null; $validationPath = $null; $pssaPath = $null; $stepsPaths = @()
    if (Get-Prop $idx 'artifacts') {
      $a = Get-Prop $idx 'artifacts'
      if (Get-Prop $a 'metadata') { $metaPath = Get-Prop $a 'metadata' }
      if (Get-Prop $a 'validation' -and @((Get-Prop $a 'validation')).Count -gt 0) { $validationPath = @((Get-Prop $a 'validation'))[0] }
      if (Get-Prop $a 'pssa' -and @((Get-Prop $a 'pssa')).Count -gt 0) { $pssaPath = @((Get-Prop $a 'pssa'))[0] }
      if (Get-Prop $a 'steps' -and @((Get-Prop $a 'steps')).Count -gt 0) { $stepsPaths = @((Get-Prop $a 'steps')) }
    }

    # status resolution: strict contract only (no guessing)
    $allowed = @('success','failed','skipped')
    $idxStatusRaw = Get-Prop $idx 'status'
    $idxStatus = if ($idxStatusRaw) { $idxStatusRaw.ToString().ToLower() } else { $null }       
    $idxManifest = Get-Prop $idx 'manifest'
    # reuse the schema-tolerant resolution performed earlier
    $reason = $null
    if ($TraceRunBuilder) {
      Write-Host "[trace-debug] idxFile=$($idxFile.FullName) idxRunIdRaw='$idxRunIdRaw' idxManifest='$idxManifest' idxStatus='$idxStatus' metaPath='$metaPath' validationPath='$validationPath'"
    }

    # Guard: if runId is missing or empty even after fallback, emit an explicit
    # unresolved record rather than silently dropping the data. This preserves
    # traceability while still marking the identity as unresolved.
    if (-not $idxRunId) {
      if ($TraceRunBuilder) {
        $evt = [ordered]@{ event = 'index_missing_runId'; stage = 'index-fallback'; path = $idxFile.FullName; manifest = $idxManifest; reason = 'missing_runId'; timestamp = (Get-Date).ToString('o') }
        Emit-TraceEvent $ArtifactsDir $evt
        Write-Host "[trace][runbuilder] index missing runId: $($idxFile.FullName) (emitting unresolved record)"
      } else {
        Write-Host "[warn] unresolved runId for index: $($idxFile.FullName) - emitting unresolved record"
      }

      $unresolved = [ordered]@{
        runId = 'unknown'
        runIdResolved = $false
        manifestPath = if ($idxManifest) { $idxManifest } else { $null }
        source = if (Get-Prop $idx 'source') { Get-Prop $idx 'source' } else { 'unknown' }
        status = 'skipped'
        attemptCount = 0
        reason = 'invalid_missing_runId_unresolved'
        artifacts = [ordered]@{
          indexPath = $idxFile.FullName
          metadataPath = $metaPath
          validationPath = $validationPath
          pssaPath = $pssaPath
          stepsPaths = $stepsPaths
        }
        validation = [ordered]@{ pre = $null; post = $null }
        pssa = $null
      }

      if ($TraceRunBuilder) {
        $evt2 = [ordered]@{ event = 'emit_unresolved_record'; stage = 'index-fallback'; runId = 'unknown'; indexPath = $idxFile.FullName; reason = 'invalid_missing_runId_unresolved'; timestamp = (Get-Date).ToString('o') }
        Emit-TraceEvent $ArtifactsDir $evt2
      }

      $runRecords += $unresolved
      continue
    }

    $invalidIndex = $false
    if (-not $idxRunIdRaw -or -not $idxManifest -or -not $idxStatus -or ($allowed -notcontains $idxStatus) -or -not $metaPath -or -not $validationPath) {
      $invalidIndex = $true
    }

    if ($invalidIndex -and -not $StrictContract) {
      Write-Host "[debug] invalidIndex true for index: $($idxFile.FullName)"
      # Non-strict mode: treat invalid or missing index as legacy run (do not fail)
      $legacyRunId = Normalize-RunId $idxRunId
      $legacy = [ordered]@{
        runId = Normalize-RunId $legacyRunId
        runIdResolved = $false
        manifestPath = if ($idxManifest) { $idxManifest } else { $null }
        source = if (Get-Prop $idx 'source') { Get-Prop $idx 'source' } else { 'unknown' }      
        status = 'skipped'
        attemptCount = 0
        reason = 'legacy_no_index_v1'
        artifacts = [ordered]@{
          indexPath = $idxFile.FullName
          metadataPath = $metaPath
          validationPath = $validationPath
          pssaPath = $pssaPath
          stepsPaths = $stepsPaths
        }
        validation = [ordered]@{ pre = $null; post = $null }
        pssa = $null
      }
      if ($TraceRunBuilder) {
        $evt = [ordered]@{ event = 'legacy_fallback'; stage = 'index-validate'; indexPath = $idxFile.FullName; runId = Normalize-RunId $legacyRunId; reason = 'invalid_index'; timestamp = (Get-Date).ToString('o') }
        Emit-TraceEvent $ArtifactsDir $evt
        Write-Host "[trace][runbuilder] legacy fallback for index (structured event emitted)"   
      }
      $runRecords += $legacy
      continue
    }

    # If strict mode or valid index, respect index values and apply strict sanity checks        
    if ($invalidIndex -and $StrictContract) {
      # prepare failure record under strict mode
      $status = 'failed'
      if (-not $idxStatus) { $reason = 'invalid_status_contract' }
      elseif ($allowed -notcontains $idxStatus) { $reason = 'invalid_status_contract' }
      else { $reason = 'incomplete_index_artifacts' }
    } else {
      $status = $idxStatus
    }

    $record = [ordered]@{
      # Use the resolved runId determined earlier and keep it immutable for this record
      runId = $idxRunId
      runIdResolved = $true
      manifestPath = if ($idxManifest) { $idxManifest } else { $null }
      source = if (Get-Prop $idx 'source') { Get-Prop $idx 'source' } else { 'unknown' }        
      status = [string]$status
      attemptCount = if (Get-Prop $idx 'attemptCount') { try { [int](Get-Prop $idx 'attemptCount') } catch { 0 } } else { 0 }
      reason = $reason
      artifacts = [ordered]@{
        indexPath = $idxFile.FullName
        metadataPath = $metaPath
        validationPath = $validationPath
        pssaPath = $pssaPath
        stepsPaths = $stepsPaths
      }
      validation = [ordered]@{ pre = $null; post = $null }
      pssa = $null
    }
    $runRecords += $record
  }
}

## Phase 2: filesystem fallback for runs without an index (back-compat)
$candidates = @()
if (Test-Path $ArtifactsDir) {
  $candidates += Get-ChildItem -Path $ArtifactsDir -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -in @('metadata.json','pssa-results.json') -or $_.Name -like 'validation-report*.json' }
}
try { $repoReports = Get-ChildItem -Path . -Recurse -Filter 'validation-report*.json' -File -ErrorAction SilentlyContinue; if ($repoReports) { $candidates += $repoReports } } catch { }        

foreach ($f in $candidates) {
  # determine runId by parent folder (normalize canonical runId)
  $rawFsRunId = Split-Path -Leaf (Split-Path -Parent $f.FullName)
  $runId = Normalize-RunId $rawFsRunId
  # skip candidates that do not yield a usable runId
  if (-not $runId) {
    if ($TraceRunBuilder) {
      $evt = [ordered]@{ event = 'filesystem_candidate_skipped'; stage = 'filesystem-fallback'; path = $f.FullName; rawParent = $rawFsRunId; reason = 'no_runId'; timestamp = (Get-Date).ToString('o') }
      Emit-TraceEvent $ArtifactsDir $evt
      Write-Host "[trace][runbuilder] filesystem candidate skipped (no usable runId): $($f.FullName)"
    }
    continue
  }
  if ($handledRunIds -contains $runId) { continue }
  # Build a minimal fallback run record and mark as skipped (best-effort)
    if (-not ($runRecords | Where-Object { $_.runId -eq $runId })) {
    $fallback = [ordered]@{
      runId = $runId
      runIdResolved = $false
      manifestPath = $null
      source = 'unknown'
      status = 'skipped'
      attemptCount = 0
      reason = $null
      artifacts = [ordered]@{
        indexPath = $null
        metadataPath = $null
        validationPath = $null
        pssaPath = $null
        stepsPaths = @()
      }
      validation = [ordered]@{ pre = $null; post = $null }
      pssa = $null
    }
    # mark as handled so we don't later add another fallback for same id
    $handledRunIds += $runId
    if ($StrictContract) { $fallback.reason = 'no_index_present' } else { $fallback.reason = 'legacy_no_index_v1' }
    # populate known artifact paths
    if ($f.Name -eq 'metadata.json') { $fallback.artifacts.metadataPath = $f.FullName }
    if ($f.Name -like 'validation-report*.json') { $fallback.artifacts.validationPath = $f.FullName }
    if ($f.Name -eq 'pssa-results.json') { $fallback.artifacts.pssaPath = $f.FullName }
    $runRecords += $fallback
  } else {
    # update existing fallback entry if necessary
    $entry = $runRecords | Where-Object { $_.runId -eq $runId }
    if ($f.Name -eq 'metadata.json') { $entry.artifacts.metadataPath = $f.FullName }
    if ($f.Name -like 'validation-report*.json') { $entry.artifacts.validationPath = $f.FullName }
    if ($f.Name -eq 'pssa-results.json') { $entry.artifacts.pssaPath = $f.FullName }
  }
}

# Normalize and finalize canonical run records
$finalRecords = @()
foreach ($r in $runRecords) {
  # ensure status is one of allowed values
  $allowed = @('success','failed','skipped')
  $statusVal = if ($r.status) { $r.status.ToString().ToLower() } else { 'failed' }
  if ($allowed -notcontains $statusVal) { $statusVal = 'failed' }

  # attemptCount normalization
  $attemptCountVal = 0
  if (Get-Prop $r 'attemptCount') { try { $attemptCountVal = [int](Get-Prop $r 'attemptCount') } catch { $attemptCountVal = 0 } }

  # ensure artifact keys exist and are explicit
  $art = [ordered]@{
    indexPath = $null
    metadataPath = $null
    validationPath = $null
    pssaPath = $null
    stepsPaths = @()
  }
  if (Get-Prop $r 'artifacts') {
    $artObj = Get-Prop $r 'artifacts'
    if (Get-Prop $artObj 'indexPath') { $art.indexPath = [string](Get-Prop $artObj 'indexPath') }
    if (Get-Prop $artObj 'metadataPath') { $art.metadataPath = [string](Get-Prop $artObj 'metadataPath') }
    if (Get-Prop $artObj 'validationPath') { $art.validationPath = [string](Get-Prop $artObj 'validationPath') }
    if (Get-Prop $artObj 'pssaPath') { $art.pssaPath = [string](Get-Prop $artObj 'pssaPath') }  
    if (Get-Prop $artObj 'stepsPaths') { $art.stepsPaths = @((Get-Prop $artObj 'stepsPaths')) } 
  }

  $validationVal = [ordered]@{ pre = $null; post = $null }
  $valObj = Get-Prop $r 'validation'
  if ($valObj) {
    if (Get-Prop $valObj 'pre') { $validationVal.pre = (Get-Prop $valObj 'pre' | Select-Object -Property *) }
    if (Get-Prop $valObj 'post') { $validationVal.post = (Get-Prop $valObj 'post' | Select-Object -Property *) }
  }

  $pssaVal = $null
  if (Get-Prop $r 'pssa') { $pssaVal = (Get-Prop $r 'pssa' | Select-Object -Property *) }       

  # Normalize the input record losslessly and treat this function as the
  # authoritative source of truth for record shape. This avoids re-creating
  # the object from scratch and accidentally dropping provenance metadata
  # such as `runIdResolved`.
  $record = Normalize-RunRecord $r

  # Ensure canonical fields are present and normalized (do not overwrite
  # `runId` or `runIdResolved` when already present).
  $record.status = $statusVal
  $record.attemptCount = $attemptCountVal
  $record.attemptHistory = if (Get-Prop $record 'attemptHistory') { Get-Prop $record 'attemptHistory' } else { @() }
  if (-not (Get-Prop $record 'reason')) { $record.reason = $null }
  if (-not (Get-Prop $record 'validation')) { $record.validation = $validationVal } else {
    if (-not (Get-Prop $record.validation 'pre')) { $record.validation.pre = $validationVal.pre }
    if (-not (Get-Prop $record.validation 'post')) { $record.validation.post = $validationVal.post }
  }
  if (-not (Get-Prop $record 'pssa')) { $record.pssa = $pssaVal }

  # Ensure canonical artifact structure exists and preserve any existing
  # artifact fields emitted earlier.
  if (-not (Get-Prop $record 'artifacts')) { $record.artifacts = $art } else {
    $artObj = Get-Prop $record 'artifacts'
    if (-not (Get-Prop $artObj 'indexPath')) { $artObj.indexPath = $art.indexPath }
    if (-not (Get-Prop $artObj 'metadataPath')) { $artObj.metadataPath = $art.metadataPath }
    if (-not (Get-Prop $artObj 'validationPath')) { $artObj.validationPath = $art.validationPath }
    if (-not (Get-Prop $artObj 'pssaPath')) { $artObj.pssaPath = $art.pssaPath }
    if (-not (Get-Prop $artObj 'stepsPaths')) { $artObj.stepsPaths = $art.stepsPaths }
    $record.artifacts = $artObj
  }

  # Final validation: ensure runId is present; if not, set explicit unresolved marker
  # attempt to recover runId from nested SyncRoot (some PSObject shapes embed original values)
  if (-not (Get-Prop $record 'runId')) {
    if ($record.PSObject.Properties.Name -contains 'SyncRoot') {
      try {
        $sr = $record.SyncRoot
        if ($sr -and $sr.PSObject.Properties.Name -contains 'runId') { $record.runId = Normalize-RunId $sr.runId }
      } catch { }
    }
  }

  if (-not (Get-Prop $record 'runId') -or [string]::IsNullOrWhiteSpace([string](Get-Prop $record 'runId'))) {
    $record.runId = 'unknown'
    if (-not (Get-Prop $record 'reason')) { $record.reason = 'invalid_missing_runId' }
    $record.status = 'skipped'
    if (-not (Get-Prop $record 'manifestPath')) { $record.manifestPath = $null }
    if (-not (Get-Prop $record 'source')) { $record.source = 'unknown' }
    # Preserve explicit unresolved flag only if not present
    if (-not (Get-Prop $record 'runIdResolved')) { $record.runIdResolved = $false }
  }

  $finalRecords += $record
}

$runRecords = $finalRecords

# Final sanitization pass: create brand-new plain objects per record to avoid
# any ambiguity from mixed PSObject/hashtable shapes. Always prefer values
# from nested SyncRoot (authoritative) when present, otherwise fall back to
# top-level properties. This guarantees deterministic serialization.
function Get-CanonicalValue($r, $name) {
  try {
    # Try direct nested access first (works for PSObjects and OrderedDictionary-like objects)
    try {
      if ($r -ne $null) {
        $sr = $null
        try { $sr = $r.SyncRoot } catch { $sr = $null }
        if ($sr -ne $null) {
          try {
            $v = $sr.$name
            if ($v -ne $null) { return $v }
          } catch { }
        }
        # Try top-level direct property access
        try {
          $tv = $r.$name
          if ($tv -ne $null) { return $tv }
        } catch { }
      }
    } catch { }
    # Fallback to property introspection helper
    return Get-Prop $r $name
  } catch { return $null }
}

$cleanRecords = @()
foreach ($r in $runRecords) {
  $artObj = Get-CanonicalValue $r 'artifacts'
  $cleanArt = [ordered]@{
    indexPath = if ($artObj -and (Get-Prop $artObj 'indexPath')) { Get-Prop $artObj 'indexPath' } else { $null }
    metadataPath = if ($artObj -and (Get-Prop $artObj 'metadataPath')) { Get-Prop $artObj 'metadataPath' } else { $null }
    validationPath = if ($artObj -and (Get-Prop $artObj 'validationPath')) { Get-Prop $artObj 'validationPath' } else { $null }
    pssaPath = if ($artObj -and (Get-Prop $artObj 'pssaPath')) { Get-Prop $artObj 'pssaPath' } else { $null }
    stepsPaths = if ($artObj -and (Get-Prop $artObj 'stepsPaths')) { @((Get-Prop $artObj 'stepsPaths')) } else { @() }
  }

  $runId = Normalize-RunId (Get-CanonicalValue $r 'runId')
  $runIdResolved = Get-CanonicalValue $r 'runIdResolved'
  if ($runIdResolved -eq $null) { $runIdResolved = $false }

  $clean = [ordered]@{
    runId = if ($runId) { $runId } else { 'unknown' }
    runIdResolved = [bool]$runIdResolved
    manifestPath = Get-CanonicalValue $r 'manifestPath'
    source = if (Get-CanonicalValue $r 'source') { Get-CanonicalValue $r 'source' } else { 'unknown' }
    status = if (Get-CanonicalValue $r 'status') { (Get-CanonicalValue $r 'status').ToString().ToLower() } else { 'skipped' }
    attemptCount = if ((Get-CanonicalValue $r 'attemptCount') -ne $null) { try { [int](Get-CanonicalValue $r 'attemptCount') } catch { 0 } } else { 0 }
    attemptHistory = if (Get-CanonicalValue $r 'attemptHistory') { Get-CanonicalValue $r 'attemptHistory' } else { @() }
    reason = if (Get-CanonicalValue $r 'reason') { Get-CanonicalValue $r 'reason' } else { $null }
    artifacts = $cleanArt
    validation = if (Get-CanonicalValue $r 'validation') { Get-CanonicalValue $r 'validation' } else { [ordered]@{ pre = $null; post = $null } }
    pssa = if (Get-CanonicalValue $r 'pssa') { Get-CanonicalValue $r 'pssa' } else { $null }
  }

  $cleanRecords += $clean
}

# Replace runRecords with the clean projection for final serialization
$runRecords = $cleanRecords

# Invariant checks: fail fast if we detect regressions that violate contract
$badResolvedUnknown = @($runRecords | Where-Object { $_.runId -eq 'unknown' -and $_.runIdResolved -eq $true })
if ($badResolvedUnknown.Count -gt 0) {
  Write-Host "::error::Invariant violation: resolved record(s) with unknown runId detected: $($badResolvedUnknown.Count)"
  throw "Invariant violation: resolved record has unknown runId"
}
$missingResolved = @($runRecords | Where-Object { -not $_.PSObject.Properties.Name -contains 'runIdResolved' })
if ($missingResolved.Count -gt 0) {
  Write-Host "::error::Invariant violation: missing runIdResolved on $($missingResolved.Count) record(s)"
  throw "Invariant violation: missing runIdResolved"
}

# Debug dump mode: emit pre/post snapshots and simple diagnostics to the artifacts directory
if ($DebugDump) {
  try {
    $prePath = Join-Path -Path $ArtifactsDir -ChildPath 'pre-normalize.json'
    ($runRecords | ConvertTo-Json -Depth 10) | Set-Content -Path $prePath -Encoding UTF8 -Force
  } catch { Write-Host "[debug-dump] failed to write pre-normalize: $($_.Exception.Message)" }

  try {
    $postPath = Join-Path -Path $ArtifactsDir -ChildPath 'post-normalize.json'
    ($finalRecords | ConvertTo-Json -Depth 10) | Set-Content -Path $postPath -Encoding UTF8 -Force
  } catch { Write-Host "[debug-dump] failed to write post-normalize: $($_.Exception.Message)" }

  try {
    $missing = @($finalRecords | Where-Object { -not $_.PSObject.Properties.Name -contains 'runIdResolved' }).Count
    $unknownTrue = @($finalRecords | Where-Object { $_.runId -eq 'unknown' -and $_.runIdResolved -eq $true }).Count
    $realFalse = @($finalRecords | Where-Object { $_.runId -ne 'unknown' -and $_.runIdResolved -eq $false }).Count
    $diag = [ordered]@{ missingRunIdResolved = $missing; unknownWithTrue = $unknownTrue; realWithFalse = $realFalse }
    $diagPath = Join-Path -Path $ArtifactsDir -ChildPath 'finalization-diagnostics.json'
    ($diag | ConvertTo-Json -Depth 5) | Set-Content -Path $diagPath -Encoding UTF8 -Force
    Write-Host "[debug-dump] Wrote diagnostics to: $diagPath"
  } catch { Write-Host "[debug-dump] failed to write diagnostics: $($_.Exception.Message)" }
}

if ($StrictContract) {
  # Run the external schema validator (keeps single source of truth)
  $tmp = Join-Path -Path $env:TEMP -ChildPath ("runrecord-" + [guid]::NewGuid().ToString() + ".json")
  ($runRecords | ConvertTo-Json -Depth 10) | Set-Content -Path $tmp -Encoding UTF8 -Force       
  Write-Host "[aggregator] Strict contract enabled: validating using tools/ci/Test-RunRecordSchema.ps1"
  $validator = Join-Path -Path (Split-Path -Parent $MyInvocation.MyCommand.Definition) -ChildPath 'Test-RunRecordSchema.ps1'
  if (-not (Test-Path $validator)) {
    Write-Host "::error::Schema validator not found: $validator"
    exit 1
  }
  & pwsh -NoProfile -File $validator -InputJson $tmp
  if ($LASTEXITCODE -ne 0) {
    Write-Host "::error::RunRecord schema validation failed (strict mode)"
    exit $LASTEXITCODE
  }
  Remove-Item -Path $tmp -Force -ErrorAction SilentlyContinue
} else {
  Write-Host '[aggregator] Non-strict mode: legacy runs will be included as skipped (reason=legacy_no_index_v1)'
}

  ## If baseline provided, compute diff against canonicalized records
  if ($BaselinePath) {
    Write-Host "[aggregator] Baseline requested: $BaselinePath"
    $baseline = $null
    try { $baseline = Read-JsonFile $BaselinePath } catch { $baseline = $null }
    if (-not $baseline) {
      Write-Host "[aggregator] Baseline invalid or missing: treating all current runs as new"   
      $baselineArr = @()
    } else {
      $baselineArr = @()
      foreach ($b in @($baseline)) { $baselineArr += Normalize-RunRecord $b }
    }

    $currentArr = @()
    foreach ($c in @($runRecords)) { $currentArr += Normalize-RunRecord $c }

    $diff = Compute-Diff $baselineArr $currentArr
    $diffOut = 'manifest-run-diff.json'
    ($diff | ConvertTo-Json -Depth 10) | Set-Content -Path $diffOut -Encoding UTF8 -Force       
    Write-Host "[aggregator] Wrote diff artifact: $diffOut"
  }

  # Write canonical JSON array only
  ($runRecords | ConvertTo-Json -Depth 10) | Set-Content -Path $OutputJson -Encoding UTF8 -Force
  Write-Host "Wrote canonical run records: $OutputJson"

  Write-Host '[aggregator] Complete.'
