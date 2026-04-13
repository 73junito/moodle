# Pre-commit safety guard (artifact + size protection)

$maxSizeMB = 10
$maxBytes = $maxSizeMB * 1MB

$blockedDirs = @(
    "sandbox_artifacts",
    "installer_extracted",
    "public",
    "tools/runs"
)

# Explicit allow-list for config/fixture files under runs
$allowedFiles = @(
    "tools/runs/positive_sim.json"
)

$blockedExt = @(
    ".csv",
    ".zip",
    ".bin",
    ".parquet",
    ".jsonl"
)

$files = git diff --cached --name-only

$violations = @()

foreach ($file in $files) {

    # Path-based blocking
    foreach ($dir in $blockedDirs) {
        if ($dir -eq "tools/runs") {
            # Allow specific fixtures (e.g. positive_sim.json) but block per-run outputs under tools/runs/<RunId>/...
            if ($allowedFiles -contains $file) {
                break
            }
            if ($file -like "tools/runs/*") {
                $violations += "Blocked directory path: $file"
                break
            }
        } else {
            if ($file -like "*$dir*") {
                $violations += "Blocked directory path: $file"
                break
            }
        }
    }

    # Extension-based blocking
    $ext = [System.IO.Path]::GetExtension($file)
    if ($blockedExt -contains $ext) {
        $violations += "Blocked file type ($ext): $file"
    }

    # Size check
    if (Test-Path $file) {
        $size = (Get-Item $file).Length
        if ($size -gt $maxBytes) {
            $violations += "File too large (> $maxSizeMB MB): $file"
        }
    }
}

if ($violations.Count -gt 0) {
    Write-Host "`n❌ Pre-commit blocked:" -ForegroundColor Red
    $violations | ForEach-Object { Write-Host " - $_" }
    exit 1
}

Write-Host "✔ Pre-commit checks passed"
exit 0
