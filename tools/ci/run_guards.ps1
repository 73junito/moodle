param(
    [string]$Root = "."
)

Set-StrictMode -Version Latest

function Log { param($m) $ts = (Get-Date).ToString('s'); Write-Host "[$ts] $m" }

Log "Running CI guards under: $Root"

$exitCode = 0

$guards = @(
    @{ Path = "$PSScriptRoot\ci_validate_no_pwsh_command.ps1"; Args = "-Root $Root" },
    @{ Path = "$PSScriptRoot\ci_validate_no_implicit_paths.ps1"; Args = "-Root $Root" }
)

foreach ($g in $guards) {
    Log "Executing: $($g.Path) $($g.Args)"
    try {
        & pwsh -NoProfile -File $g.Path $g.Args
        $rc = $LASTEXITCODE
    } catch {
        $rc = 1
    }
    Log "Exit code: $rc"
    if ($rc -ne 0) { $exitCode = $rc }
}

if ($exitCode -ne 0) {
    Write-Host "One or more guards failed (exit $exitCode)" -ForegroundColor Red
} else {
    Write-Host "All guards passed" -ForegroundColor Green
}

exit $exitCode
