param(
  [string]$ArtifactsDir = '.github/artifacts',
  [string]$OutputJson = 'manifest-run-summary.json',
  [switch]$StrictContract,
  [switch]$TraceRunBuilder,
  [string]$BaselinePath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Read-JsonFile($path) {
  try { return Get-Content $path -Raw | ConvertFrom-Json -ErrorAction Stop } catch { return $null }
}

# Normalize runId canonicalization in one place
function Normalize-RunId($id) {
  if ($null -eq $id) { return 'unknown' }
  try {
    $s = $id.ToString()
    if ([string]::IsNullOrWhiteSpace($s)) { return 'unknown' }
    return $s.Trim()
  } catch { return 'unknown' }
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
  $out = [ordered]@{}
  $tmpRunIdVal = $null
  if (Get-Prop $r 'runId') { $tmpRunIdVal = Get-Prop $r 'runId' }
  $out.runId = Normalize-RunId $tmpRunIdVal
  $out.manifestPath = if (Get-Prop $r 'manifestPath') { [string](Get-Prop $r 'manifestPath') } else { $null }
  $out.source = if (Get-Prop $r 'source') { [string](Get-Prop $r 'source') } else { 'unknown' } 
  $s = if (Get-Prop $r 'status') { [string](Get-Prop $r 'status').ToLower() } else { $null }    
  $allowed = @('success','failed','skipped')
  if ($s -and ($allowed -contains $s)) { $out.status = $s } else { $out.status = 'skipped' }    
  $out.attemptCount = if (Get-Prop $r 'attemptCount') { try { [int](Get-Prop $r 'attemptCount') } catch { 0 } } else { 0 }
  $out.attemptHistory = if (Get-Prop $r 'attemptHistory') { @((Get-Prop $r 'attemptHistory')) } else { @() }
  $out.reason = if (Get-Prop $r 'reason') { (Get-Prop $r 'reason') } else { $null }

  $art = [ordered]@{
    indexPath = $null; metadataPath = $null; validationPath = $null; pssaPath = $null; stepsPaths = @()
  }
  if (Get-Prop $r 'artifacts') {
    $artObj = Get-Prop $r 'artifacts'
    $art.indexPath = if (Get-Prop $artObj 'indexPath') { [string](Get-Prop $artObj 'indexPath') } else { $null }
    $art.metadataPath = if (Get-Prop $artObj 'metadataPath') { [string](Get-Prop $artObj 'metadataPath') } else { $null }
    $art.validationPath = if (Get-Prop $artObj 'validationPath') { [string](Get-Prop $artObj 'validationPath') } else { $null }
    $art.pssaPath = if (Get-Prop $artObj 'pssaPath') { [string](Get-Prop $artObj 'pssaPath') } else { $null }
    $art.stepsPaths = if (Get-Prop $artObj 'stepsPaths') { @((Get-Prop $artObj 'stepsPaths')) } else { @() }
  }
  $out.artifacts = $art

  # Normalized validation/post fields when present
  $val = [ordered]@{ pre = $null; post = $null }
  $valObj = Get-Prop $r 'validation'
  if ($valObj) {
    if (Get-Prop $valObj 'pre') { $val.pre = (Get-Prop $valObj 'pre' | Select-Object -Property *) }
    if (Get-Prop $valObj 'post') { $val.post = (Get-Prop $valObj 'post' | Select-Object -Property *) }
  }
  $out.validation = $val

  # pssa normalization: attempt to surface a findings array if present
  $pssaVal = $null
  if (Get-Prop $r 'pssa') {
    $ps = Get-Prop $r 'pssa'
    $pssaVal = $ps
  }
  $out.pssa = $pssaVal

  return $out
}

function Compute-Diff($baselineArr, $currentArr) {
  $bmap = @{}
  foreach ($b in $baselineArr) { $bmap[$b.runId] = $b }
  $cmap = @{}
  foreach ($c in $currentArr) { $cmap[$c.runId] = $c }

  $newRuns = @(); $removed = @(); $regressions = @(); $improvements = @(); $unchanged = @()     

  # new and changed
  foreach ($runId in $cmap.Keys) {
    if (-not $bmap.ContainsKey($runId)) {
      $newRuns += $cmap[$runId]
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
    if (-not $cmap.ContainsKey($runId)) { $removed += $bmap[$runId] }
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
    $rawRunId = if (Get-Prop $idx 'runId') { Get-Prop $idx 'runId' } else { Split-Path -Leaf (Split-Path -Parent $idxFile.FullName) }
    $runId = Normalize-RunId $rawRunId
    $handledRunIds += $runId

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
    $idxRunIdRaw = Get-Prop $idx 'runId'
    $idxRunId = Normalize-RunId $idxRunIdRaw
    $reason = $null
    if ($TraceRunBuilder) {
      Write-Host "[trace-debug] idxFile=$($idxFile.FullName) idxRunIdRaw='$idxRunIdRaw' idxManifest='$idxManifest' idxStatus='$idxStatus' metaPath='$metaPath' validationPath='$validationPath'"
    }

    # Guard: if runId is missing or empty even after fallback, emit an explicit skipped record and continue
    if ($idxRunId -eq 'unknown') {
      $src = if (Get-Prop $idx 'source') { Get-Prop $idx 'source' } else { 'unknown' }
      if ($TraceRunBuilder) {
        $evt = [ordered]@{ event = 'index_missing_runId'; stage = 'index-fallback'; path = $idxFile.FullName; manifest = $idxManifest; source = $src; reason = 'missing_runId'; timestamp = (Get-Date).ToString('o') }
        Emit-TraceEvent $ArtifactsDir $evt
        Write-Host "[trace][runbuilder] index missing runId: $($idxFile.FullName) (structured event emitted)"
      }
      $bad = [ordered]@{
        runId = 'unknown'
        manifestPath = if ($idxManifest) { $idxManifest } else { $null }
        source = if (Get-Prop $idx 'source') { Get-Prop $idx 'source' } else { 'unknown' }      
        status = 'skipped'
        attemptCount = 0
        reason = 'invalid_missing_runId'
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
        $evt2 = [ordered]@{ event = 'emit_skipped_record'; stage = 'index-fallback'; runId = 'unknown'; indexPath = $idxFile.FullName; reason = 'invalid_missing_runId'; timestamp = (Get-Date).ToString('o') }
        Emit-TraceEvent $ArtifactsDir $evt2
        Write-Host "[trace][runbuilder] emitted skipped record for missing runId (structured event emitted)"
      }
      $runRecords += $bad
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
      runId = Normalize-RunId $idxRunId
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
  if ($TraceRunBuilder -and $rawFsRunId -and [string]::IsNullOrWhiteSpace($rawFsRunId)) {       
    $evt = [ordered]@{ event = 'filesystem_candidate_empty_parent'; stage = 'filesystem-fallback'; path = $f.FullName; reason = 'empty_parent'; timestamp = (Get-Date).ToString('o') }
    Emit-TraceEvent $ArtifactsDir $evt
    Write-Host "[trace][runbuilder] filesystem candidate had empty parent; normalized to 'unknown' (structured event emitted)"
  }
  if ($handledRunIds -contains $runId) { continue }
  # Build a minimal fallback run record and mark as skipped (best-effort)
    if (-not ($runRecords | Where-Object { $_.runId -eq $runId })) {
    $fallback = [ordered]@{
      runId = Normalize-RunId $runId
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

  $attemptHistoryVal = @()
  $ahRaw = Get-Prop $r 'attemptHistory'
  if ($ahRaw) {
    foreach ($ah in @($ahRaw)) {
      if ($ah -eq $null) { continue }
      $attemptHistoryVal += [ordered]@{
        attempt = (Get-Prop $ah 'attempt')
        reason = (Get-Prop $ah 'reason')
        exitCode = (Get-Prop $ah 'exitCode')
        timestamp = (Get-Prop $ah 'timestamp')
        errors = @(@(Get-Prop $ah 'errors'))[0]
        stepsCount = (@(Get-Prop $ah 'steps')).Count
      }
    }
  }

  $record = [ordered]@{
    runId = Normalize-RunId((Get-Prop $r 'runId'))
    manifestPath = if (Get-Prop $r 'manifestPath') { [string](Get-Prop $r 'manifestPath') } else { $null }
    source = if (Get-Prop $r 'source') { [string](Get-Prop $r 'source') } else { 'unknown' }    
    status = $statusVal
    attemptCount = $attemptCountVal
    attemptHistory = $attemptHistoryVal
    reason = if (Get-Prop $r 'reason') { (Get-Prop $r 'reason') } else { $null }
    artifacts = $art
    validation = $validationVal
    pssa = $pssaVal
  }

  # Final validation: ensure runId is present; if not, convert to an explicit skipped record    
  if ([string]::IsNullOrWhiteSpace($record.runId)) {
    $record.runId = 'unknown'
    if (-not $record.reason) { $record.reason = 'invalid_missing_runId' }
    $record.status = 'skipped'
    if (-not $record.manifestPath) { $record.manifestPath = $null }
    if (-not $record.source) { $record.source = 'unknown' }
  }

  $finalRecords += $record
}

$runRecords = $finalRecords

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
