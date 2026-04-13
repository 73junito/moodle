param()

function Get-SecureArtifact {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)] [string]$Url,
        [Parameter(Mandatory=$true)] [string]$ChecksumUrl,
        [Parameter(Mandatory=$false)] [string]$ExpectedName,
        [Parameter(Mandatory=$true)] [string]$OutFile,
        [ValidateSet('SHA256','SHA1','MD5')]
        [string]$Algorithm = 'SHA256',
        [int]$Retries = 2,
        [int]$TimeoutSeconds = 60
    )

    function Log { param($m) $ts = (Get-Date).ToString('s'); Write-Host "[$ts] $m" }

    $tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
    New-Item -Path $tmpDir -ItemType Directory -Force | Out-Null
    $tmpFile = Join-Path $tmpDir ([System.IO.Path]::GetFileName($OutFile))
    $tmpChecksum = Join-Path $tmpDir 'checksum.txt'

    $attempt = 0
    while ($attempt -le $Retries) {
        try {
            Log "Downloading artifact: $Url"
            Invoke-WebRequest -Uri $Url -OutFile $tmpFile -TimeoutSec $TimeoutSeconds -ErrorAction Stop

            Log "Downloading checksum: $ChecksumUrl"
            Invoke-WebRequest -Uri $ChecksumUrl -OutFile $tmpChecksum -TimeoutSec $TimeoutSeconds -ErrorAction Stop

            break
        } catch {
            $attempt++
            if ($attempt -gt $Retries) {
                throw "Failed to download after $Retries attempts: $_"
            }
            Start-Sleep -Seconds 2
        }
    }

    # Parse checksum file: lines like '<hash>  filename' or '<hash> <filename>'
    $checksumLines = Get-Content -Path $tmpChecksum -ErrorAction Stop
    $selectedHash = $null
    foreach ($line in $checksumLines) {
        $m = [regex]::Match($line, '([0-9A-Fa-f]{32,128})\s+\*?(.+)$')
        if ($m.Success) {
            $hash = $m.Groups[1].Value.ToUpper()
            $name = $m.Groups[2].Value.Trim()
            if ($ExpectedName) {
                if ($name -eq $ExpectedName -or ([System.IO.Path]::GetFileName($name) -eq $ExpectedName)) { $selectedHash = $hash; break }
            } else {
                # if no expected name provided, accept first entry
                $selectedHash = $hash; break
            }
        }
    }

    if (-not $selectedHash) {
        throw "Could not find matching checksum for '$ExpectedName' in checksum file"
    }

    $computed = (Get-FileHash -Path $tmpFile -Algorithm $Algorithm -ErrorAction Stop).Hash.ToUpper()
    Log "Computed ${Algorithm}: $computed"
    Log "Expected ${Algorithm}: $selectedHash"

    if ($computed -ne $selectedHash) {
        $saved = Join-Path $tmpDir ([System.IO.Path]::GetFileName($OutFile) + '.mismatch')
        Copy-Item -Path $tmpFile -Destination $saved -Force
        throw "Hash mismatch — saved to $saved"
    }

    # Ensure destination dir exists
    $destDir = Split-Path -Parent $OutFile
    if (-not (Test-Path $destDir)) { New-Item -Path $destDir -ItemType Directory -Force | Out-Null }

    Move-Item -Path $tmpFile -Destination $OutFile -Force

    return @{ Path = $OutFile; Hash = $computed }
}

# Function is defined for dot-sourcing; no module export required.
