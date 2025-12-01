# Wrapper to run Moodle cron and append output to backups with timestamp
# Usage: run this from scheduled task instead of calling php.exe directly
$ts = (Get-Date).ToString('yyyyMMdd-HHmmss')
$log = "D:\Moodle\backups\cron-run-$ts.txt"
$php = 'D:\Moodle\server\php\php.exe'
$cron = 'D:\Moodle\server\moodle\admin\cli\cron.php'
try {
    & $php $cron *>&1 | Out-File -FilePath $log -Encoding utf8
    "Cron wrapper completed at $(Get-Date -Format o)" | Out-File -FilePath $log -Append -Encoding utf8
} catch {
    "Cron wrapper error at $(Get-Date -Format o): $_" | Out-File -FilePath $log -Append -Encoding utf8
}
