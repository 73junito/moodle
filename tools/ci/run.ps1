param(
    [Parameter(Mandatory=$true)]
    [string]$ManifestPath,
    [string]$RunnerScript,
    [switch]$DryRun,
    [switch]$EnforceRunDir,
    [switch]$ContinueOnError
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Normalize and resolve the manifest path early to avoid CWD-dependent bugs
try {
    $resolved = Resolve-Path -LiteralPath $ManifestPath -ErrorAction Stop
    $ManifestPath = $resolved.Path
} catch {
    Write-Host "::error::Manifest not found or path invalid: $ManifestPath"
    exit 1
}

Write-Host "[run] Starting run for manifest: $ManifestPath"

if (-not (Test-Path $ManifestPath)) {
    Write-Host "::error::Manifest not found: $ManifestPath"
    exit 1
}

$manifest = Get-Content $ManifestPath -Raw | ConvertFrom-Json
$manifestDir = Split-Path -Parent $ManifestPath
$manifestDirFull = (Get-Item -LiteralPath $manifestDir).FullName.TrimEnd('\')

# Add defensive defaults for optional manifest properties to avoid property access errors
$optionalProps = @('timeoutSeconds','retry','steps')
foreach ($p in $optionalProps) {
    if (-not ($manifest.PSObject.Properties.Name -contains $p)) {
        if ($p -eq 'steps') { $manifest | Add-Member -MemberType NoteProperty -Name $p -Value @() -Force } else { $manifest | Add-Member -MemberType NoteProperty -Name $p -Value $null -Force }
    }
}


# Pre-run validation (inputs)
Write-Host "[run] Running pre-run validation..."
& "$PSScriptRoot\ci_validate_manifest.ps1" -ManifestPath $ManifestPath -EnforceRunDir:$EnforceRunDir

if ($DryRun) {
    $report = [pscustomobject]@{
        runId = $manifest.runId
        manifest = $ManifestPath
        timestamp = (Get-Date).ToString('o')
        mode = 'dryrun'
        inputs = $manifest.inputs
        outputs = $manifest.outputs
        status = 'inputs-validated'
    }
    # deterministic per-manifest report filename to avoid collisions in parallel runs
    $sanRunId = ($manifest.runId -replace '[^A-Za-z0-9_\-]','-').ToLowerInvariant()
    # write all run artifacts under a per-run artifact root to avoid collisions
    $artifactRoot = Join-Path '.github/artifacts' $sanRunId
    if (-not (Test-Path $artifactRoot)) { New-Item -ItemType Directory -Path $artifactRoot -Force | Out-Null }
    $reportPath = Join-Path $artifactRoot 'validation-report.json'
    $report | ConvertTo-Json -Depth 5 | Set-Content -Path $reportPath -Encoding UTF8 -Force
    Write-Host "[run] DryRun: validation report written to $reportPath"
    # write an index.json for dry runs as well
    try {
        $index = [ordered]@{
            runId = $manifest.runId
            manifest = $ManifestPath
            timestamp = (Get-Date).ToString('o')
            mode = 'dryrun'
            artifacts = [ordered]@{
                metadata = $null
                validation = @($reportPath)
                pssa = @()
                steps = @()
            }
        }
        $indexPath = Join-Path $artifactRoot 'index.json'
        ($index | ConvertTo-Json -Depth 10) | Set-Content -Path $indexPath -Encoding UTF8 -Force
        Write-Host "[run] DryRun: index written to $indexPath"
    } catch { Write-Host "[run] Warning: could not write dryrun index: $($_.Exception.Message)" }
    exit 0
}

# Optional execution step: run a script inside the manifest folder
$errors = @()
$status = 'success'
$exitCode = 0
$failed = $false

# Helper to capture a step execution result
function Invoke-Step {
    param(
        [string]$StepName,
        [string]$ScriptRelPath
        ,[int]$TimeoutSeconds = 0
    )
    $stepResult = [pscustomobject]@{
        name = $StepName
        script = $ScriptRelPath
        started = (Get-Date).ToString('o')
        finished = $null
        exitCode = 0
        error = $null
        timedOut = $false
        stdoutPath = $null
        stderrPath = $null
        stdout = $null
        stderr = $null
    }

    if ([string]::IsNullOrEmpty($ScriptRelPath)) {
        $stepResult.error = 'no script specified'
        return $stepResult
    }

    if ([System.IO.Path]::IsPathRooted($ScriptRelPath) -or $ScriptRelPath -match '\.\.') {
        $stepResult.error = "RunnerScript path invalid: $ScriptRelPath"
        return $stepResult
    }

    $scriptPath = Join-Path $manifestDir $ScriptRelPath
    $scriptFull = [System.IO.Path]::GetFullPath($scriptPath)
    if (-not $scriptFull.StartsWith($manifestDirFull, [System.StringComparison]::OrdinalIgnoreCase)) {
        $stepResult.error = "RunnerScript escapes manifest directory: $ScriptRelPath"
        return $stepResult
    }
    if (-not (Test-Path $scriptFull)) {
        $stepResult.error = "RunnerScript not found: $scriptFull"
        return $stepResult
    }

    # prepare step directory and sanitized step name
    $sanitize = {
        param($n)
        $s = ($n -replace '[^A-Za-z0-9_\-]','-').Trim('-')
        if ($s.Length -gt 64) { $s = $s.Substring(0,64) }
        return $s.ToLowerInvariant()
    }
    $san = & $sanitize $StepName
    $stepDir = Join-Path $manifestDir (Join-Path 'steps' $san)
    if (-not (Test-Path $stepDir)) { New-Item -ItemType Directory -Path $stepDir -Force | Out-Null }

    $stdoutPath = Join-Path $stepDir 'stdout.txt'
    $stderrPath = Join-Path $stepDir 'stderr.txt'
    # inline cap (KB) precedence: manifest.logging.inlineLogLimitKB -> env RUN_INLINE_LOG_LIMIT_KB -> default 40 KB
    $defaultKb = 40
    $inlineLimitKb = $defaultKb
    if ($manifest -and $manifest.PSObject.Properties.Name -contains 'logging' -and $manifest.logging -ne $null) {
        if ($manifest.logging.PSObject.Properties.Name -contains 'inlineLogLimitKB' -and $manifest.logging.inlineLogLimitKB -ne $null) {
            try { $inlineLimitKb = [int]$manifest.logging.inlineLogLimitKB } catch { $inlineLimitKb = $defaultKb }
        }
    } elseif ($env:RUN_INLINE_LOG_LIMIT_KB) {
        try { $inlineLimitKb = [int]$env:RUN_INLINE_LOG_LIMIT_KB } catch { $inlineLimitKb = $defaultKb }
    }
    $inlineLimit = [int]($inlineLimitKb * 1024)

    try {
        Write-Host "[run] Executing step '$StepName': $scriptFull"
        if ($TimeoutSeconds -gt 0) {
            # Run the script inside a job and redirect streams to files inside the stepDir
            $job = Start-Job -ScriptBlock {
                param($p, $outPath, $errPath)
                & $p *> $outPath 2> $errPath
                $rc = $LASTEXITCODE
                Write-Output @{ exit = $rc }
            } -ArgumentList $scriptFull, $stdoutPath, $stderrPath

            $completed = Wait-Job $job -Timeout $TimeoutSeconds
            if (-not $completed) {
                try {
                    Stop-Job $job -ErrorAction SilentlyContinue
                    Receive-Job $job -ErrorAction SilentlyContinue | Out-Null
                } finally {
                    Remove-Job $job -Force -ErrorAction SilentlyContinue
                }
                $stepResult.error = "Timed out after ${TimeoutSeconds}s"
                $stepResult.exitCode = 124
                $stepResult.timedOut = $true
            } else {
                try {
                    $out = Receive-Job $job -ErrorAction SilentlyContinue
                } finally {
                    Remove-Job $job -Force -ErrorAction SilentlyContinue
                }
                # Look for a structured exit value produced by the job
                $stepExit = $null
                if ($out -ne $null) {
                    foreach ($o in [array]$out) {
                        if ($o -is [hashtable] -and $o.ContainsKey('exit')) { $stepExit = [int]$o.exit }
                        elseif ($o -is [pscustomobject] -and $o.PSObject.Properties.Name -contains 'exit') { $stepExit = [int]$o.exit }
                    }
                }
                if ($null -eq $stepExit) { $stepExit = (if ($?) {0} else {1}) }
                $stepResult.exitCode = $stepExit
                if ($stepExit -ne 0) { $stepResult.error = "Step exited with code $stepExit" }
            }
        } else {
            # Direct execution with redirection to files
            & $scriptFull *> $stdoutPath 2> $stderrPath
            $stepExit = $LASTEXITCODE
            if ($null -eq $stepExit) { $stepExit = (if ($?) {0} else {1}) }
            $stepResult.exitCode = $stepExit
            if ($stepExit -ne 0) { $stepResult.error = "Step exited with code $stepExit" }
        }

        # read captured files (full write always done), include truncated inline content
        $stdoutFull = ''
        $stderrFull = ''
        if (Test-Path $stdoutPath) { $stdoutFull = (Get-Content $stdoutPath -Raw -ErrorAction SilentlyContinue) }
        if (Test-Path $stderrPath) { $stderrFull = (Get-Content $stderrPath -Raw -ErrorAction SilentlyContinue) }
        $stepResult.stdoutPath = $stdoutPath
        $stepResult.stderrPath = $stderrPath
        if ($null -ne $stdoutFull -and $stdoutFull.Length -gt 0) {
            if ($stdoutFull.Length -gt $inlineLimit) { $stepResult.stdout = $stdoutFull.Substring(0,$inlineLimit) + "\n...[truncated]" } else { $stepResult.stdout = $stdoutFull }
        }
        if ($null -ne $stderrFull -and $stderrFull.Length -gt 0) {
            if ($stderrFull.Length -gt $inlineLimit) { $stepResult.stderr = $stderrFull.Substring(0,$inlineLimit) + "\n...[truncated]" } else { $stepResult.stderr = $stderrFull }
        }

    } catch {
        $stepResult.error = $_.Exception.Message
        $stepResult.exitCode = 1
    } finally {
        $stepResult.finished = (Get-Date).ToString('o')
    }

    return $stepResult
}

# Lock helpers: per-manifest run locks to prevent concurrent runs
$lockRoot = Join-Path $manifestDir '.locks'
$lockPath = Join-Path $lockRoot $manifest.runId
$lockStaleSeconds = 15 * 60
$lockWaitSeconds = 5 * 60
$lockPollInterval = 5

function Acquire-Lock {
    param([string]$path)
    if (-not (Test-Path $lockRoot)) { New-Item -ItemType Directory -Path $lockRoot -Force | Out-Null }
    $waitStart = Get-Date
    while ($true) {
        try {
            New-Item -ItemType Directory -Path $path -ErrorAction Stop | Out-Null
            $lockInfo = [pscustomobject]@{
                runId = $manifest.runId
                pid = $PID
                started = (Get-Date).ToString('o')
                host = $env:COMPUTERNAME
                github_run_id = $env:GITHUB_RUN_ID
            }
            $lockFile = Join-Path $path 'lock.json'
            $lockInfo | ConvertTo-Json -Depth 5 | Set-Content -Path $lockFile -Encoding UTF8
            Write-Host "[run] Acquired lock: $path"
            return $true
        } catch {
            if (Test-Path $path) {
                try {
                    $age = (Get-Date) - (Get-Item $path).CreationTime
                } catch {
                    $age = New-TimeSpan -Seconds 0
                }
                if ($age.TotalSeconds -gt $lockStaleSeconds) {
                    Write-Host "[run] Reclaiming stale lock at $path (age $($age.TotalSeconds) s)"
                    Remove-Item -Recurse -Force $path -ErrorAction SilentlyContinue
                    Start-Sleep -Seconds 1
                    continue
                }
            }
            if (((Get-Date) - $waitStart).TotalSeconds -ge $lockWaitSeconds) {
                throw "Lock at $path held by another process and wait timeout reached"
            }
            Start-Sleep -Seconds $lockPollInterval
        }
    }
}

function Release-Lock {
    param([string]$path)
    if (Test-Path $path) {
        try { Remove-Item -Recurse -Force $path -ErrorAction SilentlyContinue } catch {}
        Write-Host "[run] Released lock: $path"
    }
}

# Execution model: prefer manifest.steps (array of {name, script}), fallback to RunnerScript
# All step execution happens inside the unified attempt loop below (ensures clean attempts for retries)

# Retry logic: attempt the whole run up to retry.count times (0 = no retries)
# If manifest.retry.count is present, it defines number of retries (not counting first attempt)
$retryCount = 0
$retryBackoff = 0
$retryOn = @('failure','timeout')
# Be defensive when reading optional 'retry' object from the manifest.
if ($manifest -and $manifest.PSObject.Properties.Name -contains 'retry' -and $manifest.retry -ne $null) {
    try {
        if ($manifest.retry.PSObject.Properties.Name -contains 'count' -and $manifest.retry.count -ne $null) { $retryCount = [int]$manifest.retry.count }
        if ($manifest.retry.PSObject.Properties.Name -contains 'backoffSeconds' -and $manifest.retry.backoffSeconds -ne $null) { $retryBackoff = [int]$manifest.retry.backoffSeconds }
        if ($manifest.retry.PSObject.Properties.Name -contains 'retryOn' -and $manifest.retry.retryOn -ne $null) { $retryOn = @(); foreach ($r in $manifest.retry.retryOn) { $retryOn += $r } }
    } catch { }
}

# Unified attempt loop: always execute steps inside the loop for deterministic attempts
$finalStatus = $status
$finalExit = $exitCode
$finalErrors = $errors
$finalSteps = @()
$timeoutHit = $false
$attemptsPerformed = 0
$attemptHistory = @()

try {
    Acquire-Lock -path $lockPath
    for ($attempt = 1; $attempt -le ($retryCount + 1); $attempt++) {
        $attemptsPerformed = $attempt
        if ($attempt -gt 1) {
            Write-Host "[run] Retry attempt $($attempt - 1) for manifest $($manifest.runId)"
            Write-Host "::warning title=Retrying Manifest::Attempt $($attempt - 1) for $($manifest.runId)"
            Start-Sleep -Seconds ($retryBackoff * ($attempt - 1))
        }

        # reset per-attempt state
        $errors = @()
        $failed = $false
        $stepsExecuted = @()
        $attemptTimedOut = $false
        $attemptFailed = $false

        # execute steps
        if ($manifest -and $manifest.PSObject.Properties.Name -contains 'steps' -and @($manifest.steps).Count -gt 0) {
            foreach ($s in $manifest.steps) {
                $stepContinue = $ContinueOnError.IsPresent
                if ($null -ne $s.continueOnError) { $stepContinue = [bool]$s.continueOnError }
                $timeoutSec = 0
                if ($null -ne $manifest.timeoutSeconds) { $timeoutSec = [int]$manifest.timeoutSeconds }
                if ($null -ne $s.timeoutSeconds) { $timeoutSec = [int]$s.timeoutSeconds }
                $res = Invoke-Step -StepName $s.name -ScriptRelPath $s.script -TimeoutSeconds $timeoutSec
                $stepsExecuted += $res
                if ($res.timedOut) { $timeoutHit = $true }
                if (-not [string]::IsNullOrEmpty($res.error)) {
                    $errors += [pscustomobject]@{ step = $res.name; message = $res.error; time = (Get-Date).ToString('o') }
                    $failed = $true
                    if (-not $stepContinue) { break }
                }
            }
        } elseif ($RunnerScript) {
            $timeoutSec = 0
            if ($null -ne $manifest.timeoutSeconds) { $timeoutSec = [int]$manifest.timeoutSeconds }
            $res = Invoke-Step -StepName 'runner' -ScriptRelPath $RunnerScript -TimeoutSeconds $timeoutSec
            $stepsExecuted += $res
            if ($res.timedOut) { $attemptTimedOut = $true; $timeoutHit = $true }
            if (-not [string]::IsNullOrEmpty($res.error)) {
                $errors += [pscustomobject]@{ step = $res.name; message = $res.error; time = (Get-Date).ToString('o') }
                $attemptFailed = $true
                $failed = $true
            }
        }
        # compute attempt-level exitCode from stepsExecuted
        $attemptExit = 0
        if (@($stepsExecuted).Count -gt 0) {
            $nonZero = $stepsExecuted | Where-Object { $_.exitCode -ne 0 }
            if (@($nonZero).Count -gt 0) {
                $attemptExit = ($nonZero | Select-Object -ExpandProperty exitCode | Measure-Object -Maximum).Maximum
                $attemptFailed = $true
                $failed = $true
            } else {
                $attemptExit = 0
            }
        }

        # attempt-level reason
        $attemptReason = 'success'
        if ($attemptTimedOut) { $attemptReason = 'timeout' }
        elseif ($attemptFailed) { $attemptReason = 'failure' }

        # record attempt history
        $attemptHistory += [pscustomobject]@{
            attempt = $attempt
            reason = $attemptReason
            exitCode = $attemptExit
            errors = $errors
            steps = $stepsExecuted
            timestamp = (Get-Date).ToString('o')
        }

        # determine retry eligibility
        $shouldRetry = $false
        if ($attemptReason -eq 'success') {
            $finalStatus = 'success'
            $finalExit = $attemptExit
            $finalErrors = $errors
            $finalSteps = $stepsExecuted
            break
        } else {
            if ($attemptReason -eq 'timeout' -and ($retryOn -contains 'timeout')) { $shouldRetry = $true }
            if ($attemptReason -eq 'failure' -and ($retryOn -contains 'failure')) { $shouldRetry = $true }
            if ($shouldRetry) { Write-Host "[run] Attempt $attempt failed (reason=$attemptReason); will retry up to $retryCount" } else { Write-Host "[run] Attempt $attempt failed (reason=$attemptReason); not eligible for retry"; break }
        }
    }

    # overwrite metadata values with final aggregated
    $status = $finalStatus
    $exitCode = $finalExit
    $errors = $finalErrors
    $stepsExecuted = $finalSteps
    if (-not $attemptsPerformed) { $attemptsPerformed = 1 }
} finally {
    Release-Lock -path $lockPath
}

# derive exitCode for multi-step runs from final stepsExecuted
if (@($stepsExecuted).Count -gt 0) {
    $nonZero = $stepsExecuted | Where-Object { $_.exitCode -ne 0 }
    if (@($nonZero).Count -gt 0) {
        $exitCode = ($nonZero | Select-Object -ExpandProperty exitCode | Measure-Object -Maximum).Maximum
    } else {
        $exitCode = 0
    }
}

if ($status -ne 'success') { $status = 'failed' }

# Post-run validation (outputs)
try {
    Write-Host "[run] Running post-run validation (outputs)..."
    & "$PSScriptRoot\ci_validate_manifest.ps1" -ManifestPath $ManifestPath -ValidateOutputs -EnforceRunDir:$EnforceRunDir
} catch {
    $errors += [pscustomobject]@{ step = 'post-run-validation'; message = $_.Exception.Message; time = (Get-Date).ToString('o') }
    $status = 'failed'
}

# Emit metadata
$meta = [pscustomobject]@{
    runId = $manifest.runId
    manifest = $ManifestPath
    timestamp = (Get-Date).ToString('o')
    status = $status
    exitCode = $exitCode
    errors = $errors
    attempts = $attemptsPerformed
    timeoutHit = $timeoutHit
    retry = $manifest.retry
    attemptsHistory = $attemptHistory
    inputs = $manifest.inputs
    outputs = $manifest.outputs
}

# write metadata to per-run artifact directory to avoid overwrites and enable reliable aggregation
$sanRunId = ($manifest.runId -replace '[^A-Za-z0-9_\-]','-').ToLowerInvariant()
$artifactRoot = Join-Path '.github/artifacts' $sanRunId
if (-not (Test-Path $artifactRoot)) { New-Item -ItemType Directory -Path $artifactRoot -Force | Out-Null }
$metaPath = Join-Path $artifactRoot 'metadata.json'
$meta | ConvertTo-Json -Depth 5 | Set-Content -Path $metaPath -Encoding UTF8 -Force
Write-Host "[run] metadata written: $metaPath"

# Build artifact index for this run (index.json) - lists all known artifact paths for deterministic aggregation
try {
    $validationFiles = @()
    $pssaFiles = @()
    $stepFiles = @()

    # canonicalize paths relative to artifact root or repository root to avoid absolute paths
    $artifactRootFull = (Get-Item -LiteralPath $artifactRoot).FullName.TrimEnd('\')
    $repoRootFull = (Get-Item -LiteralPath (Get-Location)).FullName.TrimEnd('\')

    function Normalize-PathForIndex {
        param([string]$path)
        if (-not $path) { return $null }
        $pFull = $null
        try { $pFull = (Get-Item -LiteralPath $path -ErrorAction Stop).FullName.TrimEnd('\') } catch { $pFull = $path }
        if ($pFull -and $pFull.StartsWith($artifactRootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
            $rel = [System.IO.Path]::GetRelativePath($artifactRootFull, $pFull)
            return ($rel -replace '\\','/')
        }
        if ($pFull -and $pFull.StartsWith($repoRootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
            $rel = [System.IO.Path]::GetRelativePath($repoRootFull, $pFull)
            return ($rel -replace '\\','/')
        }
        # fallback: return filename only
        return ([System.IO.Path]::GetFileName($path) -replace '\\','/')
    }

    # validation reports may be written to artifactRoot or repository (migration stubs)
    $files = @(Get-ChildItem -Path $artifactRoot -Filter 'validation-report*.json' -File -ErrorAction SilentlyContinue) + @(Get-ChildItem -Path $manifestDir -Recurse -Filter 'validation-report*.json' -File -ErrorAction SilentlyContinue)
    foreach ($f in $files) { $n = Normalize-PathForIndex -path $f.FullName; if ($n) { $validationFiles += $n } }

    # PSSA results if present in artifactRoot or repo
    $files = @(Get-ChildItem -Path $artifactRoot -Filter 'pssa-results.json' -File -ErrorAction SilentlyContinue) + @(Get-ChildItem -Path $manifestDir -Recurse -Filter 'pssa-results.json' -File -ErrorAction SilentlyContinue)
    foreach ($f in $files) { $n = Normalize-PathForIndex -path $f.FullName; if ($n) { $pssaFiles += $n } }

    # steps artifacts are captured inside manifestDir/steps by Invoke-Step; collect stdout/stderr paths from attemptHistory
    foreach ($ah in @($attemptHistory)) {
        if ($ah.steps) {
            foreach ($s in @($ah.steps)) {
                if ($s.stdoutPath) { $stepFiles += $s.stdoutPath }
                if ($s.stderrPath) { $stepFiles += $s.stderrPath }
            }
        }
    }

    $index = [ordered]@{
        runId = $manifest.runId
        manifest = (Normalize-PathForIndex -path $ManifestPath)
        timestamp = (Get-Date).ToString('o')
        attemptCount = $attemptsPerformed
        artifacts = [ordered]@{
            metadata = (Normalize-PathForIndex -path $metaPath)
            validation = @($validationFiles | Select-Object -Unique)
            pssa = @($pssaFiles | Select-Object -Unique)
            steps = @($stepFiles | Select-Object -Unique)
        }
    }
    $indexPath = Join-Path $artifactRoot 'index.json'
    ($index | ConvertTo-Json -Depth 10) | Set-Content -Path $indexPath -Encoding UTF8 -Force
    Write-Host "[run] index written: $indexPath"
} catch {
    Write-Host "[run] Warning: failed to write index.json: $($_.Exception.Message)"
}

if ($status -eq 'failed') {
    Write-Host "::error::Run failed; see metadata: $metaPath"
    exit 1
}

Write-Host "[run] Completed successfully"
exit 0
