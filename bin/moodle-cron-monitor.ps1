param(
    [int]$Tail = 120,
    [string]$OutDir = 'D:\Moodle\backups',
    [string]$ConfigPath = 'D:\Moodle\bin\monitor-config.json'
)

$ts = (Get-Date).ToString('yyyyMMdd-HHmmss')
$latest = Get-ChildItem -Path $OutDir -Filter 'cron-run-*.txt' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $latest) {
    $latest = Get-ChildItem -Path $OutDir -Filter 'cron-run-latest-summary-*.txt' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
}

$summaryFile = Join-Path $OutDir "cron-monitor-summary-$ts.txt"
"Monitoring summary generated at $ts" | Out-File -FilePath $summaryFile -Encoding utf8
if (-not $latest) {
    "No cron-run files found in $OutDir" | Out-File -FilePath $summaryFile -Append -Encoding utf8
    Write-Output "NO_CRON_LOG_FOUND"
    # we'll still attempt to send alert if configured
} else {
    "Source file: $($latest.FullName)" | Out-File -FilePath $summaryFile -Append -Encoding utf8
    "--- Tail ($Tail lines) ---" | Out-File -FilePath $summaryFile -Append -Encoding utf8
    Get-Content $latest.FullName -Tail $Tail | Out-File -FilePath $summaryFile -Append -Encoding utf8
}

"`n--- Scheduled task statuses ---`n" | Out-File -FilePath $summaryFile -Append -Encoding utf8
try {
    schtasks /Query /TN "MoodleCronWrapper" /V /FO LIST 2>&1 | Out-File -FilePath $summaryFile -Append -Encoding utf8
} catch { "Unable to query MoodleCronWrapper: $($_.Exception.Message)" | Out-File -FilePath $summaryFile -Append -Encoding utf8 }
try {
    schtasks /Query /TN "MoodleCronRotate" /V /FO LIST 2>&1 | Out-File -FilePath $summaryFile -Append -Encoding utf8
} catch { "Unable to query MoodleCronRotate: $($_.Exception.Message)" | Out-File -FilePath $summaryFile -Append -Encoding utf8 }

# Load config if present
$config = $null
if (Test-Path $ConfigPath) {
    try { $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json -ErrorAction Stop } catch { $config = $null }
}

function Send-Alert {
    param(
        [string]$Subject,
        [string]$Body
    )
    if (-not $config) { return }

    # Webhook (preferred if configured)
    if ($config.enableWebhook -eq $true -and $config.webhookUrl) {
        try {
            $payload = @{ subject = $Subject; body = $Body; host = $env:COMPUTERNAME; time = (Get-Date).ToString('o') } | ConvertTo-Json
            Invoke-RestMethod -Uri $config.webhookUrl -Method Post -Body $payload -ContentType 'application/json' -ErrorAction Stop
        } catch {
            # write failure to summary
            "Failed to POST webhook: $($_.Exception.Message)" | Out-File -FilePath $summaryFile -Append -Encoding utf8
        }
    }

    # SMTP email (optional)
    if ($config.enableEmail -eq $true -and $config.smtpServer -and $config.to) {
        try {
            $mailParams = @{
                SmtpServer = $config.smtpServer
                To = $config.to
                From = ($config.from -or "moodle@$env:COMPUTERNAME")
                Subject = $Subject
                Body = $Body
            }
            if ($config.smtpPort) { $mailParams.Port = $config.smtpPort }
            if ($config.useSsl -eq $true) { $mailParams.UseSsl = $true }
            if ($config.username -and $config.password) {
                $sec = New-Object System.Management.Automation.PSCredential($config.username,(ConvertTo-SecureString $config.password -AsPlainText -Force))
                $mailParams.Credential = $sec
            }
            Send-MailMessage @mailParams
        } catch {
            "Failed to send email: $($_.Exception.Message)" | Out-File -FilePath $summaryFile -Append -Encoding utf8
        }
    }
}

# Decide whether to alert: missing cron file or any ERROR lines in summary
$summaryText = Get-Content $summaryFile -Raw -ErrorAction SilentlyContinue
$shouldAlert = $false
if (-not $latest) { $shouldAlert = $true; $alertReason = 'No cron-run files found' }
elseif ($summaryText -match '\bERROR\b' -or $summaryText -match 'Unable to query') { $shouldAlert = $true; $alertReason = 'Errors found in cron summary' }

if ($shouldAlert -and $config) {
    $subject = "Moodle cron alert: $alertReason on $env:COMPUTERNAME"
    $body = $summaryText
    Send-Alert -Subject $subject -Body $body
    "Alert sent (subject: $subject)" | Out-File -FilePath $summaryFile -Append -Encoding utf8
}

"Wrote summary: $summaryFile" | Out-File -FilePath $summaryFile -Append -Encoding utf8
Get-Content $summaryFile -Tail $Tail
