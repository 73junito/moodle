<?php
// Pipeline compiler: validates pipeline.json, resolves DAG, emits compiled artifacts
define('CLI_SCRIPT', 1);

// simple CLI parsing for --mode
$mode = 'compile-only';
foreach ($argv as $a) {
    if (strpos($a, '--mode=') === 0) { $mode = substr($a, 7); }
}

function now_ts() { return date('Ymd_His'); }
$runid = now_ts();
$runsdir = __DIR__ . '/runs/' . $runid;
if (!file_exists($runsdir)) { mkdir($runsdir, 0777, true); }
$latestdir = __DIR__ . '/runs/latest';
if (!file_exists($latestdir)) { @mkdir($latestdir, 0777, true); }

// Use shared registry and helper
require_once(__DIR__ . '/stage_registry.php');
// Compiler should not bind logs to a real runs dir; pass null so log entries are basenames
$stageRegistry = get_stage_registry(null);

function resolve_dag(array $pipelineStages, array $selected) {
    $inDegree = []; $adj = [];
    foreach ($selected as $n) { $inDegree[$n] = 0; $adj[$n] = []; }
    foreach ($selected as $n) {
        if (!isset($pipelineStages[$n])) { throw new Exception("Selected stage '$n' not present in pipeline"); }
        $needs = get_needs($pipelineStages[$n]);
        foreach ($needs as $dep) {
            if (!in_array($dep, $selected, true)) { throw new Exception("Stage '$n' depends on missing stage '$dep'"); }
            $adj[$dep][] = $n;
            $inDegree[$n] = ($inDegree[$n] ?? 0) + 1;
        }
    }
    $queue = []; foreach ($inDegree as $node => $deg) { if ($deg === 0) { $queue[] = $node; } }
    sort($queue, SORT_STRING); $resolved = [];
    while (!empty($queue)) {
        $n = array_shift($queue); $resolved[] = $n;
        if (!empty($adj[$n])) { sort($adj[$n], SORT_STRING); foreach ($adj[$n] as $m) { $inDegree[$m]--; if ($inDegree[$m] === 0) { $queue[] = $m; } } }
        sort($queue, SORT_STRING);
    }
    if (count($resolved) !== count($selected)) { throw new Exception('Cyclic or unresolved dependencies in pipeline DAG'); }
    return $resolved;
}

function validate_pipeline_contract(array $pipeline, array $registry) {
    if (!isset($pipeline['stages']) || !is_array($pipeline['stages'])) { throw new Exception("pipeline must contain a 'stages' object"); }
    $allowed = ['needs','meta'];
    foreach ($pipeline['stages'] as $sname => $sdef) {
        if (!is_array($sdef)) { throw new Exception("Pipeline stage '$sname' must be an object"); }
        foreach ($sdef as $k => $v) { if (!in_array($k, $allowed, true)) { throw new Exception("pipeline.json stage '$sname' contains forbidden key '$k' - pipeline is DAG-only; execution config belongs in stageRegistry"); } }
        if (isset($sdef['needs'])) {
            if (!is_array($sdef['needs'])) { throw new Exception("pipeline.json stage '$sname' 'needs' must be an array"); }
            foreach ($sdef['needs'] as $dep) {
                if (!is_string($dep) || $dep === '') { throw new Exception("pipeline.json stage '$sname' has invalid need entry"); }
                if (!array_key_exists($dep, $registry)) { throw new Exception("pipeline.json stage '$sname' depends on unknown stage '$dep' (not present in stage registry)"); }
            }
        }
    }
    return true;
}

// Safe accessor for `needs` which may be present on arrays (decoded JSON)
// or on objects (compiled nodes). Always returns an array.
function get_needs($stage) {
    if (is_array($stage)) {
        return (isset($stage['needs']) && is_array($stage['needs'])) ? $stage['needs'] : [];
    }
    if (is_object($stage)) {
        return (isset($stage->needs) && is_array($stage->needs)) ? $stage->needs : [];
    }
    return [];
}

function build_pipeline_dot_and_resolved(array $resolved, array $pipelineStages, $runsdir, $latestdir) {
    $nodes = $resolved; sort($nodes, SORT_STRING);
    // Build edges as a set to avoid duplicates and ensure determinism
    $edgesMap = [];
    foreach ($resolved as $node) {
        $needs = get_needs($pipelineStages[$node]);
        foreach ($needs as $dep) {
            $key = $dep . '->' . $node;
            $edgesMap[$key] = [$dep, $node];
        }
    }
    $edges = array_values($edgesMap);
    usort($edges, function($a, $b) { $s = $a[0]."->".$a[1]; $t = $b[0]."->".$b[1]; return strcmp($s, $t); });

    $dot = "digraph pipeline {\n  rankdir=LR;\n\n";
    // nodes (escape labels and names)
    foreach ($nodes as $n) {
        $esc = addslashes($n);
        $label = addslashes($n);
        $dot .= "  \"{$esc}\" [label=\"{$label}\"];\n";
    }
    $dot .= "\n";
    // edges
    foreach ($edges as $e) { $dep = addslashes($e[0]); $to = addslashes($e[1]); $dot .= "  \"{$dep}\" -> \"{$to}\";\n"; }
    $dot .= "}\n";
    $dotpath = $runsdir . '/pipeline.dot'; file_put_contents($dotpath, $dot, LOCK_EX); @copy($dotpath, $latestdir . '/pipeline.dot');
    $resolvedPath = $runsdir . '/pipeline.resolved.json'; file_put_contents($resolvedPath, json_encode(['resolved' => $resolved, 'stages' => $pipelineStages], JSON_PRETTY_PRINT), LOCK_EX); @copy($resolvedPath, $latestdir . '/pipeline.resolved.json');
    return [$dotpath, $resolvedPath];
}

function build_compiled_pipeline(array $resolved, array $pipelineStages, array $runtimeStages, $mode, $runsdir, $latestdir) {
    $compiled = ['run_mode' => $mode, 'resolved_order' => array_values($resolved), 'nodes' => new stdClass()];

    // Build compiled nodes as objects to ensure property access is consistent
    foreach ($resolved as $n) {
        $needs = get_needs($pipelineStages[$n]);
        $runtime = isset($runtimeStages[$n]) ? $runtimeStages[$n] : [];
        $node = (object)[
            'needs' => $needs,
            'timeout_sec' => isset($runtime['timeout_sec']) ? (int)$runtime['timeout_sec'] : null,
            'retries' => isset($runtime['retries']) ? (int)$runtime['retries'] : 0,
            'cmd' => isset($runtime['cmd']) ? $runtime['cmd'] : null,
            'required' => !empty($runtime['required']),
            'log' => isset($runtime['log']) ? basename($runtime['log']) : null,
        ];
        $compiled['nodes']->{$n} = $node;
    }

    // write compiled artifact
    $compiledPath = $runsdir . '/pipeline.compiled.json';
    file_put_contents($compiledPath, json_encode($compiled, JSON_PRETTY_PRINT), LOCK_EX);
    @copy($compiledPath, $latestdir . '/pipeline.compiled.json');

    // Emit a DOT annotated with execution hints (escaped, deterministic, deduped)
    $dot = "digraph pipeline_compiled {\n  rankdir=LR;\n\n";
    foreach ($compiled['resolved_order'] as $n) {
        $nd = $compiled['nodes']->{$n};
        $label = $n . "\n" . "t=" . ($nd->timeout_sec ?? 'null') . "s r=" . ($nd->retries ?? 0);
        $dot .= "  \"" . addslashes($n) . "\" [label=\"" . addslashes($label) . "\"];\n";
    }
    $dot .= "\n";
    // build edges deterministically and avoid duplicates
    $edgesMap = [];
    foreach ($compiled['resolved_order'] as $n) {
        $nds = get_needs($compiled['nodes']->{$n});
        foreach ($nds as $dep) {
            $key = $dep . '->' . $n;
            $edgesMap[$key] = [$dep, $n];
        }
    }
    $edges = array_values($edgesMap);
    usort($edges, function($a,$b){ $s=$a[0]."->".$a[1]; $t=$b[0]."->".$b[1]; return strcmp($s,$t); });
    foreach ($edges as $e) { $dot .= "  \"" . addslashes($e[0]) . "\" -> \"" . addslashes($e[1]) . "\";\n"; }
    $dot .= "}\n";
    $dotPath = $runsdir . '/pipeline.compiled.dot'; file_put_contents($dotPath, $dot, LOCK_EX); @copy($dotPath, $latestdir . '/pipeline.compiled.dot');
    return [$compiledPath, $dotPath];
}

// Load pipeline.json
$pipelinePath = __DIR__ . '/config/pipeline.json';
if (!file_exists($pipelinePath)) { fwrite(STDERR, "pipeline.json not found at $pipelinePath\n"); exit(2); }
$raw = file_get_contents($pipelinePath);
$dec = json_decode($raw, true);
if (json_last_error() !== JSON_ERROR_NONE || !is_array($dec)) { fwrite(STDERR, "Invalid JSON in pipeline file: $pipelinePath\n"); exit(2); }
try { validate_pipeline_contract($dec, $stageRegistry); } catch (Exception $pe) { fwrite(STDERR, "Pipeline contract error: " . $pe->getMessage() . "\n"); exit(2); }

// If contract-check mode, succeed (validation done)
if ($mode === 'contract-check') { echo "pipeline.json contract: OK\n"; exit(0); }

// Determine selection based on modes in pipeline.json (or all)
$pstages = isset($dec['stages']) && is_array($dec['stages']) ? $dec['stages'] : null;
if ($pstages === null) { fwrite(STDERR, "pipeline.json missing 'stages' object\n"); exit(2); }
$selected = array_keys($pstages);
if (isset($dec['modes']) && is_array($dec['modes']) && array_key_exists($mode, $dec['modes'])) {
    $sel = $dec['modes'][$mode];
    if ($sel === '*' || $sel === ['*']) { $selected = array_keys($pstages); }
    elseif (is_array($sel)) { $selected = $sel; }
    else { fwrite(STDERR, "Invalid mode entry for '$mode' in pipeline.json\n"); exit(2); }
}

// Expand closure
$closure = []; $stack = $selected; while (!empty($stack)) { $n = array_pop($stack); if (isset($closure[$n])) { continue; } if (!isset($pstages[$n])) { fwrite(STDERR, "Selected stage '$n' not defined in pipeline stages\n"); exit(2); } $closure[$n]=true; $needs = isset($pstages[$n]['needs']) && is_array($pstages[$n]['needs']) ? $pstages[$n]['needs'] : []; foreach ($needs as $dep) { if (!isset($closure[$dep])) { $stack[] = $dep; } } }
$selected = array_values(array_keys($closure));
try { $resolved = resolve_dag($pstages, $selected); } catch (Exception $ex) { fwrite(STDERR, "Pipeline error: " . $ex->getMessage() . "\n"); exit(2); }
// ensure runtime stages exist in registry
foreach ($resolved as $r) { if (!isset($stageRegistry[$r])) { fwrite(STDERR, "Pipeline stage '$r' not defined in stage registry\n"); exit(2); } }

// Emit observability artifacts and compiled artifact
try { build_pipeline_dot_and_resolved($resolved, $pstages, $runsdir, $latestdir); echo "Wrote pipeline visualization to runs directory\n"; } catch (Exception $de) { fwrite(STDERR, "Failed to write pipeline visualization: " . $de->getMessage() . "\n"); }
try { build_compiled_pipeline($resolved, $pstages, $stageRegistry, $mode, $runsdir, $latestdir); echo "Wrote compiled pipeline to runs directory\n"; } catch (Exception $ce) { fwrite(STDERR, "Failed to write compiled pipeline: " . $ce->getMessage() . "\n"); }

echo "pipeline compiled to $runsdir and runs/latest; exiting (compile-only).\n";
exit(0);
