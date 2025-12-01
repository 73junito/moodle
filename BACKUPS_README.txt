Moodle backups & cron run notes

Paths
- Wrapper script (runs cron, per-run logs): `D:\Moodle\bin\moodle-cron-wrapper.ps1`
- Cron CLI: `D:\Moodle\server\php\php.exe` + `D:\Moodle\server\moodle\admin\cli\cron.php`
- Per-run logs: `D:\Moodle\backups\cron-run-<timestamp>.txt`
- Summary logs: `D:\Moodle\backups\cron-run-latest-summary-<timestamp>.txt`
- Rotation script: `D:\Moodle\bin\moodle-cron-rotate.ps1`
- Rotation archives: `D:\Moodle\backups\archive\cron-archive-<YYYYMM>.zip`
- Rotation schedule task: `MoodleCronRotate` (daily 03:30)
- Wrapper schedule task: `MoodleCronWrapper` (every minute)

Quick checks
- Latest cron log (PowerShell):
  Get-ChildItem 'D:\Moodle\backups\cron-run-*.txt' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  Get-Content <latest-file> -Tail 200

- Check scheduled tasks (PowerShell):
  schtasks /Query /TN "MoodleCronWrapper" /V /FO LIST
  schtasks /Query /TN "MoodleCronRotate" /V /FO LIST

- Force-run cron manually (one-off):
  & 'D:\Moodle\server\php\php.exe' 'D:\Moodle\server\moodle\admin\cli\cron.php'

- Run rotation in dry-run (shows files it would archive):
  & 'D:\Moodle\bin\moodle-cron-rotate.ps1' -Days 30

- Run rotation and apply now (requires appropriate permissions):
  & 'D:\Moodle\bin\moodle-cron-rotate.ps1' -Days 30 -Apply

Notes
- `MoodleCronWrapper` runs the wrapper as `SYSTEM` and appends per-run logs to `D:\Moodle\backups` for audit.
- `MoodleCronRotate` archives older logs monthly into `D:\Moodle\backups\archive`.
- Keep an eye on `D:\Moodle\backups\cron-run-*.txt` log sizes; rotation archives are grouped by YYYYMM.
- Consider adding a retention policy for the `archive` folder (e.g., prune archives older than 12 months).

Contact
- If something fails, check the last rotation log `cron-rotate-*.log` and the scheduled task create/delete metadata files in `D:\Moodle\backups`.
