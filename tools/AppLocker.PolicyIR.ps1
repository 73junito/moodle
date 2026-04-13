# AppLocker.PolicyIR.ps1 - IR.v1 definitions and validation helpers
# IR.v1: authoritative intermediate representation for AppLocker policies

enum RuleType {
    Exe
    Dll
    Script
    Msi
    Appx
}

enum RuleAction {
    Allow
    Deny
}

enum Tier {
    Tier0
    Tier2
    Tier3
}

enum RuleSource {
    Audit
    Synth
    Manual
}

class AppLockerCondition {
    [string]$Path
    [string]$Publisher
    [string]$ProductName
    [string]$BinaryName
    [string]$Hash

    AppLockerCondition([hashtable]$h) {
        if ($null -ne $h.Path) { $this.Path = $h.Path }
        if ($null -ne $h.Publisher) { $this.Publisher = $h.Publisher }
        if ($null -ne $h.ProductName) { $this.ProductName = $h.ProductName }
        if ($null -ne $h.BinaryName) { $this.BinaryName = $h.BinaryName }
        if ($null -ne $h.Hash) { $this.Hash = $h.Hash }
    }
}

class AppLockerRuleIR {
    [string]$RuleId
    [RuleType]$RuleType
    [RuleAction]$Action
    [Tier]$Tier
    [AppLockerCondition]$Condition
    [string]$Scope
    [string]$Description
    [RuleSource]$Source

    AppLockerRuleIR([string]$id, [RuleType]$type, [RuleAction]$action, [Tier]$tier, [AppLockerCondition]$cond, [string]$scope, [string]$desc, [RuleSource]$src) {
        $this.RuleId = $id
        $this.RuleType = $type
        $this.Action = $action
        $this.Tier = $tier
        $this.Condition = $cond
        $this.Scope = $scope
        $this.Description = $desc
        $this.Source = $src
    }
}

class AppLockerPolicyIR {
    [AppLockerRuleIR[]]$Rules
    [string]$PolicyVersion

    AppLockerPolicyIR() {
        $this.Rules = @()
        $this.PolicyVersion = 'IR.v1'
    }
}

function Normalize-ConditionPath {
    param(
        [string]$path,
        [string]$ruleId = $null
    )
    if ([string]::IsNullOrWhiteSpace($path)) { return $null }
    # Follow strict sequence: raw -> trim -> quote-check/strip -> collapse slashes -> token normalize -> lowercase -> validate -> emit
    $orig = $path

    # Trim surrounding whitespace first
    $p = $path.Trim()

    # Detect unbalanced quotes BEFORE changing them
    $startsWithQuote = $p.StartsWith('"')
    $endsWithQuote = $p.EndsWith('"')
    if ($startsWithQuote -xor $endsWithQuote) {
        $ex = [System.ArgumentException]::new('Unbalanced quotes in path', 'path')
        $ex.Data['Raw'] = $orig
        $ex.Data['Normalized'] = $p
        if ($ruleId) { $ex.Data['RuleId'] = $ruleId }
        throw $ex
    }

    # Strip surrounding quotes if present
    if ($startsWithQuote -and $endsWithQuote) { $p = $p.Trim('"') }

    # Collapse duplicate backslashes
    $p = $p -replace '\\+','\\'

    # Expand common tokens to canonical forms (keep other tokens intact)
    $p = $p -replace '%OSDRIVE%','C:'
    $p = $p -replace '%SystemRoot%','C:\\Windows'

    $p = $p.ToLower()

    # Validation: control characters
    if ($p -match "[\r\n\t]") {
        $ex = [System.ArgumentException]::new('Path contains control characters', 'path')
        $ex.Data['Raw'] = $orig
        $ex.Data['Normalized'] = $p
        if ($ruleId) { $ex.Data['RuleId'] = $ruleId }
        throw $ex
    }

    # Embedded quotes after trimming are not allowed
    if ($p -match '"') {
        $ex = [System.ArgumentException]::new('Path contains embedded quote characters', 'path')
        $ex.Data['Raw'] = $orig
        $ex.Data['Normalized'] = $p
        if ($ruleId) { $ex.Data['RuleId'] = $ruleId }
        throw $ex
    }

    # Final empty check
    if ([string]::IsNullOrWhiteSpace($p)) {
        $ex = [System.ArgumentException]::new('Path is empty after normalization', 'path')
        $ex.Data['Raw'] = $orig
        $ex.Data['Normalized'] = $p
        if ($ruleId) { $ex.Data['RuleId'] = $ruleId }
        throw $ex
    }

    return $p
}

function Canonicalize-Publisher {
    param([string]$pub)
    if ($null -eq $pub) { return $null }
    $s = $pub.Trim()
    if ($s -eq '') { return $null }
    # collapse multi-space, trim
    $s = $s -replace '\s+',' '
    return $s
}

function Get-ConditionHash {
    param([AppLockerCondition]$cond)
    # Deterministic hash for deduplication
    $parts = @()
    if ($cond.Path) { $parts += (Normalize-ConditionPath $cond.Path) }
    if ($cond.Publisher) { $parts += (Canonicalize-Publisher $cond.Publisher) }
    if ($cond.ProductName) { $parts += $cond.ProductName.ToLower() }
    if ($cond.BinaryName) { $parts += $cond.BinaryName.ToLower() }
    if ($cond.Hash) { $parts += $cond.Hash }
    $joined = ($parts -join '|')
    if ([string]::IsNullOrEmpty($joined)) { return $null }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($joined)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $hash = $sha.ComputeHash($bytes)
    return ([System.BitConverter]::ToString($hash)).Replace('-','').ToLower()
}

function Validate-PolicyIR {
    <#
    Validate-PolicyIR -PolicyIR <AppLockerPolicyIR>
    Returns: [bool] success, [array] errors
    #>
    param([AppLockerPolicyIR]$PolicyIR)

    $errors = @()
    if ($null -eq $PolicyIR) { $errors += 'PolicyIR is null'; return @{ Success = $false; Errors = $errors } }
    if ($null -eq $PolicyIR.Rules) { $errors += 'PolicyIR.Rules is null'; return @{ Success = $false; Errors = $errors } }

    $seen = @{}
    foreach ($r in $PolicyIR.Rules) {
        if (-not $r.RuleId) { $errors += "Rule missing RuleId"; continue }
        try { [guid]::Parse($r.RuleId) } catch { $errors += "Rule $($r.RuleId): invalid GUID" }
        if (-not ($r.RuleType -is [RuleType])) { $errors += "Rule $($r.RuleId): invalid RuleType" }
        if (-not ($r.Action -is [RuleAction])) { $errors += "Rule $($r.RuleId): invalid Action" }
        if (-not ($r.Tier -is [Tier])) { $errors += "Rule $($r.RuleId): invalid Tier" }
        if (-not $r.Description) { $errors += "Rule $($r.RuleId): missing Description" }
        if ($r.Condition -eq $null) { $errors += "Rule $($r.RuleId): missing Condition" }
        else {
            # Normalize path and publisher
            if ($r.Condition.Path) {
                try { $r.Condition.Path = Normalize-ConditionPath $r.Condition.Path $r.RuleId }
                catch [System.ArgumentException] { $errors += "Rule $($r.RuleId): invalid Path - $($_.Exception.Message)"; continue }
            }
            if ($r.Condition.Publisher) { $r.Condition.Publisher = Canonicalize-Publisher $r.Condition.Publisher }
        }

        # Duplicate detection key
        $condHash = Get-ConditionHash -cond $r.Condition
        $key = "{0}|{1}|{2}|{3}" -f $r.RuleType, $r.Action, $condHash, $r.Scope
        if ($condHash -ne $null) {
            if ($seen.ContainsKey($key)) { $errors += "Duplicate rule detected: $($r.RuleId) (key $key)" }
            else { $seen[$key] = $r.RuleId }
        }
    }

    $success = ($errors.Count -eq 0)
    return @{ Success = $success; Errors = $errors }
}

Export-ModuleMember -Function Normalize-ConditionPath,Canonicalize-Publisher,Get-ConditionHash,Validate-PolicyIR,Assert-PolicyIRHealth

function Assert-PolicyIRHealth {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)] $PolicyIR,
        [int]$MinValidRules = 1,
        [switch]$RequireBaseline
    )

    # Pure validator: does NOT mutate the provided PolicyIR. Returns a PSCustomObject with
    # fields: IsValid, RuleCount, BaselineMissing, MalformedRules, Errors
    $errors = @()
    $malformed = @()
    $ruleCount = 0
    if ($null -eq $PolicyIR -or $null -eq $PolicyIR.Rules) {
        $errors += 'PolicyIR or PolicyIR.Rules is null'
        return [PSCustomObject]@{
            IsValid = $false
            RuleCount = 0
            BaselineMissing = $true
            MalformedRules = ,@()
            Errors = $errors
        }
    }

    $ruleCount = @($PolicyIR.Rules).Count

    foreach ($r in $PolicyIR.Rules) {
        # Basic shape checks
        $rid = if ($r.PSObject.Properties['RuleId']) { $r.RuleId } elseif ($r.PSObject.Properties['Id']) { $r.Id } else { $null }
        $pathRaw = $null
        try {
            if ($r.PSObject.Properties['Condition']) { $pathRaw = ($r.Condition.Path) 2>$null }
            elseif ($r.PSObject.Properties['Path']) { $pathRaw = ($r.Path) 2>$null }
        } catch { $pathRaw = $null }

        # Validate path by attempting Normalize-ConditionPath but do NOT assign back to object
        if ($pathRaw) {
            try {
                $norm = Normalize-ConditionPath $pathRaw $rid
            } catch [System.ArgumentException] {
                $malformed += [PSCustomObject]@{
                    RuleId = $rid
                    Raw = $pathRaw
                    Normalized = ($_.Exception.Data['Normalized'] -or $null)
                    Message = $_.Exception.Message
                }
                continue
            } catch {
                $malformed += [PSCustomObject]@{ RuleId = $rid; Raw = $pathRaw; Normalized = $null; Message = $_.Exception.Message }
                continue
            }
        }

        # Minimal required fields validation
        try {
            if (-not $rid) { $errors += "Rule missing RuleId" }
            if (-not ($r.RuleType -is [RuleType] -or $r.PSObject.Properties['Type'])) { $errors += "Rule ${rid}: invalid or missing RuleType" }
            if (-not ($r.Action -is [RuleAction] -or $r.PSObject.Properties['Action'])) { $errors += "Rule ${rid}: invalid or missing Action" }
        } catch { $errors += "Rule ${rid}: unexpected validation error - $($_.Exception.Message)" }
    }

    $baselineMissing = $false
    if ($RequireBaseline) {
        $baselineFound = $false
        foreach ($r in $PolicyIR.Rules) {
            if ($r.PSObject.Properties['Description'] -and ($r.Description -match 'baseline')) { $baselineFound = $true; break }
            if ($r.PSObject.Properties['Name'] -and ($r.Name -match 'baseline')) { $baselineFound = $true; break }
        }
        if (-not $baselineFound) { $baselineMissing = $true }
    }

    $isValid = ($errors.Count -eq 0) -and ($malformed.Count -eq 0) -and (-not $baselineMissing) -and ($ruleCount -ge $MinValidRules)

    return [PSCustomObject]@{
        IsValid = $isValid
        RuleCount = $ruleCount
        BaselineMissing = $baselineMissing
        MalformedRules = ,$malformed
        Errors = ,$errors
    }
}
