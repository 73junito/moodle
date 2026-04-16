param(
    [string]$ArtifactsDir = 'artifacts'
)

function New-ReportEntry($path, $size, $status, $note) {
    return [ordered]@{ path = $path; size = $size; status = $status; note = $note }
}

Write-Host "[artifact-check] ArtifactsDir = $ArtifactsDir"

if (-not (Test-Path $ArtifactsDir)) {
    Write-Host "[artifact-check] Artifacts directory '$ArtifactsDir' not found; nothing to validate"
    exit 0
}

# Gather JSON files robustly
$matches = Get-ChildItem -Path $ArtifactsDir -Recurse -Filter *.json -File -ErrorAction SilentlyContinue |
           Where-Object { $_.FullName -match "gh-artifacts-run-" -or $_.FullName -match "[\\/]artifacts[\\/]" }

if (-not $matches -or $matches.Count -eq 0) {
    Write-Host "[artifact-check] No artifact JSON files found under $ArtifactsDir"
    exit 0
}

Write-Host "[artifact-check] Found $($matches.Count) candidate JSON files. Validating..."

$report = New-Object System.Collections.Generic.List[object]
$hasError = $false

foreach ($f in $matches) {
    if (-not $f -or -not $f.FullName) {
        Write-Host "[artifact-check] SKIP invalid file object"
        continue
    }
    $path = $f.FullName
    $size = $f.Length
    $entry = New-ReportEntry $path $size 'ok' ''

    if ($size -eq 0) {
        $entry.status = 'zero-length'
        $entry.note = 'file is empty'
        $report.Add($entry) | Out-Null
        Write-Host "[artifact-check] ZERO-LENGTH: $path"
        $hasError = $true
        continue
    }

    try {
        $text = Get-Content -Path $path -Raw -ErrorAction Stop
    } catch {
        $entry.status = 'read-error'
        $entry.note = $_.Exception.Message
        $report.Add($entry) | Out-Null
        Write-Host "[artifact-check] READ-ERROR: $path -> $($entry.note)"
        $hasError = $true
        continue
    }

    $trim = $text.TrimEnd()
    if ($trim.Length -eq 0) {
        $entry.status = 'empty-content'
        $entry.note = 'content only whitespace'
        $report.Add($entry) | Out-Null
        Write-Host "[artifact-check] EMPTY-CONTENT: $path"
        $hasError = $true
        continue
    }

    $lastChar = $trim.Substring($trim.Length-1,1)
    if ($lastChar -ne '}' -and $lastChar -ne ']') {
        $entry.status = 'possibly-truncated'
        $entry.note = "lastChar='$lastChar'"
        $report.Add($entry) | Out-Null
        Write-Host "[artifact-check] POSSIBLY-TRUNCATED: $path (lastChar='$lastChar')"
        $hasError = $true
        continue
    }

    try {
        $null = $text | ConvertFrom-Json -ErrorAction Stop
        $report.Add($entry) | Out-Null
        Write-Host "[artifact-check] OK: $path (size=$size)"
    } catch {
        $entry.status = 'parse-error'
        $entry.note = $_.Exception.Message
        $report.Add($entry) | Out-Null
        Write-Host "[artifact-check] PARSE-ERROR: $path -> $($entry.note)"
        $hasError = $true
    }
}

$summaryPath = Join-Path (Get-Location).Path 'artifact-json-scan-report.json'
$report | ConvertTo-Json -Depth 5 | Out-File -FilePath $summaryPath -Encoding UTF8 -Force
Write-Host "[artifact-check] Scan complete. Report written to: $summaryPath"

if ($hasError) {
    Write-Host "[artifact-check] Validation FAILED — see report"
    exit 1
} else {
    Write-Host "[artifact-check] Validation PASSED"
    exit 0
}
