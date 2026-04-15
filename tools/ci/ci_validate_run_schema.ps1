<#
Enforce a whitelist of allowed filenames under tools/runs/<RunId>/
Exits non-zero if any tracked file under tools/runs is not in the allowed list.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "[validator] Enforcing run-schema whitelist under tools/runs/..."

$git = (Get-Command git -ErrorAction SilentlyContinue)
if (-Not $git) {
    Write-Error "git not found on PATH"
    exit 1
}

$tracked = & git ls-files

# Allowed filenames (case-insensitive)
$allowed = @(
    'metadata.json',
    'ir_validation_report.json',
    'ir_validation_report_resilient.json',
    'ir_validation_report_strict.json',
    'ir_validation_compare.json',
    'metadata.json',
    'manifest.json'
)

$violations = @()

foreach ($f in $tracked) {
    if ($f -like 'tools/runs/*') {
        # determine filename portion after runId/
        $parts = $f -split '/'
        if ($parts.Length -ge 3) {
            # filename may be at parts[2] or deeper; accept files at any depth only if their leaf name is allowed
            $leaf = [IO.Path]::GetFileName($f)
            if (-not ($allowed -contains $leaf.ToLower())) {
                $violations += $f
            }
        } else {
            # unexpected path depth -> violation
            $violations += $f
        }
    }
}

if ($violations.Count -gt 0) {
    Write-Host "Detected disallowed committed run files (whitelist violation):" -ForegroundColor Red
    $violations | ForEach-Object { Write-Host " - $_" }
    Write-Host "Allowed leaf filenames: $($allowed -join ', ')" -ForegroundColor Yellow
    exit 1
}

Write-Host "OK: run schema validated (no disallowed committed run files)."
exit 0
