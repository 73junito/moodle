<#
.SYNOPSIS
    Deploy the AutoCurriculum plugin to a local Moodle installation.

.DESCRIPTION
    Copies the current plugin folder into the Moodle `local/` directory as `autocurriculum`.
    Use this script from the plugin root (it will detect its own location).

.PARAMETER MoodleRoot
    The path to the Moodle installation root (where `config.php` exists).

.EXAMPLE
    .\deploy_to_moodle.ps1 -MoodleRoot "C:\inetpub\wwwroot\moodle"

#>

param(
    [Parameter(Mandatory=$true)]
    [string]$MoodleRoot
)

Set-StrictMode -Version Latest

function AbortIfInvalidMoodleRoot {
    param($root)
    if (-not (Test-Path (Join-Path $root 'config.php'))) {
        Write-Error "The specified path does not look like a Moodle root (config.php not found): $root"
        exit 2
    }
}

function Copy-Plugin {
    param($source, $dest)
    if (-not (Test-Path $source)) {
        Write-Error "Source plugin folder not found: $source"
        exit 3
    }

    if (-not (Test-Path $dest)) {
        New-Item -ItemType Directory -Path $dest -Force | Out-Null
    }

    Write-Host "Copying plugin from $source to $dest"
    Copy-Item -Path (Join-Path $source '*') -Destination $dest -Recurse -Force
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
AbortIfInvalidMoodleRoot -root $MoodleRoot

# Determine destination: local plugin
$destLocal = Join-Path $MoodleRoot 'local\autocurriculum'
Copy-Plugin -source $scriptRoot -dest $destLocal

Write-Host "Plugin deployed to: $destLocal"
Write-Host "Next: In Moodle go to Site administration → Notifications to complete installation."
