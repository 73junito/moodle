<#
run_policy_compiler.ps1

Minimal runner that uses AppLocker.PolicyCompiler.psm1 to:
 - parse audit + enforce XML
 - diff them
 - evaluate a workload sample and write a session-tagged report
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)] [string]$AuditPolicy,
    [Parameter(Mandatory=$true)] [string]$EnforcePolicy,
    [Parameter(Mandatory=$true)] [string]$WorkloadFile,

    [string]$SessionId = 'default',
    [string]$OutputRoot = '.\runs',

    [switch]$EmitOnly,
    [switch]$ValidateOnly
)

$repo = Split-Path -Parent $MyInvocation.MyCommand.Definition
Import-Module (Join-Path $repo 'AppLocker.PolicyCompiler.psm1') -Force

if (-not (Test-Path $AuditPolicy)) { Write-Error "Audit policy not found: $AuditPolicy"; exit 2 }
if (-not (Test-Path $EnforcePolicy)) { Write-Error "Enforce policy not found: $EnforcePolicy"; exit 3 }
if (-not (Test-Path $WorkloadFile)) { Write-Error "Workload file not found: $WorkloadFile"; exit 4 }

$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$sessionId = if ($PSBoundParameters.ContainsKey('SessionId') -and $SessionId) { $SessionId } else { $timestamp }

# Normalize OutputRoot relative to repo
if ([System.IO.Path]::IsPathRooted($OutputRoot)) { $outputRootFull = $OutputRoot } else { $outputRootFull = Join-Path $repo $OutputRoot }
New-Item -ItemType Directory -Force -Path $outputRootFull | Out-Null
$SessionFolder = Join-Path $outputRootFull "$sessionId`_$timestamp"
New-Item -ItemType Directory -Force -Path $SessionFolder | Out-Null
$outReport = Join-Path $SessionFolder "simulation.txt"

function Emit-PolicyIRToFile {
    param(
        $PolicyIR,
        [string]$FilePath,
        [switch]$ForEnforce
    )
    $xmlDoc = New-Object System.Xml.XmlDocument
    $policy = $xmlDoc.CreateElement('AppLockerPolicy')
    $policy.SetAttribute('Version','1')
    $xmlDoc.AppendChild($policy) | Out-Null

    if ($PolicyIR -and $PolicyIR.PSObject.Properties['Rules']) { $rules = $PolicyIR.Rules } else { $rules = $PolicyIR }
    if (-not $rules) { $xmlDoc.Save($FilePath); return }

    # Deterministic ordering: Tier -> RuleType -> Action -> RuleId
    $ordered = $rules | Sort-Object -Property @{Expression={"$($_.Tier)-$($_.RuleType)-$($_.Action)-$($_.RuleId)"}}

    $groups = $ordered | Group-Object -Property @{Expression={
        if ($_.PSObject.Properties['RuleType']) { $_.RuleType.ToString() } else { $_.Type }
    }}
    foreach ($g in $groups) {
        $rc = $xmlDoc.CreateElement('RuleCollection')
        $rc.SetAttribute('Type',$g.Name)
        $mode = 'AuditOnly'
        if ($ForEnforce) { $mode = 'Enforce' }
        $rc.SetAttribute('EnforcementMode', $mode)
        $policy.AppendChild($rc) | Out-Null

        foreach ($r in $g.Group) {
            # choose rule element type
            if ($r.PSObject.Properties['Condition']) {
                $cond = $r.Condition
            } else {
                $cond = $null
            }
            if ($cond -and $cond.Path) { $elName = 'FilePathRule' }
            elseif ($cond -and $cond.Publisher) { $elName = 'FilePublisherRule' }
            elseif ($r.PSObject.Properties['Hash']) { $elName = 'FileHashRule' }
            else { $elName = 'FilePathRule' }

            $fp = $xmlDoc.CreateElement($elName)
            $id = if ($r.PSObject.Properties['RuleId']) { $r.RuleId } elseif ($r.PSObject.Properties['Id']) { $r.Id } else { [guid]::NewGuid().ToString() }
            $desc = if ($r.PSObject.Properties['Description']) { $r.Description } elseif ($r.PSObject.Properties['Name']) { $r.Name } else { 'Auto-generated' }
            $action = if ($r.PSObject.Properties['Action']) { [string]$r.Action } else { 'Allow' }

            $fp.SetAttribute('Id', $id)
            $fp.SetAttribute('Name', $desc)
            $fp.SetAttribute('Description', $desc)
            $fp.SetAttribute('UserOrGroupSid','S-1-1-0')
            $fp.SetAttribute('Action', $action)

            $conds = $xmlDoc.CreateElement('Conditions')
            if ($elName -eq 'FilePathRule') {
                $c = $xmlDoc.CreateElement('FilePathCondition')
                $pathVal = if ($cond -and $cond.Path) { $cond.Path } elseif ($r.PSObject.Properties['Path']) { $r.Path } else { '%USERPROFILE%\*' }
                $c.SetAttribute('Path', $pathVal)
                $conds.AppendChild($c) | Out-Null
            }
            elseif ($elName -eq 'FilePublisherRule') {
                $c = $xmlDoc.CreateElement('FilePublisherCondition')
                $pub = if ($cond -and $cond.Publisher) { $cond.Publisher } else { $r.PublisherName }
                $c.SetAttribute('PublisherName', $pub)
                if ($r.PSObject.Properties['ProductName'] -and $r.ProductName) { $c.SetAttribute('ProductName', $r.ProductName) }
                if ($r.PSObject.Properties['BinaryName'] -and $r.BinaryName) { $c.SetAttribute('BinaryName', $r.BinaryName) }
                $conds.AppendChild($c) | Out-Null
            }
            else {
                $c = $xmlDoc.CreateElement('FileHashCondition')
                $hashVal = if ($cond -and $cond.Hash) { $cond.Hash } elseif ($r.PSObject.Properties['Hash']) { $r.Hash } else { '' }
                $c.InnerText = $hashVal
                $conds.AppendChild($c) | Out-Null
            }

            $fp.AppendChild($conds) | Out-Null
            $rc.AppendChild($fp) | Out-Null
        }
    }

    $xmlDoc.Save($FilePath)
}

Write-Host "Parsing policies..."
$auditRules = Parse-AppLockerPolicyXml -Path $AuditPolicy
$enforceRules = Parse-AppLockerPolicyXml -Path $EnforcePolicy

Write-Host "Diffing policies..."
$diff = Diff-Policies -OldRules $auditRules -NewRules $enforceRules

Write-Host "Loading workload..."
$workload = Get-Content -Path $WorkloadFile -Raw | ConvertFrom-Json

Write-Host "Evaluating workload against enforcement policy (simulation)..."

$results = Evaluate-Workload -PolicyRules $enforceRules -Workload $workload -Type 'Exe'

# Emit report

@(
    "Session: $sessionId",
    "AuditRules: $($(if ($auditRules -and $auditRules.PSObject.Properties['Rules']) { $auditRules.Rules.Count } else { ($auditRules | Measure-Object).Count }))",
    "EnforceRules: $($(if ($enforceRules -and $enforceRules.PSObject.Properties['Rules']) { $enforceRules.Rules.Count } else { ($enforceRules | Measure-Object).Count }))",
    "AddedRules: $($diff.Added.Count)",
    "RemovedRules: $($diff.Removed.Count)",
    "---",
    "Result | Path | Publisher | MatchedRule | Binary | TrustTier | TrustReason"
) | Out-File -FilePath $outReport -Encoding utf8

$results | ForEach-Object { "{0} | {1} | {2} | {3} | {4} | Tier{5} | {6}" -f $_.Result,$_.Path,$_.Publisher,$_.MatchedRule,$_.Binary,$_.TrustTier,$_.TrustReason } >> $outReport

Write-Host "Tier summary:"
$results | Group-Object -Property TrustTier | ForEach-Object { Write-Host "Tier$($_.Name): $($_.Count)" }

Write-Host "Simulation report written: $outReport"
Write-Host "Done."

# Dump IR for diagnostics
try {
    $irDumpPath = Join-Path $SessionFolder 'ir.json'
    if ($enforceRules -and $enforceRules.PSObject.Properties['Rules']) {
        $enforceRules.Rules | Select-Object RuleId,RuleType,Action,Tier,Scope,Description,@{Name='Condition';Expression={$_.Condition}} | ConvertTo-Json -Depth 5 | Out-File -FilePath $irDumpPath -Encoding utf8
    }
} catch { Write-Verbose "Failed to write IR dump: $_" }

# Synthesize Tier2 developer domain rules based on workload
Write-Host "Synthesizing Tier2 (Developer Domain) rule suggestions..."
$suggested = Synthesize-DeveloperDomainRules -WorkloadItems $workload
if ($suggested -and $suggested.Count -gt 0) {
    $tier2Path = Join-Path $SessionFolder 'tier2.xml'
    # Emit synthesized rules as IR->XML
    Emit-PolicyIRToFile -PolicyIR $suggested -FilePath $tier2Path
    Write-Host "Tier2 suggestions written to: $tier2Path"
    Add-Content -Path $outReport -Value "---`nTier2 suggestions: $tier2Path"
    foreach ($r in $suggested) { Add-Content -Path $outReport -Value "$($r.Description) => $($r.Condition.Path)" }
} else {
    Write-Host "No Tier2 suggestions generated."
}

# If EmitOnly or ValidateOnly flags are set, handle them now
if ($ValidateOnly) {
    $valReport = Join-Path $SessionFolder 'validation.txt'
    $v1 = Validate-PolicyIR -PolicyIR $auditRules
    $v2 = Validate-PolicyIR -PolicyIR $enforceRules
    @("AuditPolicy Validation: $($v1.Success)", ($v1.Errors -join "`n"), "---", "EnforcePolicy Validation: $($v2.Success)", ($v2.Errors -join "`n")) | Out-File -FilePath $valReport -Encoding utf8
    Write-Host "Validation results: $valReport"
    exit 0
}

if ($EmitOnly) {
    $auditOut = Join-Path $SessionFolder 'audit.xml'
    $enforceOut = Join-Path $SessionFolder 'enforce.xml'
    Emit-PolicyIRToFile -PolicyIR $auditRules -FilePath $auditOut
    Emit-PolicyIRToFile -PolicyIR $enforceRules -FilePath $enforceOut -ForEnforce
    Write-Host "Emitted audit/enforce XML to: $SessionFolder"
    exit 0
}
