param(
    [string]$ArtifactsDir = 'artifacts',
    [string]$OutputJson = 'manifest-run-summary.json',
    [string]$DiffJson = 'manifest-run-diff.json',
    [switch]$WriteBaseline
)

function Normalize-RunId($id) {
    if ($null -eq $id) { return 'unknown' }
    $s = [string]$id
    if ([string]::IsNullOrWhiteSpace($s)) { return 'unknown' }
    return $s
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
    $runs = @()
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

    $runs = @()
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

            $artifacts = [ordered]@{
                indexPath = $indexRel
                metadataPath = $metaRel
                validationPath = $valRel
                pssaPath = $null
                stepsPaths = @()
            }

            $record = [ordered]@{
                runId = $runId
                manifestPath = $manifestPath
                source = 'unknown'
                status = $status
                attemptCount = $attemptCount
                attemptHistory = $attemptHistory
                reason = $null
                artifacts = $artifacts
                validation = [ordered]@{ pre = $null; post = $null }
                pssa = $null
            }

            $runs += $record
        } catch {
            Write-Host "[aggregator] Failed processing run dir $dir"
            Write-Host ($_ | Out-String)
            $global:AGGREGATOR_ERRORS += ($_ | Out-String)
            continue
        }
    }
}

# Ensure deterministic ordering by runId (push unknowns to the end)
$runs = @($runs | Sort-Object -Property @{ Expression = { if ($_.runId) { $_.runId } else { 'zzz-unknown' } } })

# Build a stable summary object (always an object, never an array)
Write-Host "[aggregator] runs count = $($runs.Count)"
$passedRuns = @($runs | Where-Object { $_.status -in @('success','ok','passed') })
$failedRuns = @($runs | Where-Object { $_.status -eq 'failed' })

$summaryObj = [ordered]@{
    passed = $passedRuns.Count
    failed = $failedRuns.Count
    total  = @($runs).Count
    failedRuns = @($failedRuns | ForEach-Object { $_.runId })
    runs   = @($runs)
    pssa = [ordered]@{ newFindings = 0; existingFindings = 0; resolvedFindings = 0; topFiles = @(); newSamples = @() }
    errors = $global:AGGREGATOR_ERRORS
    timestamp = (Get-Date).ToString('o')
}
Write-Host "[aggregator] Summary => passed=$($summaryObj.passed) failed=$($summaryObj.failed) total=$($summaryObj.total)"
Write-AtomicJson -path $OutputJson -obj $summaryObj

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
