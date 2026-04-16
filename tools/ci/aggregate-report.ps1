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
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $json | Out-File -FilePath $tmp -Encoding UTF8 -Force
    Move-Item -Path $tmp -Destination $path -Force
}

# Collect candidate runs
$runs = @()
if (-not (Test-Path $ArtifactsDir)) {
    Write-Host "[aggregator] Artifacts directory '$ArtifactsDir' not found; emitting empty outputs"
    $runs = @()
} else {
    Get-ChildItem -Path $ArtifactsDir -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $dir = $_.FullName
        $indexPath = Join-Path $dir 'index.json'
        $metadataPath = Join-Path $dir 'metadata.json'
        $listingPath = Join-Path $dir 'listing.json'
        $runId = $null
        $manifestPath = $null
        $status = 'skipped'
        $attemptCount = 0
        $attemptHistory = @()
        if (Test-Path $indexPath) {
            try {
                $idx = Get-Content $indexPath -Raw | ConvertFrom-Json -ErrorAction Stop
                if ($idx.runId) { $runId = $idx.runId }
                if ($idx.manifestPath) { $manifestPath = $idx.manifestPath }
                if ($idx.status) { $status = $idx.status }
                if ($idx.attemptCount) { $attemptCount = $idx.attemptCount }
                if ($idx.attemptsHistory) { $attemptHistory = $idx.attemptsHistory }
            } catch {
                # ignore parse errors, fallback to folder-name
                $runId = $null
            }
        }
        if (-not $runId) {
            # try to infer from folder name
            $name = Split-Path -Leaf $dir
            if ($name) { $runId = $name }
        }
        $runId = Normalize-RunId $runId

        # compute artifact relative paths safely
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
    }
}

# Ensure deterministic ordering by runId
$runs = $runs | Sort-Object -Property runId

# Write summary (array form)
Write-Host "[aggregator] runs count = $($runs.Count)"
Write-Host "[aggregator] Wrote canonical run records: $OutputJson"
Write-AtomicJson -path $OutputJson -obj $runs

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
