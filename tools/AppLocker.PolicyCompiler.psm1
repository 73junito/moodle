. (Join-Path $PSScriptRoot 'AppLocker.PolicyIR.ps1')

function Parse-AppLockerPolicyXml {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)] [string]$Path
    )
    if (-not (Test-Path $Path)) { throw "Policy file not found: $Path" }
    

    [xml]$xml = Get-Content -Path $Path -Raw

    $policyIR = [AppLockerPolicyIR]::new()
    $seen = @{}

    # Namespace-agnostic selection of RuleCollection nodes
    $rcNodes = $xml.SelectNodes("//*[local-name()='RuleCollection']")
    Write-Verbose "Found $($rcNodes.Count) RuleCollection nodes in $Path"

    foreach ($rc in $rcNodes) {
        # Get Type attribute robustly
        $typeStr = $null
        if ($rc.Attributes -and $rc.Attributes['Type']) { $typeStr = $rc.Attributes['Type'].Value }
        elseif ($rc.SelectSingleNode("@Type")) { $typeStr = $rc.SelectSingleNode("@Type").Value }
        if (-not $typeStr) { $typeStr = 'Exe' }

        # Map to RuleType enum (safe)
        try { $ruleType = [RuleType]::Parse([string]$typeStr) } catch { $ruleType = [RuleType]::Exe }

        # Enumerate child rule nodes regardless of namespace/local-name
        $ruleNodes = $rc.SelectNodes("*/*[local-name()!='Conditions'] | *[local-name()!='Conditions']")
        if (-not $ruleNodes -or $ruleNodes.Count -eq 0) {
            $ruleNodes = $rc.ChildNodes
        }

        foreach ($node in $ruleNodes) {
            $id = $null; $name = $null; $actionStr = $null
            if ($node.Attributes) {
                if ($node.Attributes['Id']) { $id = $node.Attributes['Id'].Value }
                if ($node.Attributes['Name']) { $name = $node.Attributes['Name'].Value }
                if ($node.Attributes['Action']) { $actionStr = $node.Attributes['Action'].Value }
            }

            $publisherCond = $node.SelectSingleNode(".//*[local-name()='FilePublisherCondition']")
            $pathCond = $node.SelectSingleNode(".//*[local-name()='FilePathCondition']")
            $hashCond = $node.SelectSingleNode(".//*[local-name()='FileHashCondition']")

            $cond = $null
            if ($publisherCond) {
                $pubName = $publisherCond.GetAttribute('PublisherName') 2>$null
                $prodName = $publisherCond.GetAttribute('ProductName') 2>$null
                $binName = $publisherCond.GetAttribute('BinaryName') 2>$null
                $cond = [AppLockerCondition]::new(@{ Publisher = $pubName; ProductName = $prodName; BinaryName = $binName })
            }
            elseif ($pathCond) {
                $path = $pathCond.GetAttribute('Path') 2>$null
                if (-not $path) { $path = $pathCond.InnerText }
                $cond = [AppLockerCondition]::new(@{ Path = $path })
            }
            elseif ($hashCond) {
                $hash = $hashCond.InnerText
                $cond = [AppLockerCondition]::new(@{ Hash = $hash })
            }
            else {
                # Unknown rule shape — skip
                continue
            }

            # Normalize condition and compute deterministic id if missing
            if ($cond.Path) {
                # Pass rule id when available to provide context for validation errors.
                try {
                    $cond.Path = Normalize-ConditionPath $cond.Path $id
                } catch [System.ArgumentException] {
                    # For imported XML rules, treat malformed paths as fatal to ingestion so callers
                    # can decide whether to reject the candidate. Re-throw with context.
                    $_.Exception.Data['XmlNode'] = $node.OuterXml 2>$null
                    throw $_.Exception
                }
            }
            if ($cond.Publisher) { $cond.Publisher = Canonicalize-Publisher $cond.Publisher }

            $condHash = Get-ConditionHash -cond $cond
            if ($id) {
                # ensure GUID format (assign to temp to avoid emitting to pipeline)
                try { $tmpGuid = [guid]::Parse($id) } catch { $id = $null }
            }
            if (-not $id -and $condHash) {
                $hex = $condHash.Substring(0,32)
                $id = '{0}-{1}-{2}-{3}-{4}' -f $hex.Substring(0,8),$hex.Substring(8,4),$hex.Substring(12,4),$hex.Substring(16,4),$hex.Substring(20,12)
            }
            if (-not $id) { $id = [guid]::NewGuid().ToString() }

            # Deduplicate by condition hash + type
            $dedupKey = "{0}|{1}" -f $ruleType, $condHash
            if ($condHash -and $seen.ContainsKey($dedupKey)) { Write-Verbose "Skipping duplicate rule for key $dedupKey"; continue }
            if ($condHash) { $null = ($seen[$dedupKey] = $id) }

            # Map action (use explicit fallback, avoid boolean -or misuse)
            $actionVal = $actionStr
            if (-not $actionVal) { $actionVal = 'Allow' }
            try { $action = [RuleAction]::Parse([string]$actionVal) } catch { $action = [RuleAction]::Allow }

            # Infer tier
            $tier = [Tier]::Tier3
            if ($cond.Publisher) {
                if ($cond.Publisher -match 'Microsoft') { $tier = [Tier]::Tier0 }
                else { $tier = [Tier]::Tier2 }
            }
            elseif ($cond.Path) {
                if ($cond.Path -match 'c:\\windows|%systemroot%|c:\\program files') { $tier = [Tier]::Tier0 }
                elseif ($cond.Path -match 'miniconda|python|nodejs') { $tier = [Tier]::Tier2 }
            }

            # Coerce description/name properly (avoid boolean -or operator)
            if ($name) { $desc = [string]$name } else { $desc = "Auto-generated from XML import" }
            $scope = 'All'
            $source = [RuleSource]::Audit

            $ruleIR = [AppLockerRuleIR]::new($id, $ruleType, $action, $tier, $cond, $scope, $desc, $source)

            # Ensure normalized identifier properties exist on the IR object for downstream tools/tests.
            # Provide both `Id` and `RuleId` and a stable `Name` for compatibility.
            try {
                if (-not ($ruleIR.PSObject.Properties['Id'])) { Add-Member -InputObject $ruleIR -NotePropertyName Id -NotePropertyValue $id -Force | Out-Null }
                else { $ruleIR.Id = $id }
                if (-not ($ruleIR.PSObject.Properties['RuleId'])) { Add-Member -InputObject $ruleIR -NotePropertyName RuleId -NotePropertyValue $id -Force | Out-Null }
                else { $ruleIR.RuleId = $id }
                $stableName = $null
                if ($name) { $stableName = [string]$name }
                if (-not $stableName -and $desc) { $stableName = [string]$desc }
                if (-not $stableName) { $stableName = "rule-$($id.Substring(0,8))" }
                if (-not ($ruleIR.PSObject.Properties['Name'])) { Add-Member -InputObject $ruleIR -NotePropertyName Name -NotePropertyValue $stableName -Force | Out-Null }
                else { $ruleIR.Name = $stableName }
            } catch {
                # Be resilient in case AppLockerRuleIR is a sealed/immutable CLR object; avoid emitting metadata to pipeline.
                $null = [PSCustomObject]@{ Id = $id; RuleId = $id; Name = ($name -or $desc -or ("rule-$($id.Substring(0,8))")) }
            }

            $null = ($policyIR.Rules += $ruleIR)
        }
    }

    # Ensure canonical return shape: always return an object with a Rules array
    $ruleArray = @()
    if ($policyIR -and $policyIR.PSObject.Properties['Rules']) { $ruleArray = @($policyIR.Rules) }
    elseif ($policyIR -is [System.Array]) { $ruleArray = @($policyIR) }

    Write-Verbose "Parsed $($ruleArray.Count) IR rules from $Path"

    $canonical = [PSCustomObject]@{
        Rules = $ruleArray
        PolicyVersion = if ($policyIR -and $policyIR.PSObject.Properties['PolicyVersion']) { $policyIR.PolicyVersion } else { 'IR.v1' }
    }

    return $canonical
}

function Simulate-Execution {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)] [array]$PolicyRules,
        [Parameter(Mandatory=$true)] [string]$Type,
        [Parameter(Mandatory=$true)] [string]$FilePath,
        [string]$PublisherName,
        [string]$ProductName,
        [string]$BinaryName
    )

    # Accept either AppLockerPolicyIR or array of rule-like objects
    if ($PolicyRules -is [AppLockerPolicyIR]) { $rules = $PolicyRules.Rules } else { $rules = $PolicyRules }

    # Map Type string to enum if possible
    try { $wantedType = [RuleType]::Parse($Type) } catch { $wantedType = $null }

    foreach ($r in $rules) {
        $rType = $null
        if ($r -is [AppLockerRuleIR]) { $rType = $r.RuleType } elseif ($r.Type) { try { $rType = [RuleType]::Parse($r.Type) } catch { $rType = $null } }
        if ($wantedType -ne $null -and $rType -ne $null -and $rType -ne $wantedType) { continue }

        # Path condition
        $rPath = $null
        if ($r -is [AppLockerRuleIR]) { $rPath = $r.Condition.Path } elseif ($r.Path) { $rPath = $r.Path }
        if ($rPath) {
            $pattern = [Environment]::ExpandEnvironmentVariables($rPath)
            # Normalize duplicate backslashes that can occur when tokens and literals combine
            $patternNorm = $pattern -replace '\\+','\\'
            $fpNorm = $FilePath -replace '\\+','\\'
            if ($fpNorm -like $patternNorm) { return @{ Result='Allow'; Rule=$r } }
        }

        # Publisher condition
        $rPub = $null; $rProd = $null; $rBin = $null
        if ($r -is [AppLockerRuleIR]) { $rPub = $r.Condition.Publisher; $rProd = $r.Condition.ProductName; $rBin = $r.Condition.BinaryName }
        else { $rPub = $r.PublisherName; $rProd = $r.ProductName; $rBin = $r.BinaryName }
        if ($rPub -and $PublisherName -and $PublisherName -like "*$rPub*") {
            $prodMatch = (-not $rProd -or $rProd -eq '*' -or $ProductName -like $rProd)
            $binMatch = (-not $rBin -or $rBin -eq '*' -or $BinaryName -like $rBin)
            if ($prodMatch -and $binMatch) { return @{ Result='Allow'; Rule=$r } }
        }
    }

    return @{ Result='Deny'; Rule=$null }
}

function Diff-Policies {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)] [array]$OldRules,
        [Parameter(Mandatory=$true)] [array]$NewRules
    )
    if ($OldRules -is [AppLockerPolicyIR]) { $old = $OldRules.Rules } else { $old = $OldRules }
    if ($NewRules -is [AppLockerPolicyIR]) { $new = $NewRules.Rules } else { $new = $NewRules }

    $oldIds = @()
    foreach ($o in $old) {
        if ($o.PSObject.Properties['RuleId']) { $oldIds += $o.RuleId }
        elseif ($o.PSObject.Properties['Id']) { $oldIds += $o.Id }
    }
    $newIds = @()
    foreach ($n in $new) {
        if ($n.PSObject.Properties['RuleId']) { $newIds += $n.RuleId }
        elseif ($n.PSObject.Properties['Id']) { $newIds += $n.Id }
    }

    $added = @()
    foreach ($n in $new) {
        $nid = if ($n.PSObject.Properties['RuleId'] ) { $n.RuleId } elseif ($n.PSObject.Properties['Id']) { $n.Id } else { $null }
        if ($nid -and ($oldIds -notcontains $nid)) { $added += $n }
    }

    $removed = @()
    foreach ($o in $old) {
        $oid = if ($o.PSObject.Properties['RuleId'] ) { $o.RuleId } elseif ($o.PSObject.Properties['Id']) { $o.Id } else { $null }
        if ($oid -and ($newIds -notcontains $oid)) { $removed += $o }
    }
    [PSCustomObject]@{
        OldCount = $old.Count
        NewCount = $new.Count
        Added = $added
        Removed = $removed
    }
}

function Evaluate-Workload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)] [array]$PolicyRules,
        [Parameter(Mandatory=$true)] [array]$Workload,
        [string]$Type = 'Exe'
    )
    $results = @()
    foreach ($item in $Workload) {
        $fp = $item.Path
        $res = Simulate-Execution -PolicyRules $PolicyRules -Type $Type -FilePath $fp -PublisherName $item.PublisherName -ProductName $item.ProductName -BinaryName $item.BinaryName
        $tier = Get-TrustTier -Rule $res.Rule -WorkloadItem $item -Result $res
        $matchedName = $null
        if ($res.Rule) {
            if ($res.Rule -is [AppLockerRuleIR]) { $matchedName = $res.Rule.Description } else { $matchedName = $res.Rule.Name }
        }
        $results += [PSCustomObject]@{
            Path = $fp
            Publisher = $item.PublisherName
            Product = $item.ProductName
            Binary = $item.BinaryName
            Result = $res.Result
            MatchedRule = $matchedName
            TrustTier = $tier.Tier
            TrustReason = $tier.Reason
        }
    }
    return $results
}

function Get-TrustTier {
    [CmdletBinding()]
    param(
        [object]$Rule,
        [object]$WorkloadItem,
        [object]$Result
    )
    # Tiers:
    # 0 - OS / Microsoft
    # 1 - Trusted vendors (Google, Adobe, Mozilla)
    # 2 - Developer runtime (Python, Conda, Node, Git tooling)
    # 3 - User-local unsigned / untrusted
    # 4 - Unknown / blocked

    $tier = 4
    $reason = 'Unknown'

    if ($null -ne $Rule) {
        if ($Rule -is [AppLockerRuleIR]) {
            if ($Rule.Condition.Publisher) {
                $pub = $Rule.Condition.Publisher
                if ($pub -match 'Microsoft') { $tier = 0; $reason = 'Microsoft publisher' }
                elseif ($pub -match 'Google') { $tier = 1; $reason = 'Google publisher' }
                elseif ($pub -match 'Python Software Foundation') { $tier = 2; $reason = 'Python publisher' }
                else { $tier = 1; $reason = "Third-party publisher: $pub" }
            }
            elseif ($Rule.Condition.Path) {
                $p = $Rule.Condition.Path
                if ($p -match 'userprofile|localappdata|miniconda|users') { $tier = 2; $reason = 'User-local dev path' }
                elseif ($p -match 'c:\\windows|programfiles') { $tier = 0; $reason = 'System path' }
                else { $tier = 3; $reason = 'Path-based allow (user-local fallback)' }
            }
        }
        else {
            if ($Rule.Kind -eq 'Publisher') {
                $pub = $Rule.PublisherName
                if ($pub -and $pub -match 'Microsoft') { $tier = 0; $reason = 'Microsoft publisher' }
                elseif ($pub -and $pub -match 'Google') { $tier = 1; $reason = 'Google publisher' }
                elseif ($pub -and $pub -match 'Python Software Foundation') { $tier = 2; $reason = 'Python publisher' }
                else { $tier = 1; $reason = "Third-party publisher: $pub" }
            }
            elseif ($Rule.Kind -eq 'Path') {
                $p = $Rule.Path
                if ($p -match '%USERPROFILE%|%LOCALAPPDATA%|miniconda|Users') { $tier = 2; $reason = 'User-local dev path' }
                elseif ($p -match '%ProgramFiles%|%SystemRoot%') { $tier = 0; $reason = 'System path' }
                else { $tier = 3; $reason = 'Path-based allow (user-local fallback)' }
            }
            else {
                $tier = 4; $reason = "Rule kind: $($Rule.Kind)"
            }
        }
    } else {
        # No matched rule — infer from workload item
        $path = $WorkloadItem.Path
        if ($path -match '%USERPROFILE%|%LOCALAPPDATA%|C:\\Users') { $tier = 3; $reason = 'User-local executable (no rule)' }
        elseif ($WorkloadItem.PublisherName -and $WorkloadItem.PublisherName -match 'Microsoft') { $tier = 0; $reason = 'Publisher indicates Microsoft' }
        elseif ($WorkloadItem.PublisherName -and $WorkloadItem.PublisherName -match 'Google') { $tier = 1; $reason = 'Publisher indicates Google' }
        else { $tier = 3; $reason = 'Unsigned/unknown workload' }
    }

    return @{ Tier = $tier; Reason = $reason }
}

function Synthesize-DeveloperDomainRules {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)] [array]$WorkloadItems
    )
    # Heuristic synthesis: collect common dev binaries and produce narrow path rules
    $suggestions = @{}
    foreach ($item in $WorkloadItems) {
        $bin = $item.BinaryName.ToLower()
        if ($bin -match 'python.exe') {
            $suggestions['python'] = @('%LOCALAPPDATA%\Programs\Python\Python*\python.exe','%USERPROFILE%\miniconda3\python.exe','C:\\Python*\\python.exe')
        }
        elseif ($bin -match 'conda.exe|pip.exe') {
            $suggestions['conda'] = @('%USERPROFILE%\miniconda3\*','%LOCALAPPDATA%\Programs\Python\Python*\Scripts\*')
        }
        elseif ($bin -match 'node.exe') {
            $suggestions['node'] = @('%ProgramFiles%\nodejs\node.exe','%USERPROFILE%\\AppData\\Roaming\\nvm\\*\\node.exe')
        }
        elseif ($bin -match 'gk.exe|gitkraken') {
            $suggestions['gitkraken'] = @('%LOCALAPPDATA%\GitKrakenCLI\GK.exe')
        }
        elseif ($bin -match 'ollama.exe') {
            $suggestions['ollama'] = @('%LOCALAPPDATA%\Programs\Ollama\ollama.exe')
        }
    }

    $rules = @()
    foreach ($key in $suggestions.Keys) {
        foreach ($p in $suggestions[$key]) {
            $cond = [AppLockerCondition]::new(@{ Path = $p })
            try {
                $cond.Path = Normalize-ConditionPath $cond.Path
            } catch [System.ArgumentException] {
                Write-Warning "Synthesize-DeveloperDomainRules: skipping synthesized path due to validation error for key '$key' path '$p' - $($_.Exception.Message)"
                continue
            }
            $condHash = Get-ConditionHash -cond $cond
            if ($condHash) {
                $hex = $condHash.Substring(0,32)
                $id = '{0}-{1}-{2}-{3}-{4}' -f $hex.Substring(0,8),$hex.Substring(8,4),$hex.Substring(12,4),$hex.Substring(16,4),$hex.Substring(20,12)
            } else {
                $id = [guid]::NewGuid().ToString()
            }
            $rule = [AppLockerRuleIR]::new($id, [RuleType]::Exe, [RuleAction]::Allow, [Tier]::Tier2, $cond, 'All', "DeveloperDomain - $key", [RuleSource]::Synth)
            $rules += $rule
        }
    }
    return ,$rules
}

function Emit-PolicyIRToXml {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]$PolicyIR,
        [Parameter(Mandatory=$true)][string]$FilePath,
        [switch]$ForEnforce
    )
    $xmlDoc = New-Object System.Xml.XmlDocument
    $policy = $xmlDoc.CreateElement('AppLockerPolicy')
    $policy.SetAttribute('Version','1')
    $xmlDoc.AppendChild($policy) | Out-Null

    if ($PolicyIR -and $PolicyIR.PSObject.Properties['Rules']) { $rules = $PolicyIR.Rules } else { $rules = $PolicyIR }
    if (-not $rules) { $xmlDoc.Save($FilePath); return }

    $ordered = $rules | Sort-Object -Property @{Expression={"$($_.Tier)-$($_.RuleType)-$($_.Action)-$($_.RuleId)"}}
    $groups = $ordered | Group-Object -Property @{Expression={ if ($_.PSObject.Properties['RuleType']) { $_.RuleType.ToString() } else { $_.Type } }}

    foreach ($g in $groups) {
        $rc = $xmlDoc.CreateElement('RuleCollection')
        $rc.SetAttribute('Type',$g.Name)
        $mode = 'AuditOnly'
        if ($ForEnforce) { $mode = 'Enforce' }
        $rc.SetAttribute('EnforcementMode', $mode)
        $policy.AppendChild($rc) | Out-Null

        foreach ($r in $g.Group) {
            $cond = if ($r.PSObject.Properties['Condition']) { $r.Condition } else { $null }
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

function Compare-AppLockerIR {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]$Left,
        [Parameter(Mandatory=$true)]$Right
    )
    function NormalizeRules($ir) {
        if ($ir -is [AppLockerPolicyIR]) { $rules = $ir.Rules }
        elseif ($ir -and $ir.PSObject.Properties['Rules']) { $rules = $ir.Rules }
        elseif ($ir -is [System.Array]) { $rules = $ir }
        else { $rules = @() }

        $rules | ForEach-Object {
            [PSCustomObject]@{
                RuleId = ([string]($_.RuleId -or $_.Id -or ''))
                Name   = ([string]($_.Name -or $_.Description -or ''))
                Action = ([string]($_.Action))
                Type   = ([string]($_.RuleType -or $_.Type -or ''))
                Tier   = ([string]($_.Tier -or ''))
            }
        } | Sort-Object -Property RuleId
    }

    $l = @($(NormalizeRules $Left))
    $r = @($(NormalizeRules $Right))

    $added   = Compare-Object -ReferenceObject $l -DifferenceObject $r -Property RuleId -PassThru | Where-Object { $_.SideIndicator -eq '=>' }
    $removed = Compare-Object -ReferenceObject $l -DifferenceObject $r -Property RuleId -PassThru | Where-Object { $_.SideIndicator -eq '<=' }

    $changed = @()
    foreach ($item in $l) {
        $match = $r | Where-Object { $_.RuleId -eq $item.RuleId }
        if ($match) {
            $m = $match | Select-Object -First 1
            if ($item.Name -ne $m.Name -or $item.Action -ne $m.Action -or $item.Type -ne $m.Type -or $item.Tier -ne $m.Tier) {
                $changed += [PSCustomObject]@{
                    RuleId = $item.RuleId
                    Left   = $item
                    Right  = $m
                }
            }
        }
    }

    $addedCount = @($added).Count
    $removedCount = @($removed).Count
    $changedCount = @($changed).Count

    $summary = "{0} added, {1} removed, {2} changed" -f $addedCount, $removedCount, $changedCount
    if ($addedCount -eq 0 -and $removedCount -eq 0 -and $changedCount -eq 0) { $summary += ' (equal)' }

    return [PSCustomObject]@{
        IsEqual = (($addedCount -eq 0) -and ($removedCount -eq 0) -and ($changedCount -eq 0))
        Added   = $added
        Removed = $removed
        Changed = $changed
        Summary = $summary
    }
}

function Assert-AppLockerIR {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]$Left,
        [Parameter(Mandatory=$true)]$Right
    )

    $result = Compare-AppLockerIR -Left $Left -Right $Right
    if (-not $result.IsEqual) {
        $msg = @(
            'AppLocker IR mismatch',
            $result.Summary,
            '',
            ($result | ConvertTo-Json -Depth 10)
        ) -join "`n"

        throw $msg
    }

    return $true
}

Export-ModuleMember -Function Parse-AppLockerPolicyXml,Simulate-Execution,Diff-Policies,Evaluate-Workload,Synthesize-DeveloperDomainRules,Emit-PolicyIRToXml,Compare-AppLockerIR,Assert-AppLockerIR,Assert-PolicyIRHealth
