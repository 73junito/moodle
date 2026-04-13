<#
.SYNOPSIS
  Self-healing AppLocker orchestrator: simulate → analyze → suggest → validate → emit

.DESCRIPTION
  Uses existing AppLocker Policy Compiler module to parse policy, analyze simulation
  output, synthesize minimal rules, validate diffs and emit candidate policy XML.

  Safety gates prevent broad automatic changes; AI suggestion hook is available but
  disabled by default.
#>

param(
    [Parameter(Mandatory=$true)] [string]$PolicyXml,
    [Parameter(Mandatory=$true)] [string]$SimulationReport,
    [switch]$DryRun,
    [switch]$AllowAI,
    [switch]$StrictMode,
    [string]$ReportPath
)

# Enforce report path contract when explicit path provided
if ($ReportPath) {
    if ($StrictMode -and ($ReportPath -notmatch '(?i)strict')) { throw "Strict mode requires 'strict' in ReportPath: $ReportPath" }
    if (-not $StrictMode -and ($ReportPath -notmatch '(?i)resilient')) { throw "Resilient mode requires 'resilient' in ReportPath: $ReportPath" }
}
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'AppLocker.PolicyCompiler.psm1') -Force -ErrorAction Stop

function Log { param($m) $ts = (Get-Date).ToString('s'); Write-Output "[$ts] $m" }

# Writes a CI-friendly validation report to runs/ir_validation_report.json (overwrites)
function Write-ValidationReport {
    param(
        $HealthResult,
        [bool]$StrictModeFlag = $false,
        [string]$OutDir = (Join-Path $PSScriptRoot 'runs'),
        [string]$RunMode = 'Resilient',
        [string]$PipelineVersion = 'self_heal_v1',
        [string]$ReportPath
    )

    # Determine final report path: explicit ReportPathParam wins; otherwise use OutDir with deterministic name
    if ($ReportPath) {
        $reportPath = $ReportPath
        $reportDir = Split-Path -Path $reportPath -Parent
        if (-not (Test-Path $reportDir)) { New-Item -Path $reportDir -ItemType Directory | Out-Null }
    } else {
        if (-not (Test-Path $OutDir)) { New-Item -Path $OutDir -ItemType Directory | Out-Null }
        # For CI determinism emit exact-named files for strict/resilient runs
        switch ($RunMode.ToLowerInvariant()) {
            'strict'   { $reportPath = Join-Path $OutDir 'ir_validation_report_strict.json' }
            'resilient'{ $reportPath = Join-Path $OutDir 'ir_validation_report_resilient.json' }
            default    { $ts = (Get-Date).ToString('yyyyMMdd_HHmmss'); $reportPath = Join-Path $OutDir ("ir_validation_report_{0}_{1}.json" -f $RunMode, $ts) }
        }
    }

    # Normalize malformed rules into serializable objects
    $malformed = @()
    if ($HealthResult -and $HealthResult.MalformedRules) {
        foreach ($m in @($HealthResult.MalformedRules)) {
            $malformed += [PSCustomObject]@{
                RuleId = ($m.RuleId -as [string])
                RawPath = ($m.Raw -as [string])
                NormalizedPath = ($m.Normalized -as [string])
                Error = ($m.Message -as [string])
            }
        }
    }

    $errors = @()
    if ($HealthResult -and $HealthResult.Errors) { $errors = @($HealthResult.Errors | ForEach-Object { $_ -as [string] }) }

    $out = [PSCustomObject]@{
        Timestamp = (Get-Date).ToUniversalTime().ToString('o')
        RunMode = $RunMode
        PipelineVersion = $PipelineVersion
        StrictMode = $StrictModeFlag
        IsValid = ($HealthResult -and $HealthResult.IsValid) -as [bool]
        RuleCount = if ($HealthResult) { $HealthResult.RuleCount } else { 0 }
        BaselineMissing = if ($HealthResult) { $HealthResult.BaselineMissing } else { $false }
        MalformedRuleCount = ($malformed).Count
        MalformedRules = $malformed
        Errors = $errors
    }

    try {
        $json = $out | ConvertTo-Json -Depth 6
        $json | Out-File -FilePath $reportPath -Encoding UTF8
        Log "IR validation report written: $reportPath"
    } catch {
        Log "Failed to write IR validation report: $($_.Exception.Message)"
        throw
    }
}

function Parse-SimulationReport {
    param([string]$Path)
    $lines = Get-Content -Path $Path -ErrorAction Stop
    $events = @()
    foreach ($line in $lines) {
        if ($line -match 'DENIED' -or $line -match 'blocked') {
            # Best-effort parse: pick a path-like token from the line
            $token = ($line -split '\s+' | Where-Object {$_ -like '*:\*' -or $_ -like '*\\*' } | Select-Object -First 1)
            if (-not $token) { $token = ($line -split '\s+' | Select-Object -First 2 -Last 1) }
            $events += [pscustomobject]@{ Raw = $line; Path = $token; Reason = 'Denied' }
        }
    }
    return @($events)
}

function Suggest-RulesFromEvents {
    param([array]$Events)
    $sugs = @()
    foreach ($e in $Events) {
        if (-not $e.Path) { continue }
        # prefer directory-level allow within moodle tree
        if ($e.Path -match '(?i)\\moodle\\') {
            $dir = (Split-Path -Path $e.Path -Parent)
            $sugs += [pscustomobject]@{
                RuleType = 'FilePath'
                Path = "$dir\\*"
                Action = 'Allow'
                Tier = 2
                Reason = 'Auto-synthesized for Moodle internal execution'
            }
        } else {
            # benign fallback: suggest file-level allow for invoking binary's parent
            $dir = (Split-Path -Path $e.Path -Parent)
            if ($dir) {
                $sugs += [pscustomobject]@{
                    RuleType = 'FilePath'
                    Path = "$dir\\*"
                    Action = 'Allow'
                    Tier = 2
                    Reason = 'Auto-synthesized from simulation event'
                }
            }
        }
    }
    return $sugs | Sort-Object Path -Unique
}

function Test-PolicyChange {
    param($OldIR, $NewIR, $MaxAdd=10)
    $diff = Compare-AppLockerIR -Left $OldIR -Right $NewIR
    $added = @($diff.Added).Count
    $removed = @($diff.Removed).Count
    $changed = @($diff.Changed).Count
    if ($added -gt $MaxAdd) { throw "Too many rules proposed: $added > $MaxAdd" }
    return $diff
}

function Merge-SuggestionsIntoIR {
    param($IR, $Suggestions)
    # Make a shallow copy via JSON for safe manipulation
    $irJson = $IR | ConvertTo-Json -Depth 10
    $new = $irJson | ConvertFrom-Json
    if (-not $new.Rules) { $new | Add-Member -MemberType NoteProperty -Name Rules -Value @() }

    # Helpers
    function Normalize-PathForKey { param($p) if (-not $p) { return $null } $s = $p.ToString().Trim(); $s = $s -replace '\\\\+','\\'; return $s.ToLowerInvariant() }

    # Collect candidates: existing rules + synthesized suggestions
    $candidates = @()
    foreach ($r in $new.Rules) { $candidates += $r }
    foreach ($s in $Suggestions) {
        $rule = [ordered]@{
            Id = ([guid]::NewGuid().ToString())
            Type = $s.RuleType
            Path = $s.Path
            Action = $s.Action
            Tier = $s.Tier
            Name = "auto-synth: $($s.Reason)"
        }
        $candidates += $rule
    }
    Write-Verbose "Merge-SuggestionsIntoIR: collected candidates: $((@($candidates)).Count)"

    # Deterministic dedupe by normalized key: Path + Action + Type
    $seen = @{}
    $merged = @()
    foreach ($r in $candidates) {
        try {
            $rp = $null
            if ($r -and (@($r.PSObject.Properties.Match('Path')).Count -gt 0)) { $rp = $r.Path }
            elseif ($r -and (@($r.PSObject.Properties.Match('Condition')).Count -gt 0)) { $rp = $r.Condition.Path }
            $ra = if ($r -and (@($r.PSObject.Properties.Match('Action')).Count -gt 0)) { $r.Action } else { $null }
            $rt = if ($r -and (@($r.PSObject.Properties.Match('Type')).Count -gt 0)) { $r.Type } else { $null }
            $key = ((Normalize-PathForKey $rp) + '|' + ($ra -as [string]) + '|' + ($rt -as [string]))
            if (-not $seen.ContainsKey($key)) { $seen[$key] = $true; $merged += $r }
        } catch { }
    }
    Write-Verbose "Merge-SuggestionsIntoIR: merged unique rules: $((@($merged)).Count)"

    # Ensure baseline allow rules exist exactly once (normalized), single source of truth
    $baselineRules = @('%SystemRoot%\System32\*','%SystemRoot%\*','%ProgramFiles%\*','%ProgramFiles(x86)%\*')
    foreach ($b in $baselineRules) {
        $normB = Normalize-PathForKey $b
        $found = $false
        foreach ($r in $merged) {
            try {
                $rp = $null
                if ($r -and (@($r.PSObject.Properties.Match('Path')).Count -gt 0)) { $rp = $r.Path }
                elseif ($r -and (@($r.PSObject.Properties.Match('Condition')).Count -gt 0)) { $rp = $r.Condition.Path }
                $ra = if ($r -and (@($r.PSObject.Properties.Match('Action')).Count -gt 0)) { $r.Action } else { $null }
                if ($rp -and (Normalize-PathForKey $rp -eq $normB) -and ($ra -ieq 'Allow')) { $found = $true; break }
            } catch { }
        }
        if (-not $found) {
            $merged += [ordered]@{
                Id = ([guid]::NewGuid().ToString())
                Type = 'FilePath'
                Path = $b
                Action = 'Allow'
                Tier = 0
                Name = 'baseline allow'
            }
        }
    }
    Write-Verbose "Merge-SuggestionsIntoIR: after baseline injection: $((@($merged)).Count)"
    Write-Verbose "Merge-SuggestionsIntoIR: merged entries listing:" 
    foreach ($r in $merged) {
        try {
            $rp = $null
            if ($r -and (@($r.PSObject.Properties.Match('Path')).Count -gt 0)) { $rp = $r.Path }
            elseif ($r -and (@($r.PSObject.Properties.Match('Condition')).Count -gt 0)) { $rp = $r.Condition.Path }
            $ra = if ($r -and (@($r.PSObject.Properties.Match('Action')).Count -gt 0)) { $r.Action } else { $null }
            $rt = if ($r -and (@($r.PSObject.Properties.Match('Type')).Count -gt 0)) { $r.Type } else { $null }
            Write-Verbose " - Path='$rp' Action='$ra' Type='$rt'"
        } catch { }
    }

    # Reorder: baseline rules first (in baselineRules order), then the rest deterministically sorted by normalized Path
    $baselineLower = $baselineRules | ForEach-Object { Normalize-PathForKey $_ }
    $ordered = @()
    foreach ($b in $baselineLower) {
        foreach ($r in $merged) {
            try {
                $rp = $null
                if ($r -and (@($r.PSObject.Properties.Match('Path')).Count -gt 0)) { $rp = $r.Path }
                elseif ($r -and (@($r.PSObject.Properties.Match('Condition')).Count -gt 0)) { $rp = $r.Condition.Path }
                if ($rp -and (Normalize-PathForKey $rp -eq $b)) { $ordered += $r }
            } catch { }
        }
    }
    foreach ($r in $merged) { if ($ordered -notcontains $r) { $ordered += $r } }

    # Normalize all rules into a single canonical IR shape before returning
    function Normalize-RuleObject {
        param($r)
        $outPath = $null
        $outAction = $null
        $outType = $null
        $outTier = 0
        $outId = $null
        $outName = $null

        if ($r -eq $null) { return $null }

        if ((@($r.PSObject.Properties['Condition']).Count -gt 0)) {
            try { $outPath = $r.Condition.Path } catch { $outPath = $null }
        }
        if ((@($r.PSObject.Properties['Path']).Count -gt 0)) { $outPath = $outPath ?? $r.Path }

        if ((@($r.PSObject.Properties['Action']).Count -gt 0)) {
            try { $outAction = $r.Action.ToString() } catch { $outAction = $r.Action }
        }
        if ((@($r.PSObject.Properties['RuleAction']).Count -gt 0)) { $outAction = $outAction ?? $r.RuleAction.ToString() }

        if ((@($r.PSObject.Properties['Type']).Count -gt 0)) { $outType = $r.Type }
        elseif ((@($r.PSObject.Properties['RuleType']).Count -gt 0)) { $outType = $r.RuleType }
        elseif ((@($r.PSObject.Properties['RuleTypeName']).Count -gt 0)) { $outType = $r.RuleTypeName }

        if ((@($r.PSObject.Properties['Tier']).Count -gt 0)) { $outTier = $r.Tier }
        if ((@($r.PSObject.Properties['Id']).Count -gt 0)) { $outId = $r.Id }
        if ((@($r.PSObject.Properties['RuleId']).Count -gt 0)) { $outId = $outId ?? $r.RuleId }
        if ((@($r.PSObject.Properties['Name']).Count -gt 0)) { $outName = $r.Name }
        if ((@($r.PSObject.Properties['Description']).Count -gt 0)) { $outName = $outName ?? $r.Description }

        if (-not $outPath -or -not $outAction) { return $null }

        # Coerce type names to friendly form
        if ($outType -is [int]) { $outType = 'FilePath' }
        if (-not $outType) { $outType = 'FilePath' }

        return [pscustomobject]@{
            Id = ($outId ?? ([guid]::NewGuid().ToString()))
            RuleId = ($outId ?? ([guid]::NewGuid().ToString()))
            Type = $outType
            RuleType = $outType
            Path = $outPath
            Condition = [pscustomobject]@{ Path = $outPath }
            Action = $outAction
            Tier = ($outTier -as [int])
            Name = ($outName ?? '')
        }
    }

    $canonical = @()
    foreach ($r in $ordered) {
        try {
            $n = Normalize-RuleObject -r $r
            if ($n) { $canonical += $n }
        } catch { }
    }

    $new.Rules = $canonical
    Write-Verbose "Merge-SuggestionsIntoIR: final rule count: $((@($new.Rules)).Count)"
    try { Write-Verbose "Merge-SuggestionsIntoIR: final rules JSON: $((@($new.Rules) | ConvertTo-Json -Depth 6))" } catch { }

    # Debug: output normalized final rules for inspection
    Write-Verbose "Merge-SuggestionsIntoIR: normalized final rules list:"
    foreach ($r in $new.Rules) {
        try {
            $rp = $r.Path
            $norm = Normalize-PathForKey $rp
            $ra = $r.Action
            Write-Verbose " - raw='$rp' norm='$norm' action='$ra'"
        } catch { }
    }

    # Debug: report baseline matching details
    foreach ($b in $baselineLower) {
        $matchesList = @()
        foreach ($r in $new.Rules) {
            try {
                $rp = $null
                if ((@($r.PSObject.Properties['Path']).Count -gt 0)) { $rp = $r.Path }
                elseif ((@($r.PSObject.Properties['Condition']).Count -gt 0)) { try { $rp = $r.Condition.Path } catch { $rp = $null } }
                $ra = if ((@($r.PSObject.Properties['Action']).Count -gt 0)) { $r.Action } else { $null }
                $match = $false
                if ($rp -and ($ra -and $ra -ieq 'Allow')) {
                    if ((Normalize-PathForKey $rp) -eq $b) { $match = $true }
                }
                Write-Verbose "Merge detail: comparing baseline '$b' against rule raw='$rp' norm='$(Normalize-PathForKey $rp)' action='$ra' -> match=$match"
                if ($match) { $matchesList += $r }
            } catch { }
        }
        $mcount = (@($matchesList)).Count
        $paths = $matchesList | ForEach-Object { if ((@($_.PSObject.Properties['Path']).Count -gt 0)) { $_.Path } elseif ((@($_.PSObject.Properties['Condition']).Count -gt 0)) { try { $_.Condition.Path } catch { '' } } else { '' } }
        Write-Verbose "Merge debug: baseline '$b' -> matches=$mcount paths=[$($paths -join ', ')]"
        if ($mcount -eq 0) { throw "Baseline invariant violation: missing baseline rule: $b" }
        if ($mcount -gt 1) { throw "Baseline invariant violation: duplicate baseline rule: $b" }
    }

    return $new
}

function Emit-CandidatePolicy {
    param($IR, $OutPath)
    # Ensure baseline rules exist in proper IR shape before emitting (AppLockerRuleIR or Condition.Path)
    function _normalizePath { param($p) if (-not $p) { return $null } $s = $p.ToString().Trim(); $s = $s -replace '\\\\+','\\'; return $s.ToLowerInvariant() }
    $baselineRules = @('%SystemRoot%\System32\*','%SystemRoot%\*','%ProgramFiles%\*','%ProgramFiles(x86)%\*')
    if ($IR -and $IR.PSObject.Properties['Rules']) { $rules = $IR.Rules } else { $rules = $IR }
    foreach ($b in $baselineRules) {
        $found = $false
        $normB = _normalizePath $b
        foreach ($r in $rules) {
            $rp = $null
            if (@($r.PSObject.Properties['Condition']).Count -gt 0) { $rp = $r.Condition.Path }
            elseif (@($r.PSObject.Properties['Path']).Count -gt 0) { $rp = $r.Path }
            if ($rp -and (_normalizePath $rp) -eq $normB) { $found = $true; break }
        }
        if (-not $found) {
            try {
                $cond = [AppLockerCondition]::new(@{ Path = $b })
                $cond.Path = $cond.Path
                $condHash = Get-ConditionHash -cond $cond
                $tier = [Tier]::Tier0
                $action = [RuleAction]::Allow
                $ruleType = [RuleType]::Exe
                $hex = if ($condHash) { $condHash.Substring(0,32) } else { [guid]::NewGuid().ToString().Replace('-','') }
                $id = '{0}-{1}-{2}-{3}-{4}' -f $hex.Substring(0,8),$hex.Substring(8,4),$hex.Substring(12,4),$hex.Substring(16,4),$hex.Substring(20,12)
                $ruleIR = [AppLockerRuleIR]::new($id, $ruleType, $action, $tier, $cond, 'All', 'baseline allow', [RuleSource]::Synth)
                $null = ($IR.Rules += $ruleIR)
            } catch {
                # best-effort: fall back to adding a simple PSCustomObject rule
                $IR.Rules += [PSCustomObject]@{ Id = ([guid]::NewGuid().ToString()); Type = 'FilePath'; Path = $b; Action = 'Allow'; Tier = 0; Name = 'baseline allow' }
            }
        }
    }

    try {
        Emit-PolicyIRToXml -PolicyIR $IR -FilePath $OutPath
    } catch {
        # Fallback: coerce to simple PSCustomObject shape expected by emitter
        Write-Verbose "Emit-PolicyIRToXml failed; falling back to constructed PSCustomObject for emit: $($_.Exception.Message)"
        $policy = [PSCustomObject]@{ Rules = @() }
        foreach ($r in $IR.Rules) {
            try {
                $pathVal = $null
                if ((@($r.PSObject.Properties['Condition']).Count -gt 0)) { $pathVal = $r.Condition.Path }
                elseif ((@($r.PSObject.Properties['Path']).Count -gt 0)) { $pathVal = $r.Path }
                $rid = if ((@($r.PSObject.Properties['RuleId']).Count -gt 0)) { $r.RuleId } elseif ((@($r.PSObject.Properties['Id']).Count -gt 0)) { $r.Id } else { [guid]::NewGuid().ToString() }
                $rname = if ((@($r.PSObject.Properties['Name']).Count -gt 0)) { $r.Name } elseif ((@($r.PSObject.Properties['Description']).Count -gt 0)) { $r.Description } else { 'Auto-generated' }
                $raction = if ((@($r.PSObject.Properties['Action']).Count -gt 0)) { $r.Action } else { 'Allow' }
                $ruleObj = [PSCustomObject]@{
                    RuleId = $rid
                    RuleType = if ((@($r.PSObject.Properties['RuleType']).Count -gt 0)) { $r.RuleType } else { if ((@($r.PSObject.Properties['Type']).Count -gt 0)) { $r.Type } else { 'FilePath' } }
                    Action = $raction
                    Tier = if ((@($r.PSObject.Properties['Tier']).Count -gt 0)) { $r.Tier } else { 0 }
                    Condition = [PSCustomObject]@{ Path = $pathVal }
                    Scope = 'All'
                    Description = $rname
                    Source = 0
                }
                $policy.Rules += $ruleObj
            } catch { }
        }
        Emit-PolicyIRToXml -PolicyIR $policy -FilePath $OutPath
    }
}

# Main execution with guaranteed reporting in a finally block
$script:LastError = $null
$script:Health = $null
$runMode = if ($StrictMode) { 'Strict' } else { 'Resilient' }
$exitCode = 0

try {
    Log "Loading policy: $PolicyXml"
    $ir = Parse-AppLockerPolicyXml -Path $PolicyXml

    Log "Parsing simulation report: $SimulationReport"
    $events = Parse-SimulationReport -Path $SimulationReport
    $evCount = @($events).Count
    Log "Detected $evCount denied events"

    if ($evCount -eq 0) { Log 'No denied events; nothing to suggest.'; exit 0 }

    Log 'Synthesizing suggestions (deterministic)'
    $suggestions = Suggest-RulesFromEvents -Events $events
    Log "Proposed $($suggestions.Count) suggestion(s)"

    if ($AllowAI -and $suggestions.Count -gt 0) {
        Log 'AI hook requested but disabled by default — implement Ollama call here.'
    }

    Log 'Merging suggestions into IR (shallow copy)'
    $newIR = Merge-SuggestionsIntoIR -IR $ir -Suggestions $suggestions

    Log 'Running IR health validator (resilient by default)'
    $script:Health = Assert-PolicyIRHealth -PolicyIR $newIR -RequireBaseline

    if ($script:Health -and -not $script:Health.IsValid) {
        if ($StrictMode) {
            $errMsg = if ($script:Health.Errors) { ($script:Health.Errors | ForEach-Object { $_ -as [string] }) -join '; ' } else { 'IR health check failed in strict mode' }
            Log "ERROR: IR health validation failed (strict mode): $errMsg"
            throw "IR health check failed in strict mode"
        } else {
            if ($script:Health.Errors -and $script:Health.Errors.Count -gt 0) { Log ("IR validator errors: " + (($script:Health.Errors | ForEach-Object { $_ -as [string] }) -join '; ')) }
            if ($script:Health.MalformedRules -and $script:Health.MalformedRules.Count -gt 0) {
                Log "IR validator: excluding $($script:Health.MalformedRules.Count) malformed rule(s) before continuing"
                $badIds = $script:Health.MalformedRules | ForEach-Object { $_.RuleId } | Where-Object { $_ }
                $badPaths = $script:Health.MalformedRules | ForEach-Object { $_.Raw } | Where-Object { $_ }
                $pruned = $newIR | ConvertTo-Json -Depth 10 | ConvertFrom-Json
                $pruned.Rules = $pruned.Rules | Where-Object {
                    $rid = if ($_.PSObject.Properties['RuleId']) { $_.RuleId } elseif ($_.PSObject.Properties['Id']) { $_.Id } else { $null }
                    $rp = if ($_.PSObject.Properties['Path']) { $_.Path } elseif ($_.PSObject.Properties['Condition']) { try { $_.Condition.Path } catch { $null } } else { $null }
                    if ($rid -and ($badIds -contains $rid)) { $false }
                    elseif ($rp -and ($badPaths -contains $rp)) { $false }
                    else { $true }
                }
                $newIR = $pruned
            }
        }
    }

    if (-not $suggestions -or $suggestions.Count -eq 0) {
        Log 'No suggestions generated; exiting.'
        exit 0
    }

    Log 'Validating policy change'
    $diff = Test-PolicyChange -OldIR $ir -NewIR $newIR -MaxAdd 20
    $added = @($diff.Added).Count
    $removed = @($diff.Removed).Count
    $changed = @($diff.Changed).Count
    Log "Diff summary: Added=$added Removed=$removed Changed=$changed"

    $outDir = Join-Path $PSScriptRoot 'runs'
    if (-not (Test-Path $outDir)) { New-Item -Path $outDir -ItemType Directory | Out-Null }
    $timestamp = (Get-Date).ToString('yyyyMMdd_HHmmss')
    $candidatePath = Join-Path $outDir "self_heal_candidate_$timestamp.xml"

    if ($DryRun) {
        Log "Dry-run: emitting candidate to $candidatePath (no apply)"
        Emit-CandidatePolicy -IR $newIR -OutPath $candidatePath
        Log 'Dry-run complete'
        exit 0
    }

    Log "Emitting candidate policy to $candidatePath"
    Emit-CandidatePolicy -IR $newIR -OutPath $candidatePath

    Log 'Run Pester tests to validate behavior (optional)'
    if (Get-Command Invoke-Pester -ErrorAction SilentlyContinue) {
        try { Invoke-Pester -Script tools/tests/PolicyCompiler.Tests.ps1 -PassThru | Out-Null; Log 'Pester tests ran' } catch { Log 'Pester tests failed or not configured' }
    }

    Log 'Candidate policy emitted. Manual review recommended before promotion.'
    exit 0
} catch {
    # Capture error and prepare fallback health for reporting; do NOT emit report here (finally will handle it)
    $script:LastError = $_
    $errMsg = $_.Exception | Out-String
    Log "ERROR: $errMsg"

    $script:Health = [PSCustomObject]@{
        IsValid = $false
        RuleCount = 0
        BaselineMissing = $true
        MalformedRules = @()
        Errors = @((($_.Exception.Message) -as [string]))
    }
    $exitCode = 2
} finally {
    # Ensure we always write a validation report (CI artifact) regardless of strict/resilient mode or fatal errors
    try {
        if (-not $script:Health) {
            $script:Health = [PSCustomObject]@{ IsValid = $false; RuleCount = 0; BaselineMissing = $true; MalformedRules = @(); Errors = @('No health result produced') }
        }
        Write-ValidationReport -HealthResult $script:Health -StrictModeFlag ([bool]$StrictMode) -RunMode $runMode -PipelineVersion 'self_heal_v1' -ReportPath $ReportPath
        Log 'IR validation report written (finally)'
    } catch {
        Log "Failed to write IR validation report in finally: $($_.Exception.Message)"
    }
}

# Exit with appropriate code when not already terminated by earlier exits
if ($exitCode -ne 0) { exit $exitCode } else { exit 0 }
 
