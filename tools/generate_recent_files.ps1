param(
    [int]$Days = 7,
    [string]$OutDir = (Join-Path $PSScriptRoot 'runs')
)

Set-StrictMode -Version Latest
function Log { param($m) $ts = (Get-Date).ToString('s'); Write-Output "[$ts] $m" }

if (-not (Test-Path $OutDir)) { New-Item -Path $OutDir -ItemType Directory | Out-Null }

$recentPath = Join-Path $OutDir 'recent_files.json'
$artifactsPath = Join-Path $OutDir 'run_artifacts.json'

try {
    $cutoff = (Get-Date).AddDays(-$Days)
    $recent = Get-ChildItem -Path $PSScriptRoot -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -gt $cutoff } | Sort-Object LastWriteTime -Descending | Select-Object FullName,LastWriteTime,Length
    $recent | ConvertTo-Json -Depth 4 | Out-File -FilePath $recentPath -Encoding UTF8
    Log "Wrote recent files to: $recentPath"
} catch {
    Log "Failed to write recent files: $($_.Exception.Message)"
}

try {
    $artifacts = Get-ChildItem -Path (Join-Path $PSScriptRoot 'runs') -File -ErrorAction SilentlyContinue | Select-Object FullName,Name,LastWriteTime,Length
    $artifacts | ConvertTo-Json -Depth 4 | Out-File -FilePath $artifactsPath -Encoding UTF8
    Log "Wrote run artifacts to: $artifactsPath"
} catch {
    Log "Failed to write run artifacts: $($_.Exception.Message)"
}

Write-Output "done"
