param(
    [string]$ArtifactsDir = 'artifacts',
    [string]$OutputJson = 'manifest-run-summary.json',
    [string]$DiffJson = 'manifest-run-diff.json',
    [switch]$WriteBaseline,
    [string]$BaselinePath = '',
    [switch]$TraceRunBuilder
)

function Normalize-RunId($id) {
    if ($null -eq $id) { return 'unknown' }
    $s = [string]$id
    if ([string]::IsNullOrWhiteSpace($s)) { return 'unknown' }
    return $s
}

function Normalize-Status($s) {
    if ($null -eq $s) { return 'unknown' }
    $t = $s.ToString().ToLower()
    switch ($t) {
        'success' { return 'success' }
        'ok' { return 'success' }
        'passed' { return 'success' }
        'failed' { return 'failed' }
        'error' { return 'failed' }
        'skipped' { return 'skipped' }
        'unknown' { return 'unknown' }
        default { return $t }
    }
}

function Resolve-ManifestPath($path) {
    if (-not $path) { return $null }
    # If already absolute, return as-is
    try {
        $p = [string]$path
        if ([System.IO.Path]::IsPathRooted($p)) { return $p }
        # try resolve relative to current working directory
        $candidate = Join-Path (Get-Location).Path $p
        if (Test-Path $candidate) { return (Resolve-Path $candidate).Path }
        # try resolve relative to artifacts dir
        $candidate2 = Join-Path (Resolve-Path -LiteralPath $ArtifactsDir).Path $p
        if (Test-Path $candidate2) { return (Resolve-Path $candidate2).Path }
        return $p
    } catch { return $path }
}

function Write-AtomicJson($path, $obj) {
    $tmp = "$path.tmp.$([System.Guid]::NewGuid().ToString())"
    $json = $obj | ConvertTo-Json -Depth 10 -Compress
    Write-Host "[aggregator-debug] json length = $($json.Length)"
    if ($json.Length -gt 200) { Write-Host "[aggregator-debug] json preview = $($json.Substring(0,200))..." }
    $dir = Split-Path -Parent $path
    if (-not [string]::IsNullOrWhiteSpace($dir) -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $json | Out-File -FilePath $tmp -Encoding UTF8 -Force
    Move-Item -Path $tmp -Destination $path -Force
}

function Read-JsonSafe($path) {
    if (-not (Test-Path $path)) {
        Write-Host "[aggregator] Missing file: $path"
        return $null
    }
    try {
        return Get-Content $path -Raw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        Write-Host "[aggregator] JSON parse failed: $path"
        Write-Host ($_ | Out-String)
        try { $global:AGGREGATOR_ERRORS += "[json-parse] $path :: $($_.Exception.Message)" } catch { }
        return $null
    }
}

Write-Host "[aggregator] ArtifactsDir = $ArtifactsDir"
$global:AGGREGATOR_ERRORS = @()

if (-not (Test-Path $ArtifactsDir)) {
    Write-Host "[aggregator] Artifacts directory '$ArtifactsDir' not found; emitting empty outputs"
    $runMap = @{}
} else {
    Write-Host "[aggregator] === ARTIFACT TREE ==="
    Get-ChildItem -Path $ArtifactsDir -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object { Write-Host $_.FullName }
    Write-Host "[aggregator] === END TREE ==="

    # Discover candidate run directories: direct children plus parents of any metadata.json found recursively
    $runDirs = @()
    $childDirs = Get-ChildItem -Path $ArtifactsDir -Directory -ErrorAction SilentlyContinue
    if ($childDirs) { $runDirs += $childDirs }

    $metaFiles = Get-ChildItem -Path $ArtifactsDir -Recurse -Filter 'metadata.json' -ErrorAction SilentlyContinue
    if ($metaFiles) {
        foreach ($mf in $metaFiles) {
            $p = Split-Path -Parent $mf.FullName
            if (-not ($runDirs | Where-Object { $_.FullName -eq $p })) {
                try { $runDirs += Get-Item -LiteralPath $p } catch { }
            }
        }
    }

    Write-Host "[aggregator] Found $($runDirs.Count) candidate run directories under $ArtifactsDir"

    $runMap = @{}
    function Merge-RunRecord {
        param(
            [hashtable]$Existing,
            [hashtable]$Incoming
        )

        if (-not $Existing) { return $Incoming }
        if (-not $Incoming) { return $Existing }

        # Prefer successful execution metadata
        if ($Incoming.status -eq 'success') { $Existing.status = 'success' }

        # Merge artifacts deterministically (prefer run-* over others)
        $incomingIsRun = $false
        $existingIsRun = $false
        try { if ($Incoming.artifacts.metadataPath -match "[/\\]run-") { $incomingIsRun = $true } } catch {}
        try { if ($Existing.artifacts.metadataPath -match "[/\\]run-") { $existingIsRun = $true } } catch {}

        if ($incomingIsRun -and -not $existingIsRun) {
            $Existing.artifacts = $Incoming.artifacts
        }
        elseif ($incomingIsRun -eq $existingIsRun) {
            foreach ($k in $Incoming.artifacts.Keys) {
                if (-not $Existing.artifacts[$k]) { $Existing.artifacts[$k] = $Incoming.artifacts[$k] }
            }
        }

        # Merge attempt counts and histories
        $Existing.attemptCount = [math]::Max([int]$Existing.attemptCount, [int]$Incoming.attemptCount)
        $Existing.attemptHistory = @(@($Existing.attemptHistory) + @($Incoming.attemptHistory)) | Select-Object -Unique

        # Choose status deterministically: prefer failure if present, then success
        $Existing.status = Choose-Status $Existing.status $Incoming.status

        return $Existing
    }

    foreach ($item in $runDirs) {
        $dir = $item.FullName
        Write-Host "[aggregator] Processing run dir: $dir"
        try {
            $indexPath = Join-Path $dir 'index.json'
            $metadataPath = Join-Path $dir 'metadata.json'
            $listingPath = Join-Path $dir 'listing.json'

            $runId = $null
            $manifestPath = $null
            $status = 'skipped'
            $attemptCount = 0
            $attemptHistory = @()

            $meta = Read-JsonSafe $metadataPath
            if ($meta) {
                if ($meta.runId) { $runId = $meta.runId }
                if ($meta.manifest) { $manifestPath = $meta.manifest }
                if ($meta.status) { $status = $meta.status }
                if ($meta.attemptCount) { $attemptCount = $meta.attemptCount }
                if ($meta.attemptHistory) { $attemptHistory = $meta.attemptHistory }
            }

            # fallback: status.txt
            $statusFile = Join-Path $dir 'status.txt'
            if ($status -in @('skipped','unknown') -and (Test-Path $statusFile)) {
                try { $s = (Get-Content -Path $statusFile -Raw).Trim(); if ($s) { $status = $s } } catch { try { $global:AGGREGATOR_ERRORS += "[status-read] $statusFile :: $($_.Exception.Message)" } catch { } }
            }

            # fallback: folder name
            if (-not $runId) { $name = Split-Path -Leaf $dir; if ($name) { $runId = $name } }
            $runId = Normalize-RunId $runId

            # compute artifact absolute paths safely
            $indexRel = $null
            if (Test-Path $indexPath) { $indexRel = (Resolve-Path $indexPath).Path }
            $metaRel = $null
            if (Test-Path $metadataPath) { $metaRel = (Resolve-Path $metadataPath).Path }
            $valPath = Join-Path $dir 'validation-report.json'
            $valRel = $null
            if (Test-Path $valPath) { $valRel = (Resolve-Path $valPath).Path }

            # normalize manifest path to absolute when possible
            $manifestResolved = $null
            if ($manifestPath) { $manifestResolved = Resolve-ManifestPath $manifestPath }

            $artifacts = [ordered]@{
                indexPath = $indexRel
                metadataPath = $metaRel
                validationPath = $valRel
                pssaPath = $null
                stepsPaths = @()
            }

            # normalize status and use resolved manifest when helpful
            $status = Normalize-Status $status
            $record = [ordered]@{
                runId = $runId
                manifestPath = $manifestResolved ? $manifestResolved : $manifestPath
                source = 'unknown'
                status = $status
                attemptCount = $attemptCount
                attemptHistory = $attemptHistory
                reason = $null
                artifacts = $artifacts
                validation = [ordered]@{ pre = $null; post = $null }
                pssa = $null
            }

            # Only include real execution runs: status indicates execution OR manifest path exists
            $isExecution = $false
            if ($record.status -in @('success','failed')) { $isExecution = $true }
            if (-not $isExecution -and $record.manifestPath -and -not [string]::IsNullOrWhiteSpace($record.manifestPath)) {
                $isExecution = $true
            }

            if (-not $isExecution) {
                Write-Host "[aggregator] Skipping non-execution run: $runId (status=$status manifest=$manifestPath)"
                continue
            }

            # Ensure runId is present and normalized
            $record.runId = Normalize-RunId $record.runId

            # prefer absolute artifact paths when available
            if ($artifacts.indexPath) { $record.artifacts.indexPath = $artifacts.indexPath }
            if ($artifacts.metadataPath) { $record.artifacts.metadataPath = $artifacts.metadataPath }
            if ($artifacts.validationPath) { $record.artifacts.validationPath = $artifacts.validationPath }

            $rid = $record.runId
            if (-not $runMap.ContainsKey($rid)) {
                $runMap[$rid] = $record
            } else {
                $runMap[$rid] = Merge-RunRecord -Existing $runMap[$rid] -Incoming $record
            }
        } catch {
            Write-Host "[aggregator] Failed processing run dir $dir"
            Write-Host ($_ | Out-String)
            $global:AGGREGATOR_ERRORS += ($_ | Out-String)
            continue
        }
    }
}

Write-Host "[aggregator] Merged runs were accumulated during collection; verifying uniqueness and flattening map"

function Choose-Status($a, $b) {
    $priority = @('failed','success','ok','skipped','unknown')
    foreach ($p in $priority) {
        if (($a -and ($a -eq $p)) -or ($b -and ($b -eq $p))) { return $p }
    }
    if ($a) { return $a }
    return $b
}

# Sanity check: duplicate runIds after merge should be impossible because keys are unique.
$duplicateIds = $runMap.Keys | Group-Object | Where-Object { $_.Count -gt 1 }

if ($duplicateIds) {
    Write-Host "[aggregator] ERROR: duplicate runIds detected after merge (this should be impossible)"
    $duplicateIds | ForEach-Object { Write-Host "-- $($_.Name) count=$($_.Count)" }
    exit 2
}

# Flatten map to array and ensure deterministic ordering by runId
$runs = @($runMap.Values) | Sort-Object -Property @{ Expression = { if ($_.runId) { $_.runId } else { 'zzz-unknown' } } }

# Build a stable summary object (always an object, never an array)
Write-Host "[aggregator] runs count = $($runs.Count)"

# Compute passed/failed counts deterministically
$passed = ($runs | Where-Object { $_.status -in @('success','ok','passed') }).Count
$failed = ($runs | Where-Object { $_.status -eq 'failed' }).Count
$failedRunIds = @($runs | Where-Object { $_.status -eq 'failed' } | ForEach-Object { $_.runId })

$summaryObj = [ordered]@{
    passed = $passed
    failed = $failed
    total  = @($runs).Count
    failedRuns = $failedRunIds
    runs   = @($runs)
    pssa = [ordered]@{ newFindings = 0; existingFindings = 0; resolvedFindings = 0; topFiles = @(); newSamples = @() }
    errors = $global:AGGREGATOR_ERRORS
    timestamp = (Get-Date).ToString('o')
}

Write-Host "[aggregator] Summary => passed=$($summaryObj.passed) failed=$($summaryObj.failed) total=$($summaryObj.total)"
Write-AtomicJson -path $OutputJson -obj $summaryObj
Write-Host "[aggregator] Wrote canonical run records: $OutputJson"

# Build a simple diff artifact that references the runs (no null runIds)
$diff = [ordered]@{
    summary = [ordered]@{ new = $runs.Count; removed = 0; regressions = 0; improvements = 0; unchanged = 0 }
    regressions = @()
    improvements = @()
    newRuns = @()
    removedRuns = @()
    unchanged = @()
}

foreach ($r in $runs) {
    $rid = Normalize-RunId $r.runId
    $nr = [ordered]@{
        runId = $rid
        manifestPath = $r.manifestPath
        source = $r.source
        status = $r.status
        attemptCount = $r.attemptCount
        attemptHistory = $r.attemptHistory
        reason = $r.reason
        artifacts = $r.artifacts
        validation = $r.validation
        pssa = $r.pssa
    }
    $diff.newRuns += $nr
}

Write-Host "[aggregator] Wrote diff artifact: $DiffJson"
Write-AtomicJson -path $DiffJson -obj $diff
