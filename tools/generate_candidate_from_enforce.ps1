$ErrorActionPreference = 'Stop'

$policy = Join-Path $PSScriptRoot 'runs\verify_ir_emit_20260412_000502\enforce.xml'
$outdir = Join-Path $PSScriptRoot 'runs'

Import-Module (Join-Path $PSScriptRoot 'AppLocker.PolicyCompiler.psm1') -Force

Write-Output "Loading policy: $policy"
$ir = Parse-AppLockerPolicyXml -Path $policy

Write-Output 'Creating suggestion: allow moodle bin dir'
$suggestions = @()
$suggestions += [pscustomobject]@{
    RuleType = 'FilePath'
    Path = 'C:\inetpub\wwwroot\moodle\bin\*'
    Action = 'Allow'
    Tier = 2
    Reason = 'Auto-synth for smoke test'
}

Write-Output 'Merging suggestion into IR (shallow JSON copy)'
$irJson = $ir | ConvertTo-Json -Depth 10
$newIR = $irJson | ConvertFrom-Json
if (-not $newIR.Rules) { $newIR | Add-Member -MemberType NoteProperty -Name Rules -Value @() }

foreach ($s in $suggestions) {
    $rule = [ordered]@{
        Id = ([guid]::NewGuid().ToString())
        Type = $s.RuleType
        Path = $s.Path
        Action = $s.Action
        Tier = $s.Tier
        Name = "auto-synth: $($s.Reason)"
    }
    $newIR.Rules += $rule
}

$timestamp = (Get-Date).ToString('yyyyMMdd_HHmmss')
$candidate = Join-Path $outdir "self_heal_candidate_$timestamp.xml"
Write-Output "Emitting candidate: $candidate"
Emit-PolicyIRToXml -PolicyIR $newIR -FilePath $candidate
Write-Output "EMITTED:$candidate"
