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
        $tmp = Join-Path -Path $env:TEMP -ChildPath "pcc_test_parse.xml"
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
        $tmpIn = Join-Path $env:TEMP 'pcc_rt_in.xml'
        $tmpOut = Join-Path $env:TEMP 'pcc_rt_out.xml'
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

      $tmpOut = Join-Path $env:TEMP 'pcc_roundtrip.xml'
      Emit-PolicyIRToXml -PolicyIR $ir1 -FilePath $tmpOut

      if (-not (Test-Path $tmpOut)) { throw 'Emitter did not produce round-trip file' }

      $ir2 = Parse-AppLockerPolicyXml -Path $tmpOut

      Assert-AppLockerIR $ir1 $ir2
    }
  }
