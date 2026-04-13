# Pre-commit safety guard (artifact + size protection)

$maxSizeMB = 10
$maxBytes = $maxSizeMB * 1MB

$blockedDirs = @(
    "sandbox_artifacts",
    "installer_extracted",
    "public",
    "tools/runs"
)

# Allow committed inputs/fixtures under tools/runs/input/
# (block generated per-run outputs under tools/runs/<RunId>/...)

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
            # Allow committed inputs under tools/runs/input/, but block generated outputs under tools/runs/*
            if ($file -like "tools/runs/input/*") {
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
