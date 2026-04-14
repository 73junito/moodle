Import-Module -Name "$PSScriptRoot\..\AppLocker.PolicyCompiler.psm1" -Force

Describe 'AppLocker Baseline Invariants' {
    It 'Baseline rules present, unique, and stable across merge and round-trip' {
        $selfHeal = Join-Path $PSScriptRoot '..\self_heal.ps1'
        $simReport = Join-Path $PSScriptRoot '..\fixtures\positive_sim.json'
        $policyIn = Join-Path $PSScriptRoot 'sample_inspect.xml'

        if (-not (Test-Path $selfHeal)) { throw "self_heal.ps1 not found: $selfHeal" }
        if (-not (Test-Path $simReport)) { throw "Simulation report not found: $simReport" }

        # Run self_heal in DryRun to emit a candidate (which uses Merge-SuggestionsIntoIR internally)
        $args = "-NoProfile","-File",$selfHeal,"-PolicyXml",$policyIn,"-SimulationReport",$simReport,"-DryRun"
        $p = Start-Process -FilePath pwsh -ArgumentList $args -Wait -NoNewWindow -PassThru
        if ($p.ExitCode -ne 0) { throw 'self_heal execution failed' }

        $runsDir = Join-Path $PSScriptRoot '..\runs'
        $candidate = Get-ChildItem -Path $runsDir -Filter 'self_heal_candidate_*.xml' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if (-not $candidate) { throw 'No candidate emitted by self_heal' }

        $ir = Parse-AppLockerPolicyXml -Path $candidate.FullName

        $baseline = @('%SystemRoot%\System32\*','%SystemRoot%\*','%ProgramFiles%\*','%ProgramFiles(x86)%\*')

        # normalize rule path extraction to handle legacy and new IR shapes
        function Get-RulePath($r) {
            if ($r -and $r.PSObject -and $r.PSObject.Properties['Path']) { return $r.Path }
            if ($r -and $r.PSObject -and $r.PSObject.Properties['Condition']) {
                try { return $r.Condition.Path } catch { return $null }
            }
            return $null
        }

            function Normalize-PathForKey {
                param($p)
                if (-not $p) { return $null }
                $s = $p.ToString().Trim()
                $s = $s -replace '\\+','\\'
                $s = $s.Trim('"', "'")
                return $s.ToLowerInvariant()
            }

        # normalize baseline tokens and resolved env-expanded paths
        $baselineNorms = @()
        foreach ($b in $baseline) {
            $baselineNorms += (Normalize-PathForKey $b)
            $baselineNorms += (Normalize-PathForKey ([Environment]::ExpandEnvironmentVariables($b)))
        }
        $baselineNorms = $baselineNorms | Sort-Object -Unique

        # 1) Baseline present — for each token ensure either tokenized or resolved path appears
        foreach ($b in $baseline) {
            $t1 = Normalize-PathForKey $b
            $t2 = Normalize-PathForKey ([Environment]::ExpandEnvironmentVariables($b))
            $found = $ir.Rules | Where-Object {
                $p = Get-RulePath $_
                $pNorm = if ($p) { Normalize-PathForKey $p } else { $null }
                ($pNorm -and ($pNorm -in @($t1,$t2))) -and
                ($_.PSObject.Properties['Action'] -and ($_.Action -ieq 'Allow')) }
            ($found.Count) | Should -BeGreaterThan 0
        }

        # 2) Baseline unique (no duplicate baseline allow entries)
        $baselineRules = $ir.Rules | Where-Object {
            $p = Get-RulePath $_
            ($p -and ($baseline | ForEach-Object { ($_ -replace '\\','\\') } | Where-Object { $_ -ieq ($p -replace '\\','\\') })) -and
            ($_.PSObject.Properties['Action'] -and ($_.Action -ieq 'Allow')) }
        $dups = $baselineRules | Group-Object -Property @{ Expression = { Get-RulePath $_ } } | Where-Object { $_.Count -gt 1 }
        ($dups.Count) | Should -Be 0

        # 3) Baseline stable across emit -> parse round-trip
        $tmpOut = Join-Path $env:TEMP ('pcc_baseline_rt_' + ([guid]::NewGuid().ToString()) + '.xml')
        Emit-PolicyIRToXml -PolicyIR $ir -FilePath $tmpOut
        $ir2 = Parse-AppLockerPolicyXml -Path $tmpOut
        $baselineCount1 = ($ir.Rules | Where-Object { $p = Get-RulePath $_; ($baseline | ForEach-Object { ($_ -replace '\\','\\') } | Where-Object { $_ -ieq ($p -replace '\\','\\') }) -and ($_.Action -eq 'Allow') }).Count
        $baselineCount2 = ($ir2.Rules | Where-Object { $p = Get-RulePath $_; ($baseline | ForEach-Object { ($_ -replace '\\','\\') } | Where-Object { $_ -ieq ($p -replace '\\','\\') }) -and ($_.Action -eq 'Allow') }).Count
        $baselineCount2 | Should -Be $baselineCount1

        # 4) Merging suggestions does not add duplicate baseline rules
        # Prepare a synthetic suggestion and re-run merge by invoking self_heal again with same inputs
        $p2 = Start-Process -FilePath pwsh -ArgumentList $args -Wait -NoNewWindow -PassThru
        if ($p2.ExitCode -ne 0) { throw 'self_heal re-execution failed' }
        $candidate2 = Get-ChildItem -Path $runsDir -Filter 'self_heal_candidate_*.xml' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        $ir3 = Parse-AppLockerPolicyXml -Path $candidate2.FullName
        $baselineCount3 = ($ir3.Rules | Where-Object { $p = Get-RulePath $_; ($baseline | ForEach-Object { ($_ -replace '\\','\\') } | Where-Object { $_ -ieq ($p -replace '\\','\\') }) -and ($_.Action -eq 'Allow') }).Count
        $baselineCount3 | Should -Be $baselineCount1
    }
}
