param(
    [switch]$SkipPhp,
    [switch]$SkipNode,
    [switch]$SkipGuards
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "=== Local CI Runner ===" -ForegroundColor Cyan

# 1. Node / JS build
if (-not $SkipNode) {
    Write-Host "`n[1/3] Node/Grunt step..." -ForegroundColor Yellow

    if (Test-Path "package.json") {
        Write-Host "Running npm install..."
        npm install
        Write-Host "Running grunt..."
        npx grunt
    } else {
        Write-Host "No package.json found, skipping Node step."
    }
}

# 2. PHP tests
if (-not $SkipPhp) {
    Write-Host "`n[2/3] PHP Unit tests..." -ForegroundColor Yellow

    if (Test-Path "vendor/bin/phpunit") {
        php vendor/bin/phpunit
    } else {
        Write-Host "PHPUnit not installed, skipping."
    }
}

# 3. CI Guards
if (-not $SkipGuards) {
    Write-Host "`n[3/3] CI Guards..." -ForegroundColor Yellow

    pwsh -File tools/ci/run_guards.ps1 -Root .
}

Write-Host "`n=== Local CI Complete ===" -ForegroundColor Green
