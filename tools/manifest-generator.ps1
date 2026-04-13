param()

$repoRoot = Split-Path -Parent $PSScriptRoot
function RelPath($full) {
    $root = $repoRoot.TrimEnd('\')
    if ($full -like "$root*") {
        $rel = $full.Substring($root.Length)
        if ($rel.StartsWith('\') -or $rel.StartsWith('/')) { $rel = $rel.Substring(1) }
        return ($rel -replace '\\','/')
    }
    return $full
}

$toolsPath = Join-Path $repoRoot 'tools'
$appLockerFiles = @(Get-ChildItem -Path $toolsPath -Include *.xml -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'tier2|synthesized|applocker' })
$appLockerScripts = @(Get-ChildItem -Path $toolsPath -Filter '*AppLocker*' -Recurse -File -ErrorAction SilentlyContinue)
$testsPath = Join-Path $toolsPath 'tests'
$testFiles = @((Get-ChildItem -Path $testsPath -Recurse -File -ErrorAction SilentlyContinue))
$runsPath = Join-Path $toolsPath 'runs'
$runFiles = @((Get-ChildItem -Path $runsPath -Recurse -File -ErrorAction SilentlyContinue))
$simReports = @((Get-ChildItem -Path $toolsPath -Filter 'applocker_sim_report*.txt' -File -ErrorAction SilentlyContinue))

$adminCliFiles = @((Get-ChildItem -Path (Join-Path $repoRoot 'admin\\cli') -Recurse -File -ErrorAction SilentlyContinue))

# Function-level extraction from PowerShell files under tools
$psFiles = @(Get-ChildItem -Path $toolsPath -Recurse -Include *.ps1,*.psm1 -File -ErrorAction SilentlyContinue)
$functions = @()
foreach ($f in $psFiles) {
    try {
        $matches = Select-String -Path $f.FullName -Pattern '^[\s]*function\s+([A-Za-z0-9_-]+)' -AllMatches -ErrorAction SilentlyContinue
        foreach ($m in $matches) {
            $functions += [pscustomobject]@{
                file = RelPath($f.FullName)
                function = $m.Matches.Groups[1].Value
            }
        }
    } catch { }
}

# AppLocker-specific intelligence: parse XML rules to count rules and types
$applockerSummary = [ordered]@{ ruleFileCount = $appLockerFiles.Count; totalRules = 0; ruleTypes = @{} }
foreach ($xmlFile in $appLockerFiles) {
    try {
        $x = [xml](Get-Content -Path $xmlFile.FullName -ErrorAction Stop)
        # find any Rule nodes
        $rules = $x.SelectNodes('//Rule')
        if ($rules) {
            $applockerSummary.totalRules += $rules.Count
            foreach ($r in $rules) {
                $type = $r.GetAttribute('Type')
                if (-not $type) { $type = $r.nodeName }
                if ($applockerSummary.ruleTypes.ContainsKey($type)) { $applockerSummary.ruleTypes[$type] += 1 } else { $applockerSummary.ruleTypes[$type] = 1 }
            }
        }
    } catch { }
}

# CI awareness
$workflowPath = Join-Path $repoRoot '.github\\workflows'
$hasCI = Test-Path (Join-Path $workflowPath 'pester.yml')

# Size metrics
$allFiles = @(Get-ChildItem -Path $repoRoot -Recurse -File -ErrorAction SilentlyContinue)
$totalSize = ($allFiles | Measure-Object -Property Length -Sum).Sum

# Risk signals: search admin CLI and scripts for dangerous patterns
$riskyPatterns = 'Invoke-Expression|iex\s|Start-Process\s|Invoke-Command\s|System\.Diagnostics\.Process|\bexec\(|shell_exec\(|popen\(|passthru\(|system\('
$riskSignals = @()
foreach ($f in $adminCliFiles + $psFiles) {
    try {
        $hits = Select-String -Path $f.FullName -Pattern $riskyPatterns -CaseSensitive:$false -AllMatches -ErrorAction SilentlyContinue
        if ($hits) {
            $riskSignals += [pscustomobject]@{ file = RelPath($f.FullName); matches = ($hits | Select-Object -Unique Line).Line }
        }
    } catch { }
}

# Top-level manifest
$manifest = [ordered]@{
    generatedAt = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    generator = 'tools/manifest-generator.ps1'
    summary = [ordered]@{
        repoPath = $repoRoot
        totalFilesScanned = $allFiles.Count
        totalSizeBytes = $totalSize
        categories = 5
        hasCI = $hasCI
        hasAppLocker = ($appLockerFiles.Count -gt 0 -or $appLockerScripts.Count -gt 0)
        notes = 'Regenerate to refresh counts, functions, and risk signals.'
    }
    categories = @()
    capabilities = [ordered]@{
        functions = $functions
        applocker = $applockerSummary
        ci = [ordered]@{ hasWorkflow = $hasCI; testFileCount = $testFiles.Count }
        riskSignals = $riskSignals
    }
}

function AddCategory($name,$description,$files) {
    $files = @($files) | Sort-Object FullName -Unique
    $rep = @()
    foreach ($f in $files | Select-Object -First 10) { $rep += RelPath($f.FullName) }
    $cat = [ordered]@{
        name = $name
        description = $description
        fileCount = @($files).Count
        totalBytes = ($files | Measure-Object -Property Length -Sum).Sum
        representativeFiles = if ($rep.Count -eq 0) { $null } else { $rep }
    }
    $manifest.categories += $cat
}

AddCategory 'AppLocker Tooling' 'Core AppLocker IR and compiler used to parse, synthesize and emit AppLocker policies.' ($appLockerScripts + $appLockerFiles)
AddCategory 'Tests & CI' 'Pester tests, test fixtures and CI workflow for enforcing the IR contract and determinism.' ($testFiles + (Get-ChildItem -Path $workflowPath -Recurse -File -ErrorAction SilentlyContinue))
AddCategory 'Runs & Reports' 'Saved run outputs, synthesized tier2 rules and AppLocker simulation reports used for triage.' ($runFiles + $simReports)
AddCategory 'Admin Automation' 'Admin CLI scripts and helpers relevant to safe auditing and maintenance (non-AppLocker).' $adminCliFiles
AddCategory 'Docs & Fixtures' 'Documentation, sample fixtures and developer helpers referenced by the toolchain.' (Get-ChildItem -Path $repoRoot -Include README.md,INSTALL.txt -File -ErrorAction SilentlyContinue)

$outPath = Join-Path $toolsPath 'capability-manifest.json'
$json = $manifest | ConvertTo-Json -Depth 10
[System.IO.File]::WriteAllText($outPath,$json)
Write-Output "Wrote manifest to: $outPath"
