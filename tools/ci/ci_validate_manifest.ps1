param(
    [Parameter(Mandatory=$true)]
    [string]$ManifestPath,
    [switch]$ValidateOutputs,
    [switch]$EnforceRunDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "[validator] Validating manifest: $ManifestPath"

if (-not (Test-Path $ManifestPath)) {
    Write-Error "Manifest not found: $ManifestPath"
    exit 1
}

$json = Get-Content $ManifestPath -Raw | ConvertFrom-Json

# Basic required fields
$requiredFields = @('version','runId')
foreach ($f in $requiredFields) {
    if (-not $json.PSObject.Properties.Name -contains $f) {
        Write-Error "Manifest missing required field: $f"
        exit 1
    }
}

# Enforce allowed top-level properties (helps catch schema drift)
$allowed = @('version','runId','timestamp','inputs','outputs','logging','source')
$extra = $json.PSObject.Properties.Name | Where-Object { $allowed -notcontains $_ }
# Ensure $extra is treated as an array so Count works when only one extra property exists
if ($null -ne $extra -and (@($extra)).Count -gt 0) {
    $msg = "Manifest contains disallowed properties: $(@($extra) -join ', ')"
    Write-Host "::error::$msg"
    exit 1
}

$manifestDir = Split-Path -Parent $ManifestPath
$manifestDirFull = (Get-Item -LiteralPath $manifestDir).FullName.TrimEnd('\')

try {
    if ($EnforceRunDir) {
        $runFolder = Split-Path -Leaf $manifestDir
        if ($runFolder -ne $json.runId) {
            throw "Manifest runId '$($json.runId)' does not match containing folder '$runFolder'"
        }
    }

    # Helper: validate path entries (inputs/outputs)
    function Test-ManifestPaths {
        param(
            [Parameter(Mandatory=$true)]
            [object]$Items,
            [Parameter(Mandatory=$true)]
            [string]$Label
        )

        $result = [pscustomobject]@{
            Missing = @()
            Errors  = @()
        }

        if ($null -eq $Items) { return $result }

        if (-not ($Items -is [System.Array])) {
            $result.Errors += "Manifest '$Label' must be an array"
            return $result
        }

        foreach ($entry in $Items) {
            if (-not ($entry -is [string])) {
                $result.Errors += "Manifest $Label entry must be a string: $entry"
                continue
            }

            if ([System.IO.Path]::IsPathRooted($entry) -or $entry -match '\.\.') {
                $result.Errors += "Invalid $Label path (absolute or path traversal): $entry"
                continue
            }

            $p = Join-Path $manifestDir $entry
            $pFull = [System.IO.Path]::GetFullPath($p)
            if (-not $pFull.StartsWith($manifestDirFull, [System.StringComparison]::OrdinalIgnoreCase)) {
                $result.Errors += "$Label path escapes manifest directory: $entry"
                continue
            }

            if (-not (Test-Path $p)) { $result.Missing += $entry }
        }

        return $result
    }

    # Validate inputs (pre-run)
    $inputsRes = Test-ManifestPaths -Items $json.inputs -Label 'inputs'
    if ($inputsRes.Errors.Count -gt 0) { throw ($inputsRes.Errors -join '; ') }
    if ($inputsRes.Missing.Count -gt 0) { throw ("Missing input files declared in manifest: " + ($inputsRes.Missing -join ', ')) }

    # Validate outputs only when requested (two-phase validation)
    if ($ValidateOutputs) {
        $outputsRes = Test-ManifestPaths -Items $json.outputs -Label 'outputs'
        if ($outputsRes.Errors.Count -gt 0) { throw ($outputsRes.Errors -join '; ') }
        if ($outputsRes.Missing.Count -gt 0) { throw ("Missing output files declared in manifest: " + ($outputsRes.Missing -join ', ')) }
    }

    Write-Host "OK: manifest inputs present"
    if ($ValidateOutputs) { Write-Host "OK: manifest outputs present" }
    exit 0

} catch {
    $msg = $_.Exception.Message
    if (-not $msg) { $msg = $_.ToString() }
    Write-Host "::error::$msg"
    exit 1
}
