param(
    [int]$Months = 12,
    [string]$ArchiveDir = 'D:\Moodle\backups\archive',
    [switch]$Apply
)

$ts = (Get-Date).ToString('yyyyMMdd-HHmmss')
$log = Join-Path (Split-Path $ArchiveDir -Parent) "archive-prune-$ts.log"
function Log { param($m) $m | Out-File -FilePath $log -Append -Encoding utf8; Write-Output $m }

Log "Starting archive prune: Months=$Months, Apply=$Apply, ArchiveDir=$ArchiveDir"
if (-not (Test-Path $ArchiveDir)) { Log "Archive folder not found: $ArchiveDir. Nothing to do."; exit 0 }

$cutoff = (Get-Date).AddMonths(-$Months)
$files = Get-ChildItem -Path $ArchiveDir -File -Include '*.zip' -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt $cutoff }

if (-not $files -or $files.Count -eq 0) {
    Log "No archive zip files older than $Months months (cutoff: $cutoff)."
    Log "Finished archive prune"
    exit 0
}

Log "Found $($files.Count) archive file(s) older than $Months months. Sample: $($files[0].FullName)"
foreach ($f in $files) {
    if ($Apply) {
        try {
            Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop
            Log "Removed: $($f.FullName)"
        } catch {
            Log "ERROR removing $($f.FullName): $($_.Exception.Message)"
        }
    } else {
        Log "DRY: $($f.FullName) (LastWrite: $($f.LastWriteTime))"
    }
}

Log "Finished archive prune (Apply=$Apply). See this log: $log"
exit 0
