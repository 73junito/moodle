CRON & Backups — Ops Runbook

Overview
- Purpose: document the Moodle cron wrapper, scheduled tasks, rotation, pruning and monitoring so ops can inspect, test and troubleshoot.
- Paths and files referenced here assume the repository root at `D:\Moodle`.

Key scripts & locations
- Wrapper (runs cron and writes per-run logs): `D:\Moodle\bin\moodle-cron-wrapper.ps1`
- Cron CLI: `D:\Moodle\server\php\php.exe` and `D:\Moodle\server\moodle\admin\cli\cron.php`
- Per-run logs: `D:\Moodle\backups\cron-run-<timestamp>.txt`
- Summary logs: `D:\Moodle\backups\cron-run-latest-summary-<timestamp>.txt`
- Monitor script: `D:\Moodle\bin\moodle-cron-monitor.ps1`
- Monitor config (example): `D:\Moodle\bin\monitor-config.json` (alerts disabled by default)
- Rotation script: `D:\Moodle\bin\moodle-cron-rotate.ps1` (archives monthly by YYYYMM)
- Archive location: `D:\Moodle\backups\archive\cron-archive-<YYYYMM>.zip`
- Prune script: `D:\Moodle\bin\moodle-archive-prune.ps1`

Scheduled tasks (Windows Task Scheduler)
- `MoodleCronWrapper` — runs the wrapper every minute as `SYSTEM` (produces per-run logs)
- `MoodleCronRotate` — daily at 03:30 as `SYSTEM` (runs rotation to archive old logs)
- `MoodleArchivePrune` — monthly (1st day 04:00) as `SYSTEM` (removes archive zips older than configured months)
- `MoodleCronMonitor` — hourly as `SYSTEM` (runs the monitor to generate summary files and optionally send alerts)

Quick inspection commands (PowerShell)
- Latest cron-run file:
  Get-ChildItem 'D:\Moodle\backups\\cron-run-*.txt' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
- Tail the latest file (200 lines):
  Get-Content <latest-file> -Tail 200
- Show monitor summaries:
  Get-ChildItem 'D:\Moodle\backups\\cron-monitor-summary-*.txt' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  Get-Content <monitor-summary-file> -Tail 200
- Show scheduled task metadata:
  schtasks /Query /TN "MoodleCronWrapper" /V /FO LIST
  schtasks /Query /TN "MoodleCronRotate" /V /FO LIST
  schtasks /Query /TN "MoodleCronMonitor" /V /FO LIST

Manual run (one-off)
- Run cron now (one-off):
  & 'D:\Moodle\server\php\php.exe' 'D:\Moodle\server\moodle\admin\cli\cron.php'

- Run rotation dry-run:
  & 'D:\Moodle\bin\moodle-cron-rotate.ps1' -Days 30

- Run rotation and apply now:
  & 'D:\Moodle\bin\moodle-cron-rotate.ps1' -Days 30 -Apply

- Run monitor now:
  & 'D:\Moodle\bin\moodle-cron-monitor.ps1' -Tail 200

Enabling alerts (monitor)
- Edit `D:\Moodle\bin\monitor-config.json` and set either `enableWebhook`/`webhookUrl` or `enableEmail` plus SMTP details.
- Example webhook config:
  {
    "enableWebhook": true,
    "webhookUrl": "https://hooks.example.com/services/<token>",
    "enableEmail": false
  }
- Example SMTP config (secure credentials required):
  {
    "enableWebhook": false,
    "enableEmail": true,
    "smtpServer": "smtp.example.com",
    "smtpPort": 587,
    "useSsl": true,
    "from": "moodle@example.local",
    "to": "ops@example.local",
    "username": "smtp-user",
    "password": "smtp-password"
  }
- After editing the config, run the monitor once to test; monitor will attempt to send alerts if issues are found.

Troubleshooting
- If `MoodleCronWrapper` is running too frequently or multiple cron processes appear, ensure `MoodleCron` (legacy) is disabled or deleted.
- If rotation archives are not created, confirm `D:\Moodle\backups\archive` exists and `moodle-cron-rotate.ps1` has write permissions.
- If monitor alerts fail to send, check `D:\Moodle\backups\cron-monitor-summary-*.txt` for error messages and confirm network access to webhook/smtp host.

Contact
- For help, provide the latest monitor summary and the scheduled-task metadata files from `D:\Moodle\backups` (files named `scheduledtask-*` and `cron-monitor-summary-*`).
