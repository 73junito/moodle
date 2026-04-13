param(
    [string]$Version = 'v0.20.4',
    [string]$DestRoot = "$PSScriptRoot\bootstrap\ollama",
    [switch]$RunInstaller
)

Set-StrictMode -Off

function Log { param($m) $ts = (Get-Date).ToString('s'); Write-Host "[$ts] $m" }

Log "ollama setup: version=$Version dest=$DestRoot RunInstaller=$RunInstaller"

New-Item -ItemType Directory -Force -Path $DestRoot | Out-Null

$base = "https://github.com/ollama/ollama/releases/download/$Version"
$install = Join-Path $DestRoot 'install.ps1'
$sha = Join-Path $DestRoot 'sha256sum.txt'

# Use the secure download helper to fetch and verify the installer
$lib = Join-Path $PSScriptRoot 'lib\secure_download.ps1'
if (-not (Test-Path $lib)) { Write-Error "Missing helper: $lib"; exit 10 }
. $lib

try {
    $res = Get-SecureArtifact -Url "$base/install.ps1" -ChecksumUrl "$base/sha256sum.txt" -ExpectedName 'install.ps1' -OutFile $install -Algorithm SHA256 -Retries 2
} catch {
    Write-Error "Secure download failed: $_"
    exit 2
}

if (-not $res -or -not $res.Path) { Write-Error "Secure download did not return a result"; exit 3 }

Log "Download and verification succeeded. Installer available at: $($res.Path)"

# Record the verified hash for auditability
$hashFile = Join-Path $DestRoot 'verified_installer.sha256'
"$($res.Hash)  $(Split-Path -Leaf $res.Path)" | Out-File -FilePath $hashFile -Encoding UTF8 -Force
Log "Wrote verified hash to: $hashFile"

if ($RunInstaller) {
    Log "Running installer: $install"
    try {
        & pwsh -NoProfile -ExecutionPolicy Bypass -File $install
        $rc = $LASTEXITCODE
        Log "Installer exited with code $rc"
        exit $rc
    } catch {
        Write-Error "Installer failed: $_"
        exit 5
    }
} else {
    exit 0
}
