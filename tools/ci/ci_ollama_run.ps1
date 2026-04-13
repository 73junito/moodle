<#
CI-safe replacement for `ollama_sandbox_run.wsb` and `ollama-sandbox-autorun-full.wsb` behaviors.
Performs baseline captures, secure download/verify, optional non-elevated installer run, and post-capture diffs.
#>
param(
    [string]$Version = 'v0.20.4',
    [string]$OutRoot = "$PSScriptRoot\runs\ollama_run",
    [switch]$RunInstaller
)

Set-StrictMode -Off
function Log { param($m) $ts = (Get-Date).ToString('s'); Write-Host "[$ts] $m" }

New-Item -ItemType Directory -Force -Path $OutRoot | Out-Null

# baseline captures
try { Get-Process | Select Id,ProcessName,Path | Export-Csv -Path (Join-Path $OutRoot 'processes-before.csv') -NoTypeInformation -Force } catch {}
try { Get-Service | Select Name,Status,DisplayName | Export-Csv -Path (Join-Path $OutRoot 'services-before.csv') -NoTypeInformation -Force } catch {}
try { Get-NetTCPConnection -State Listen | Select LocalAddress,LocalPort,OwningProcess,State | Export-Csv -Path (Join-Path $OutRoot 'listening-before.csv') -NoTypeInformation -Force } catch {}

# Use secure helper to download installer
$lib = Join-Path $PSScriptRoot 'lib\\secure_download.ps1'
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
    Log "Attempting non-elevated installer run. Installer output captured in $OutRoot"
    try {
        & pwsh -NoProfile -ExecutionPolicy Bypass -File $install *>&1 | Tee-Object -FilePath (Join-Path $OutRoot 'install-output.txt')
    } catch {
        $_ | Out-File -FilePath (Join-Path $OutRoot 'install-error.txt') -Encoding UTF8
    }
}

# post captures
try { Get-Process | Select Id,ProcessName,Path | Export-Csv -Path (Join-Path $OutRoot 'processes-after.csv') -NoTypeInformation -Force } catch {}
try { Get-Service | Select Name,Status,DisplayName | Export-Csv -Path (Join-Path $OutRoot 'services-after.csv') -NoTypeInformation -Force } catch {}
try { Get-NetTCPConnection -State Listen | Select LocalAddress,LocalPort,OwningProcess,State | Export-Csv -Path (Join-Path $OutRoot 'listening-after.csv') -NoTypeInformation -Force } catch {}

# file diff for top-level scan paths
$scanPaths = @('C:\\Program Files','C:\\Program Files (x86)','C:\\ProgramData',$env:LOCALAPPDATA)
try {
    Get-ChildItem -Path $scanPaths -Recurse -File -ErrorAction SilentlyContinue | Select-Object FullName | Export-Csv -Path (Join-Path $OutRoot 'files-after.csv') -NoTypeInformation -Force
} catch { '' | Out-File (Join-Path $OutRoot 'files-after.csv') -Force }

try { Compare-Object (Import-Csv (Join-Path $OutRoot 'files-before.csv') -ErrorAction SilentlyContinue) (Import-Csv (Join-Path $OutRoot 'files-after.csv') -ErrorAction SilentlyContinue) | Out-File (Join-Path $OutRoot 'files-diff.txt') } catch {}

Log "Run complete. Artifacts are in: $OutRoot"
exit 0
