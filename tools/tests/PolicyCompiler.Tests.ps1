Import-Module -Name "$PSScriptRoot\..\AppLocker.PolicyCompiler.psm1" -Force

Describe 'AppLocker Policy Compiler - Parse/Validate/Emit' {
    It 'Parse -> IR shape test' {
        $xml = @'
<AppLockerPolicy Version="1">
  <RuleCollection Type="Exe" EnforcementMode="AuditOnly">
    <FilePathRule Id="11111111-1111-1111-1111-111111111111" Name="TestExe" Description="Test" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePathCondition Path="%ProgramFiles%\*" />
      </Conditions>
    </FilePathRule>
  </RuleCollection>
</AppLockerPolicy>
'@
        $tmp = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "pcc_test_parse.xml"
        $xml | Out-File -FilePath $tmp -Encoding utf8

        $ir = Parse-AppLockerPolicyXml -Path $tmp
        if (-not $ir) { throw 'Parse-AppLockerPolicyXml returned null' }
        if ($ir -is [System.Array]) { $rules = $ir } elseif ($ir.PSObject.Properties['Rules']) { $rules = $ir.Rules } elseif ($ir.Rules) { $rules = $ir.Rules } else { throw 'Parsed IR missing Rules property or returned array' }
        if ($rules.Count -lt 1) { throw "Expected at least 1 rule, got $($rules.Count)" }
        $badRules = $rules | Where-Object { -not ($_.RuleId -or $_.Id -or $_.Name) }
        if ($badRules -and $badRules.Count -gt 0) {
            Write-Host "Found bad rules (missing Id/RuleId/Name):"
            $badRules | ConvertTo-Json -Depth 6 | Write-Host
        }
        ($badRules.Count) | Should -Be 0
    }

    It 'Validate-PolicyIR fails cleanly on malformed IR' {
        $bad = [PSCustomObject]@{
            Rules = @(
                [PSCustomObject]@{ RuleId = $null; RuleType = $null }
            )
        }
        try {
          Validate-PolicyIR -PolicyIR $bad
          throw 'Expected Validate-PolicyIR to throw or error on malformed IR'
        } catch {
          if (-not $_) { throw 'Expected an exception from Validate-PolicyIR' }
        }
    }

    It 'Emit round-trip test (IR -> XML -> parse)' {
        $xml = @'
<AppLockerPolicy Version="1">
  <RuleCollection Type="Exe" EnforcementMode="AuditOnly">
    <FilePathRule Id="22222222-2222-2222-2222-222222222222" Name="RoundTrip" Description="RT" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePathCondition Path="%ProgramFiles%\MyApp\*" />
      </Conditions>
    </FilePathRule>
  </RuleCollection>
</AppLockerPolicy>
'@
        $tmpIn = Join-Path ([System.IO.Path]::GetTempPath()) 'pcc_rt_in.xml'
        $tmpOut = Join-Path ([System.IO.Path]::GetTempPath()) 'pcc_rt_out.xml'
        $xml | Out-File -FilePath $tmpIn -Encoding utf8

        $ir = Parse-AppLockerPolicyXml -Path $tmpIn
        Emit-PolicyIRToXml -PolicyIR $ir -FilePath $tmpOut

        if (-not (Test-Path $tmpOut)) { throw 'Emitter did not produce output file' }
        $ir2 = Parse-AppLockerPolicyXml -Path $tmpOut
        if ($ir2.Rules.Count -ne $ir.Rules.Count) { throw "Round-trip rule count mismatch: $($ir.Rules.Count) vs $($ir2.Rules.Count)" }
    }

    It 'Diff stability test' {
        $a = [PSCustomObject]@{ Rules = @(@{ RuleId = 'a'; RuleType = 'Exe'; Action='Allow' }) }
        $b = [PSCustomObject]@{ Rules = @(@{ RuleId = 'b'; RuleType = 'Exe'; Action='Deny' }) }
        $diff = Diff-Policies $a $b
        if (-not $diff) { throw 'Diff-Policies returned empty result' }
    }

    It 'Parse -> Emit -> Parse is deterministic' {
      $xmlPath = Join-Path $PSScriptRoot 'sample_inspect.xml'

      $ir1 = Parse-AppLockerPolicyXml -Path $xmlPath

      $tmpOut = Join-Path ([System.IO.Path]::GetTempPath()) 'pcc_roundtrip.xml'
      Emit-PolicyIRToXml -PolicyIR $ir1 -FilePath $tmpOut

      if (-not (Test-Path $tmpOut)) { throw 'Emitter did not produce round-trip file' }

      $ir2 = Parse-AppLockerPolicyXml -Path $tmpOut

      Assert-AppLockerIR $ir1 $ir2
    }


    It 'Emit-PolicyIRToXml sets EnforcementMode=Enforce when ForEnforce is set' {
        $xmlSrc = Join-Path $PSScriptRoot 'sample_inspect.xml'
        $tmpOut = Join-Path ([System.IO.Path]::GetTempPath()) 'pcc_enforce_test.xml'
        $ir = Parse-AppLockerPolicyXml -Path $xmlSrc
        Emit-PolicyIRToXml -PolicyIR $ir -FilePath $tmpOut -ForEnforce
        [xml]$doc = Get-Content $tmpOut -Raw
        $doc.AppLockerPolicy.RuleCollection.EnforcementMode | Should -Be 'Enforce'
    }

    It 'Emit-PolicyIRToXml uses AuditOnly by default (no ForEnforce)' {
        $xmlSrc = Join-Path $PSScriptRoot 'sample_inspect.xml'
        $tmpOut = Join-Path ([System.IO.Path]::GetTempPath()) 'pcc_audit_test.xml'
        $ir = Parse-AppLockerPolicyXml -Path $xmlSrc
        Emit-PolicyIRToXml -PolicyIR $ir -FilePath $tmpOut
        [xml]$doc = Get-Content $tmpOut -Raw
        $doc.AppLockerPolicy.RuleCollection.EnforcementMode | Should -Be 'AuditOnly'
    }
  }

InModuleScope 'AppLocker.PolicyCompiler' {
    Describe 'Normalize-ConditionPath' {
        It 'Expands %OSDRIVE% token to start with C:' {
            $result = Normalize-ConditionPath '%OSDRIVE%\Windows\*'
            $result | Should -Match '^c:'
        }

        It 'Expands %SystemRoot% to include windows and system32 in lowercase' {
            $result = Normalize-ConditionPath '%SystemRoot%\System32\*'
            $result | Should -Match 'windows'
            $result | Should -Match 'system32'
            $result | Should -Be $result.ToLower()
        }

        It 'Normalizes 3 or more consecutive backslashes to at most 2' {
            $result = Normalize-ConditionPath ('C:' + ('\' * 4) + 'Windows')
            ($result -match '\\{3,}') | Should -Be $false
        }

        It 'Returns lowercase result' {
            $result = Normalize-ConditionPath '%ProgramFiles%\MyApp\*'
            $result | Should -Be $result.ToLower()
        }

        It 'Strips surrounding double quotes and produces a path without them' {
            $result = Normalize-ConditionPath '"%ProgramFiles%\MyApp\*"'
            $result | Should -Not -Match '^"'
            $result | Should -Not -Match '"$'
        }

        It 'Throws on unbalanced leading quote' {
            { Normalize-ConditionPath '"C:\Windows\*' } | Should -Throw
        }

        It 'Throws on unbalanced trailing quote' {
            { Normalize-ConditionPath 'C:\Windows\*"' } | Should -Throw
        }

        It 'Throws on path containing newline (control character)' {
            { Normalize-ConditionPath "C:\Windows\`n*" } | Should -Throw
        }

        It 'Returns null or empty for empty-string input' {
            $result = Normalize-ConditionPath ''
            ($null -eq $result -or $result -eq '') | Should -Be $true
        }
    }

    Describe 'Canonicalize-Publisher' {
        It 'Returns null for null input' {
            $result = Canonicalize-Publisher $null
            ($null -eq $result -or $result -eq '') | Should -Be $true
        }

        It 'Returns null for empty string' {
            $result = Canonicalize-Publisher ''
            ($null -eq $result -or $result -eq '') | Should -Be $true
        }

        It 'Collapses multiple consecutive spaces into a single space' {
            $result = Canonicalize-Publisher 'Microsoft   Corporation'
            $result | Should -Be 'Microsoft Corporation'
        }

        It 'Trims leading and trailing whitespace' {
            $result = Canonicalize-Publisher '  Google LLC  '
            $result | Should -Be 'Google LLC'
        }
    }

    Describe 'Get-ConditionHash' {
        It 'Returns the same hash for two identical path conditions' {
            $c1 = [AppLockerCondition]::new(@{ Path = '%ProgramFiles%\*' })
            $c2 = [AppLockerCondition]::new(@{ Path = '%ProgramFiles%\*' })
            (Get-ConditionHash -cond $c1) | Should -Be (Get-ConditionHash -cond $c2)
        }

        It 'Returns different hashes for different paths' {
            $c1 = [AppLockerCondition]::new(@{ Path = '%ProgramFiles%\App1\*' })
            $c2 = [AppLockerCondition]::new(@{ Path = '%ProgramFiles%\App2\*' })
            (Get-ConditionHash -cond $c1) | Should -Not -Be (Get-ConditionHash -cond $c2)
        }

        It 'Returns null or empty for an empty condition (no fields set)' {
            $c = [AppLockerCondition]::new(@{})
            $result = Get-ConditionHash -cond $c
            ($null -eq $result -or $result -eq '') | Should -Be $true
        }

        It 'Returns same hash for identical publisher conditions' {
            $c1 = [AppLockerCondition]::new(@{ Publisher = 'Microsoft Corporation' })
            $c2 = [AppLockerCondition]::new(@{ Publisher = 'Microsoft Corporation' })
            (Get-ConditionHash -cond $c1) | Should -Be (Get-ConditionHash -cond $c2)
        }
    }

    Describe 'Validate-PolicyIR' {
        It 'Returns Success=true for a valid IR with a well-formed rule' {
            $cond = [AppLockerCondition]::new(@{ Path = '%ProgramFiles%\*' })
            $rule = [AppLockerRuleIR]::new('cccccccc-cccc-cccc-cccc-cccccccccccc', [RuleType]::Exe, [RuleAction]::Allow, [Tier]::Tier0, $cond, 'All', 'ValidRule', [RuleSource]::Manual)
            $ir = [AppLockerPolicyIR]::new()
            $ir.Rules += $rule
            $result = Validate-PolicyIR -PolicyIR $ir
            $result.Success | Should -Be $true
            $result.Errors.Count | Should -Be 0
        }

        It 'Returns Success=false and a Description error for a rule with empty description' {
            $cond = [AppLockerCondition]::new(@{ Path = '%ProgramFiles%\*' })
            $rule = [AppLockerRuleIR]::new('dddddddd-dddd-dddd-dddd-dddddddddddd', [RuleType]::Exe, [RuleAction]::Allow, [Tier]::Tier0, $cond, 'All', '', [RuleSource]::Manual)
            $ir = [AppLockerPolicyIR]::new()
            $ir.Rules += $rule
            $result = Validate-PolicyIR -PolicyIR $ir
            $result.Success | Should -Be $false
            (@($result.Errors) | Where-Object { $_ -match 'Description' }).Count | Should -BeGreaterThan 0
        }

        It 'Returns Success=false and a Duplicate error for rules sharing the same condition' {
            $cond1 = [AppLockerCondition]::new(@{ Path = '%ProgramFiles%\DupApp\*' })
            $rule1 = [AppLockerRuleIR]::new('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', [RuleType]::Exe, [RuleAction]::Allow, [Tier]::Tier0, $cond1, 'All', 'DupRule1', [RuleSource]::Manual)
            $cond2 = [AppLockerCondition]::new(@{ Path = '%ProgramFiles%\DupApp\*' })
            $rule2 = [AppLockerRuleIR]::new('ffffffff-ffff-ffff-ffff-ffffffffffff', [RuleType]::Exe, [RuleAction]::Allow, [Tier]::Tier0, $cond2, 'All', 'DupRule2', [RuleSource]::Manual)
            $ir = [AppLockerPolicyIR]::new()
            $ir.Rules += $rule1
            $ir.Rules += $rule2
            $result = Validate-PolicyIR -PolicyIR $ir
            $result.Success | Should -Be $false
            (@($result.Errors) | Where-Object { $_ -match '[Dd]uplicate' }).Count | Should -BeGreaterThan 0
        }
    }

    Describe 'Assert-PolicyIRHealth' {
        It 'Returns IsValid=true for a well-formed IR meeting MinValidRules' {
            $rule = [PSCustomObject]@{ RuleId = '11111111-2222-3333-4444-555555555555'; Description = 'HealthyRule'; Name = 'HealthyRule'; Action = 'Allow'; Type = 'Exe'; Condition = [PSCustomObject]@{ Path = 'c:\program files\*' } }
            $ir = [PSCustomObject]@{ Rules = @($rule) }
            $result = Assert-PolicyIRHealth -PolicyIR $ir -MinValidRules 1
            $result.IsValid | Should -Be $true
        }

        It 'Returns IsValid=false when Rules is empty and MinValidRules=1' {
            $ir = [PSCustomObject]@{ Rules = @() }
            $result = Assert-PolicyIRHealth -PolicyIR $ir -MinValidRules 1
            $result.IsValid | Should -Be $false
        }

        It 'Detects malformed path in rules and records it in MalformedRules' {
            $rule = [PSCustomObject]@{ RuleId = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'; Condition = [PSCustomObject]@{ Path = '"C:\Bad"Path"' }; Action = 'Allow'; RuleType = 'Exe' }
            $ir = [PSCustomObject]@{ Rules = @($rule) }
            $result = Assert-PolicyIRHealth -PolicyIR $ir
            $result.MalformedRules.Count | Should -BeGreaterThan 0
        }

        It 'RequireBaseline: BaselineMissing=false when a rule description contains "baseline"' {
            $rule = [PSCustomObject]@{ RuleId = 'aaaabbbb-cccc-dddd-eeee-ffffaaaabbbb'; Description = 'baseline allow'; Name = 'baseline allow'; Action = 'Allow'; RuleType = 'Exe'; Condition = [PSCustomObject]@{ Path = 'c:\program files\*' } }
            $ir = [PSCustomObject]@{ Rules = @($rule) }
            $result = Assert-PolicyIRHealth -PolicyIR $ir -RequireBaseline
            $result.BaselineMissing | Should -Be $false
        }

        It 'RequireBaseline: BaselineMissing=true when no rule description contains "baseline"' {
            $rule = [PSCustomObject]@{ RuleId = '11112222-3333-4444-5555-666677778888'; Description = 'Some other rule'; Name = 'Some other rule'; Action = 'Allow'; RuleType = 'Exe'; Condition = [PSCustomObject]@{ Path = 'c:\program files\*' } }
            $ir = [PSCustomObject]@{ Rules = @($rule) }
            $result = Assert-PolicyIRHealth -PolicyIR $ir -RequireBaseline
            $result.BaselineMissing | Should -Be $true
        }
    }

    Describe 'Simulate-Execution' {
        It 'Returns Allow when an AppLockerRuleIR path condition matches the file path' {
            $cond = [AppLockerCondition]::new(@{ Path = 'c:\program files\myapp\*' })
            $rule = [AppLockerRuleIR]::new('aabb1122-ccdd-3344-eeff-556677889900', [RuleType]::Exe, [RuleAction]::Allow, [Tier]::Tier0, $cond, 'All', 'MyApp rule', [RuleSource]::Manual)
            $result = Simulate-Execution -PolicyRules @($rule) -Type 'Exe' -FilePath 'C:\Program Files\MyApp\app.exe'
            $result.Result | Should -Be 'Allow'
        }

        It 'Returns Deny when no AppLockerRuleIR rule path matches the file path' {
            $cond = [AppLockerCondition]::new(@{ Path = 'c:\program files\myapp\*' })
            $rule = [AppLockerRuleIR]::new('aabb1122-ccdd-3344-eeff-556677889911', [RuleType]::Exe, [RuleAction]::Allow, [Tier]::Tier0, $cond, 'All', 'MyApp rule', [RuleSource]::Manual)
            $result = Simulate-Execution -PolicyRules @($rule) -Type 'Exe' -FilePath 'C:\Users\user\Downloads\evil.exe'
            $result.Result | Should -Be 'Deny'
        }

        It 'Returns Allow when publisher condition matches the PublisherName argument' {
            $cond = [AppLockerCondition]::new(@{ Publisher = 'Google LLC' })
            $rule = [AppLockerRuleIR]::new('11223344-5566-7788-99aa-bbccddeeff00', [RuleType]::Exe, [RuleAction]::Allow, [Tier]::Tier2, $cond, 'All', 'Google rule', [RuleSource]::Manual)
            $result = Simulate-Execution -PolicyRules @($rule) -Type 'Exe' -FilePath 'C:\Program Files\Google\Chrome\chrome.exe' -PublisherName 'O=Google LLC, L=Mountain View'
            $result.Result | Should -Be 'Allow'
        }

        It 'Returns Allow via duck-typed PSCustomObject path rule' {
            $rule = [PSCustomObject]@{ Type = 'Exe'; Path = 'c:\program files\myapp\*'; PublisherName = ''; Action = 'Allow' }
            $result = Simulate-Execution -PolicyRules @($rule) -Type 'Exe' -FilePath 'C:\Program Files\MyApp\app.exe'
            $result.Result | Should -Be 'Allow'
        }

        It 'Returns Deny via duck-typed PSCustomObject when path does not match' {
            $rule = [PSCustomObject]@{ Type = 'Exe'; Path = 'c:\program files\myapp\*'; PublisherName = ''; Action = 'Allow' }
            $result = Simulate-Execution -PolicyRules @($rule) -Type 'Exe' -FilePath 'C:\BadPath\evil.exe'
            $result.Result | Should -Be 'Deny'
        }
    }

    Describe 'Evaluate-Workload' {
        It 'Returns Allow result for workload items matching a rule' {
            $cond = [AppLockerCondition]::new(@{ Path = 'c:\program files\myapp\*' })
            $rule = [AppLockerRuleIR]::new('aabb1122-ccdd-3344-eeff-556677889933', [RuleType]::Exe, [RuleAction]::Allow, [Tier]::Tier0, $cond, 'All', 'MyApp', [RuleSource]::Manual)
            $workload = @([PSCustomObject]@{ Path = 'C:\Program Files\MyApp\app.exe'; PublisherName = ''; ProductName = ''; BinaryName = 'app.exe' })
            $results = Evaluate-Workload -PolicyRules @($rule) -Workload $workload -Type 'Exe'
            $results.Count | Should -Be 1
            $results[0].Result | Should -Be 'Allow'
        }

        It 'Returns Deny result for workload items with no matching rule' {
            $cond = [AppLockerCondition]::new(@{ Path = 'c:\program files\myapp\*' })
            $rule = [AppLockerRuleIR]::new('aabb1122-ccdd-3344-eeff-556677889944', [RuleType]::Exe, [RuleAction]::Allow, [Tier]::Tier0, $cond, 'All', 'MyApp', [RuleSource]::Manual)
            $workload = @([PSCustomObject]@{ Path = 'C:\Users\user\Downloads\unknown.exe'; PublisherName = ''; ProductName = ''; BinaryName = 'unknown.exe' })
            $results = Evaluate-Workload -PolicyRules @($rule) -Workload $workload -Type 'Exe'
            $results[0].Result | Should -Be 'Deny'
        }

        It 'Result objects include TrustTier and TrustReason fields' {
            $cond = [AppLockerCondition]::new(@{ Path = 'c:\program files\myapp\*' })
            $rule = [AppLockerRuleIR]::new('aabb1122-ccdd-3344-eeff-556677889955', [RuleType]::Exe, [RuleAction]::Allow, [Tier]::Tier0, $cond, 'All', 'MyApp', [RuleSource]::Manual)
            $workload = @([PSCustomObject]@{ Path = 'C:\Program Files\MyApp\app.exe'; PublisherName = ''; ProductName = ''; BinaryName = 'app.exe' })
            $results = Evaluate-Workload -PolicyRules @($rule) -Workload $workload -Type 'Exe'
            $results[0].PSObject.Properties.Name | Should -Contain 'TrustTier'
            $results[0].PSObject.Properties.Name | Should -Contain 'TrustReason'
        }
    }

    Describe 'Synthesize-DeveloperDomainRules' {
        It 'Synthesizes path rules for python.exe workload item' {
            $items = @([PSCustomObject]@{ BinaryName = 'python.exe'; Path = ''; PublisherName = ''; ProductName = '' })
            $rules = Synthesize-DeveloperDomainRules -WorkloadItems $items
            @($rules).Count | Should -BeGreaterThan 0
            (@($rules) | Where-Object { $_.Condition.Path -match 'python' }).Count | Should -BeGreaterThan 0
        }

        It 'Synthesizes path rules for node.exe workload item' {
            $items = @([PSCustomObject]@{ BinaryName = 'node.exe'; Path = ''; PublisherName = ''; ProductName = '' })
            $rules = Synthesize-DeveloperDomainRules -WorkloadItems $items
            @($rules).Count | Should -BeGreaterThan 0
            (@($rules) | Where-Object { $_.Condition.Path -match 'node' }).Count | Should -BeGreaterThan 0
        }

        It 'Returns empty array for an unrecognized binary name' {
            $items = @([PSCustomObject]@{ BinaryName = 'unknowntool.exe'; Path = ''; PublisherName = ''; ProductName = '' })
            $rules = Synthesize-DeveloperDomainRules -WorkloadItems $items
            @($rules).Count | Should -Be 0
        }
    }

    Describe 'Compare-AppLockerIR and Assert-AppLockerIR' {
        It 'Returns IsEqual=true for two identical IRs' {
            $cond = [AppLockerCondition]::new(@{ Path = '%ProgramFiles%\*' })
            $rule = [AppLockerRuleIR]::new('12341234-1234-1234-1234-123412341234', [RuleType]::Exe, [RuleAction]::Allow, [Tier]::Tier0, $cond, 'All', 'SameRule', [RuleSource]::Manual)
            $ir1 = [PSCustomObject]@{ Rules = @($rule) }
            $ir2 = [PSCustomObject]@{ Rules = @($rule) }
            (Compare-AppLockerIR -Left $ir1 -Right $ir2).IsEqual | Should -Be $true
        }

        It 'Detects rules added to Right that were not in Left' {
            $cond1 = [AppLockerCondition]::new(@{ Path = '%ProgramFiles%\App1\*' })
            $rule1 = [AppLockerRuleIR]::new('aaaaaaaa-bbbb-cccc-dddd-111111111111', [RuleType]::Exe, [RuleAction]::Allow, [Tier]::Tier0, $cond1, 'All', 'App1', [RuleSource]::Manual)
            $cond2 = [AppLockerCondition]::new(@{ Path = '%ProgramFiles%\App2\*' })
            $rule2 = [AppLockerRuleIR]::new('aaaaaaaa-bbbb-cccc-dddd-222222222222', [RuleType]::Exe, [RuleAction]::Allow, [Tier]::Tier0, $cond2, 'All', 'App2', [RuleSource]::Manual)
            $result = Compare-AppLockerIR -Left ([PSCustomObject]@{ Rules = @($rule1) }) -Right ([PSCustomObject]@{ Rules = @($rule1, $rule2) })
            $result.IsEqual | Should -Be $false
            @($result.Added).Count | Should -Be 1
        }

        It 'Detects rules removed from Left that are absent from Right' {
            $cond1 = [AppLockerCondition]::new(@{ Path = '%ProgramFiles%\App1\*' })
            $rule1 = [AppLockerRuleIR]::new('aaaaaaaa-bbbb-cccc-dddd-333333333333', [RuleType]::Exe, [RuleAction]::Allow, [Tier]::Tier0, $cond1, 'All', 'App1', [RuleSource]::Manual)
            $cond2 = [AppLockerCondition]::new(@{ Path = '%ProgramFiles%\App2\*' })
            $rule2 = [AppLockerRuleIR]::new('aaaaaaaa-bbbb-cccc-dddd-444444444444', [RuleType]::Exe, [RuleAction]::Allow, [Tier]::Tier0, $cond2, 'All', 'App2', [RuleSource]::Manual)
            $result = Compare-AppLockerIR -Left ([PSCustomObject]@{ Rules = @($rule1, $rule2) }) -Right ([PSCustomObject]@{ Rules = @($rule1) })
            $result.IsEqual | Should -Be $false
            @($result.Removed).Count | Should -Be 1
        }

        It 'Assert-AppLockerIR throws when Left and Right differ in Action' {
            $ir1 = [PSCustomObject]@{ Rules = @([PSCustomObject]@{ Id = 'shared-id'; Action = 'Allow' }) }
            $ir2 = [PSCustomObject]@{ Rules = @([PSCustomObject]@{ Id = 'shared-id'; Action = 'Deny' }) }
            { Assert-AppLockerIR $ir1 $ir2 } | Should -Throw
        }

        It 'Assert-AppLockerIR does not throw when Left and Right are identical' {
            $cond = [AppLockerCondition]::new(@{ Path = '%ProgramFiles%\*' })
            $rule = [AppLockerRuleIR]::new('cccccccc-dddd-eeee-ffff-000011112222', [RuleType]::Exe, [RuleAction]::Allow, [Tier]::Tier0, $cond, 'All', 'SameRule', [RuleSource]::Manual)
            $ir = [PSCustomObject]@{ Rules = @($rule) }
            { Assert-AppLockerIR $ir $ir } | Should -Not -Throw
        }
    }

    Describe 'Diff-Policies - added/removed/unchanged counts' {
        It 'Correctly counts OldCount, NewCount, Added, and Removed when passing arrays directly' {
            $rule1 = [PSCustomObject]@{ RuleId = 'id-old-1'; Id = 'id-old-1' }
            $rule2 = [PSCustomObject]@{ RuleId = 'id-old-2'; Id = 'id-old-2' }
            $rule3 = [PSCustomObject]@{ RuleId = 'id-new-1'; Id = 'id-new-1' }
            $diff = Diff-Policies @($rule1, $rule2) @($rule1, $rule3)
            $diff.OldCount | Should -Be 2
            $diff.NewCount | Should -Be 2
            @($diff.Added).Count | Should -Be 1
            @($diff.Removed).Count | Should -Be 1
        }

        It 'Returns zero Added and Removed counts for identical rule arrays' {
            $rule1 = [PSCustomObject]@{ RuleId = 'same-id'; Id = 'same-id' }
            $diff = Diff-Policies @($rule1) @($rule1)
            @($diff.Added).Count | Should -Be 0
            @($diff.Removed).Count | Should -Be 0
        }
    }
}
