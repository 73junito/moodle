<#
Checks the repository for any tracked files under tools/runs/**/output or tools/runs/**/artifacts
Exits with non-zero code if any offending files are found.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "[validator] Checking for committed run outputs under tools/runs/..."

$git = (Get-Command git -ErrorAction SilentlyContinue)
if (-Not $git) {
    Write-Error "git not found on PATH"
    exit 1
}

$tracked = & git ls-files

$pattern = '^(tools/runs/).*?/((output|artifacts)/).+'

$violations = @()
foreach ($f in $tracked) {
    if ($f -match $pattern) {
        $violations += $f
    }
}

if ($violations.Count -gt 0) {
    Write-Host "Detected committed run output/artifact files (forbidden):" -ForegroundColor Red
    $violations | ForEach-Object { Write-Host " - $_" }
    Write-Host "Please move runtime outputs to an ignored path (tools/runs/) or remove them from the commit." -ForegroundColor Yellow
    exit 1
}

Write-Host "OK: no committed run outputs found"
exit 0
