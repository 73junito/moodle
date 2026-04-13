param(
    [string]$Root = ".",
    [switch]$Strict,
    [string]$OutDir = "tools\\runs",
    [string]$RunId = $null
)

Set-StrictMode -Version Latest

function Log { param($m) $ts = (Get-Date).ToString('s'); Write-Host "[$ts] $m" }

# Detect pwsh/powershell (with optional .exe) followed at some point by a -Command argument
$patterns = @(
    'pwsh(?:\.exe)?[^\r\n]*-Command',
    'powershell(?:\.exe)?[^\r\n]*-Command'
)

if ($Strict) { $patterns += 'Start-Process\s+pwsh\s+-ArgumentList' }

Log "Scanning for forbidden -Command usage under: $Root"

# Fail fast if any .wsb files exist outside the legacy archive (enforce migration)
$wsbFiles = Get-ChildItem -Path $Root -Recurse -Filter *.wsb -File -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notlike "*\tools\legacy\wsb\*" }
if (@($wsbFiles).Count -gt 0) {
    Write-Host "FAIL: Found .wsb files outside tools/legacy/wsb - archive or convert them to tools/ci/*.ps1" -ForegroundColor Red
    $wsbFiles | ForEach-Object { Write-Host $_.FullName }
    exit 1
}

# Exclude common non-code artifacts to avoid scanning large logs/binaries
$excludeExtensions = @('.csv','.pml','.log','.json','.zip','.exe','.dll','.bin','.yml','.yaml','.md')

# build parameterized exclude paths (use OutDir/RunId instead of hardcoded literals)
$outDirPath = if ($OutDir.EndsWith('\') -or $OutDir.EndsWith('/')) { $OutDir } else { "$OutDir\" }
$excludePaths = @($outDirPath, '\sandbox_artifacts\','\node_modules\','\.git\','\tools\legacy\wsb\')
if ($RunId) { $excludePaths += (Join-Path $OutDir $RunId) + '\' }

# Build list of candidate text files to scan, excluding large logs, binary captures and CI helpers
$files = Get-ChildItem -Path $Root -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object {
        $ext = $_.Extension.ToLower()
        $path = $_.FullName
        if ($excludeExtensions -contains $ext) { return $false }
        foreach ($p in $excludePaths) { if ($path -like "*$p*") { return $false } }
        if ($_.Length -gt 1MB) { return $false }
        return $true
    }

# Exclude this script and other CI helper scripts to avoid self-matching
$selfPath = $PSCommandPath
$files = $files | Where-Object { $_.FullName -ne $selfPath -and ($_.FullName -notlike '*\tools\ci\*') }

$hits = @()

foreach ($pattern in $patterns) {
    $matches = @()
    try {
        $matches = Select-String -Path ($files | ForEach-Object { $_.FullName }) -Pattern $pattern -AllMatches -ErrorAction SilentlyContinue
    } catch {
        # ignore file read errors
        continue
    }
    foreach ($m in $matches) {
        $hits += [PSCustomObject]@{
            File = $m.Path
            LineNumber = $m.LineNumber
            Line = $m.Line.Trim()
            Pattern = $pattern
        }
    }
}

if ($hits.Count -gt 0) {
    Write-Host "FAIL: Forbidden pwsh/powershell -Command usage detected:" -ForegroundColor Red
    $hits | Sort-Object File,LineNumber | Format-Table @{Label='File';Expression={$_.File}}, @{Label='Line';Expression={$_.LineNumber}}, @{Label='Pattern';Expression={$_.Pattern}} -AutoSize
    Write-Host "\nUse dedicated scripts under tools/ci/ and call with `pwsh -NoProfile -File` instead." -ForegroundColor Yellow
    exit 1
}

Write-Host "OK: no forbidden -Command usage found" -ForegroundColor Green
exit 0
