<#
CI-safe replacement for `ollama-sandbox-writable-autodownload.wsb`.
Deterministic, non-interactive: download + verify installer, optionally run installer (non-elevated).
#>
param(
    [string]$Version = 'v0.20.4',
    [string]$OutRoot = "$PSScriptRoot\bootstrap\ollama_writable",
    [switch]$RunInstaller
)

Set-StrictMode -Off
function Log { param($m) $ts = (Get-Date).ToString('s'); Write-Host "[$ts] $m" }

New-Item -ItemType Directory -Force -Path $OutRoot | Out-Null

# Use secure helper
$lib = Join-Path $PSScriptRoot 'lib\secure_download.ps1'
if (-not (Test-Path $lib)) { Write-Error "Missing helper: $lib"; exit 10 }
. $lib

$install = Join-Path $OutRoot 'install.ps1'

try {
    $res = Get-SecureArtifact -Url "https://github.com/ollama/ollama/releases/download/$Version/install.ps1" -ChecksumUrl "https://github.com/ollama/ollama/releases/download/$Version/sha256sum.txt" -ExpectedName 'install.ps1' -OutFile $install -Algorithm SHA256 -Retries 2
} catch {
    Write-Error "Secure download failed: $_"
    exit 2
}

Log "Installer verified at $($res.Path)"

if ($RunInstaller) {
    Log "Running installer (non-elevated). Output will be captured in $OutRoot"
    try {
        & pwsh -NoProfile -ExecutionPolicy Bypass -File $install *>&1 | Tee-Object -FilePath (Join-Path $OutRoot 'install-output.txt')
        $rc = $LASTEXITCODE
        Log "Installer exit code: $rc"
    } catch {
        $_ | Out-File -FilePath (Join-Path $OutRoot 'install-error.txt') -Encoding UTF8
        Log "Installer execution failed"
        exit 5
    }
}

Log "Artifacts written to: $OutRoot"
exit 0
