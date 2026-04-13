# Pre-commit safety guard (artifact + size protection)

$maxSizeMB = 10
$maxBytes = $maxSizeMB * 1MB

$blockedDirs = @(
    "sandbox_artifacts",
    "installer_extracted",
    "public",
    "tools/runs"
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

    # Path-based blocking (match on path segment boundaries to avoid false positives)
    foreach ($dir in $blockedDirs) {
        $pattern = "(^|[\\/])" + [regex]::Escape($dir) + "([\\/]|$)"
        if ($file -match $pattern) {
            $violations += "Blocked directory path: $file"
            break
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
