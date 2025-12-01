param(
    [int]$Days = 30,
    [string]$Backups = 'D:\Moodle\backups',
    [string]$Archive = 'D:\Moodle\backups\archive',
    [switch]$Apply
)

$ts = (Get-Date).ToString('yyyyMMdd-HHmmss')
$logFile = Join-Path $Backups "cron-rotate-$ts.log"
function Log { param($m) $m | Out-File -FilePath $logFile -Append -Encoding utf8; Write-Output $m }

Log "Starting cron rotation: Days=$Days, Apply=$Apply"
if (-not (Test-Path $Backups)) { Log "Backups folder not found: $Backups. Exiting."; exit 1 }
if (-not (Test-Path $Archive)) { New-Item -ItemType Directory -Path $Archive | Out-Null; Log "Created archive folder: $Archive" }

$cutoff = (Get-Date).AddDays(-$Days)
$patterns = @('cron-run-*.txt','cron-run-latest-summary-*.txt')
$files = Get-ChildItem -Path $Backups -File -Include $patterns -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt $cutoff }

if (-not $files -or $files.Count -eq 0) {
    Log "No cron log files older than $Days days (cutoff: $cutoff). Nothing to do."
    Log "Finished cron rotation"
    exit 0
}

$totalSize = ($files | Measure-Object -Property Length -Sum).Sum
Log "Found $($files.Count) file(s) to archive, total size ${totalSize} bytes. Sample: $($files[0].FullName)"

if (-not $Apply) {
    Log "Dry run mode. To apply changes re-run with -Apply."
    $files | ForEach-Object { Log "DRY: $($_.FullName) (LastWrite: $($_.LastWriteTime))" }
    Log "Finished cron rotation (dry-run)"
    exit 0
}

# Group files by year-month of lastwrite time and compress per group
$grouped = $files | Group-Object { $_.LastWriteTime.ToString('yyyyMM') }
foreach ($g in $grouped) {
    $ym = $g.Name
    $zipName = "cron-archive-$ym.zip"
    $zipPath = Join-Path $Archive $zipName
    $toAdd = $g.Group | ForEach-Object { $_.FullName }
    Log "Archiving $($g.Count) file(s) for $ym into $zipPath"
    try {
        if (Test-Path $zipPath) {
            # update existing zip
            Compress-Archive -Path $toAdd -DestinationPath $zipPath -Update -ErrorAction Stop
            Log "Updated existing archive: $zipPath"
        } else {
            Compress-Archive -Path $toAdd -DestinationPath $zipPath -ErrorAction Stop
            Log "Created new archive: $zipPath"
        }
        # Remove originals after successful archive
        foreach ($f in $g.Group) {
            Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop
            Log "Removed original file: $($f.FullName)"
        }
    } catch {
        $err = $_.Exception.Message
        Log "ERROR archiving group $ym: $err"
    }
}

Log "Finished cron rotation (applied). Archive stored in $Archive. See this log: $logFile"
exit 0
