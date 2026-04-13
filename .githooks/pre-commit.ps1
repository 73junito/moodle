# Block large files (>10 MB)
$maxSizeMB = 10
$maxBytes = $maxSizeMB * 1MB

$files = git diff --cached --name-only

$violations = @()

foreach ($file in $files) {
    if (Test-Path $file) {
        $size = (Get-Item $file).Length
        if ($size -gt $maxBytes) {
            $violations += [PSCustomObject]@{
                File = $file
                SizeMB = [math]::Round($size / 1MB, 2)
            }
        }
    }
}

if ($violations.Count -gt 0) {
    Write-Host "`n❌ Commit blocked: Large files detected (> $maxSizeMB MB)`n" -ForegroundColor Red
    $violations | Format-Table -AutoSize
    exit 1
}

exit 0
