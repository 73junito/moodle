param(
    [string]$Root = ".",
    [string]$OutDir = "tools\\runs"
)

Set-StrictMode -Version Latest

function Log { param($m) $ts = (Get-Date).ToString('s'); Write-Host "[$ts] $m" }

Log "Checking for implicit report paths under: $Root"

$violations = @()

# Only scan PowerShell scripts (reduce noise)
# Resolve absolute OutDir (if present) and exclude run-artifacts under it to avoid scanning generated files
$absOut = $null
try { $absOut = (Resolve-Path -LiteralPath $OutDir -ErrorAction SilentlyContinue).ProviderPath } catch { }

$files = Get-ChildItem -Path $Root -Recurse -Include *.ps1 -File -ErrorAction SilentlyContinue |
    Where-Object {
        if ($absOut) {
            $_.FullName -notmatch '\\tools\\legacy\\wsb\\' -and ($_.FullName -notlike ("$absOut*")) -and $_.Length -lt 1MB
        } else {
            $_.FullName -notmatch '\\tools\\legacy\\wsb\\' -and ($_.FullName -notmatch [regex]::Escape($OutDir)) -and $_.Length -lt 1MB
        }
    }

foreach ($f in $files) {
    # use a safe, single-quoted regex pattern based on OutDir to avoid PowerShell parsing traps
    $escapedOutDir = [regex]::Escape($OutDir)
    $pattern = "$escapedOutDir\\\\S+\.json"

    try {
        $matched = $false
        Get-Content -Path $f.FullName -ReadCount 100 -ErrorAction Stop | ForEach-Object {
            foreach ($line in $_) {
                if ($line -match $pattern) {
                    if ($line -notmatch '-ReportPath' -and $line -notmatch '\$OutDir' -and $line -notmatch '\$RunId' -and $line -notmatch 'Join-Path\s+\$OutDir') {
                        $violations += [PSCustomObject]@{ File = $f.FullName; Issue = 'Implicit tools/runs JSON path without ReportPath/OutDir/RunId'; Line = $line.Trim() }
                        $matched = $true
                        break
                    }
                }

                # catch simple hardcoded literal assignments referencing tools/runs
                if ($line -match '\$[A-Za-z_]\w*\s*=') {
                    if ($line -match 'tools\\runs\\') {
                        if ($line -notmatch '-ReportPath' -and $line -notmatch '\$OutDir' -and $line -notmatch '\$RunId') {
                            $violations += [PSCustomObject]@{ File = $f.FullName; Issue = 'Literal assignment to tools/runs path without ReportPath/OutDir/RunId'; Line = $line.Trim() }
                            $matched = $true
                            break
                        }
                    }
                }
            }
            if ($matched) { break }
        }
    } catch {
        continue
    }
}

if (@($violations).Count -gt 0) {
    Write-Host "FAIL: Implicit report paths detected" -ForegroundColor Red
    $violations | Sort-Object File | Format-Table -AutoSize
    Write-Host "\nUse -ReportPath or a run-scoped OutDir/RunId when writing CI artifacts." -ForegroundColor Yellow
    exit 1
}

Write-Host "OK: no implicit report paths found" -ForegroundColor Green
exit 0
