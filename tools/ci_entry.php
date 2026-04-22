<?php
// CI entrypoint: declarative stage-runner
define('CLI_SCRIPT', 1);
require_once(__DIR__ . '/../config.php');

// CLI parsing: --mode=full|bootstrap-only|validate-only|cron-only|smoke-only
$mode = 'full';
$profile = 'ci';
foreach ($argv as $a) {
    if (strpos($a, '--mode=') === 0) { $mode = substr($a, 7); }
    if (strpos($a, '--profile=') === 0) { $profile = substr($a, 10); }
}

function now_ts() { return date('Ymd_His'); }
$runid = now_ts();
$runsdir = __DIR__ . '/runs/' . $runid;
if (!file_exists($runsdir)) { mkdir($runsdir, 0777, true); }

// Ensure latest pointer directory exists (tools/runs/latest)
$latestdir = __DIR__ . '/runs/latest';
if (!file_exists($latestdir)) { @mkdir($latestdir, 0777, true); }

$executorlib = __DIR__ . '/executor_lib.php';
if (is_readable($executorlib)) {
    require_once($executorlib);
}
if (!function_exists('php_cmd')) {
    function php_cmd($script = null) {
        $php = defined('PHP_BINARY') && PHP_BINARY ? PHP_BINARY : 'php';
        if ($script === null || $script === '') {
            return $php;
        }
        return $php . ' ' . escapeshellarg($script);
    }
}

// Shared helpers and stage registry
// Minimal executor: the compiler is authoritative for runtime stage defs.
// Keep only the minimal defaults used by validation.
$stage_defaults = ['retries' => 1, 'timeout_sec' => 60, 'enabled' => true];

// Attempt to load a declarative pipeline (optional)
// `pipeline.json` is now compiled by the dedicated compiler. Runtime executor
// no longer loads or resolves the DAG directly; compilation is delegated to
// `tools/pipeline_compiler.php`. This keeps a single authoritative execution
// path: compile -> execute.

// Legacy DAG resolution and in-file compilation were removed. Compilation and
// observability are handled by `tools/pipeline_compiler.php` at build time.

$summary = [ 'run_id' => $runid, 'status' => 'pass', 'stages' => new stdClass(), 'failed_stage' => null, 'total_duration_ms' => 0 ];

// Simple stage validation helper
function validate_stage_def($name, $stage, $defaults) {
    if (!is_array($stage)) { throw new Exception("Stage definition for $name must be an array"); }
    if (!isset($stage['cmd']) || !is_string($stage['cmd'])) { throw new Exception("Stage $name missing string 'cmd'"); }
    if (!isset($stage['timeout_sec'])) { $stage['timeout_sec'] = $defaults['timeout_sec']; }
    if (!is_int($stage['timeout_sec']) && !ctype_digit((string)$stage['timeout_sec'])) { throw new Exception("Stage $name 'timeout_sec' must be integer"); }
    if (!isset($stage['retries'])) { $stage['retries'] = $defaults['retries']; }
    if (!is_int($stage['retries']) && !ctype_digit((string)$stage['retries'])) { throw new Exception("Stage $name 'retries' must be integer >= 0"); }
    // Treat 'required' as read-only contract data; if missing, derive from defaults
    if (!array_key_exists('required', $stage)) {
        $stage['required'] = !empty($defaults['required']) ? (bool)$defaults['required'] : false;
    } elseif (!is_bool($stage['required'])) {
        $stage['required'] = (bool)$stage['required'];
    }
    return $stage;
}

// NOTE: Artifact validation is performed by tools/validate_artifacts.php stage.

function run_stage($name, $stage, $runsdir, $latestdir) {
    $retries = isset($stage['retries']) ? (int)$stage['retries'] : 0;
    $timeout = isset($stage['timeout_sec']) ? (int)$stage['timeout_sec'] : null;
    $attempts_info = [];
    $finalStatus = 'fail';
    $finalExit = 1;
    $attempts = $retries + 1;
    $tick_usec = 100000; // 100ms poll tick (single source of truth for polling)

    for ($attempt = 1; $attempt <= $attempts; $attempt++) {
        $start = microtime(true);
        $descriptorspec = array(
            1 => array('pipe', 'w'),
            2 => array('pipe', 'w')
        );
        $proc = proc_open($stage['cmd'], $descriptorspec, $pipes);
        if (!is_resource($proc)) {
            $duration = (int)((microtime(true) - $start) * 1000);
            $attemptRecord = [ 'attempt' => $attempt, 'exit_code' => 1, 'duration_ms' => $duration, 'status' => 'fail', 'note' => 'failed to start' ];
            $attempts_info[] = $attemptRecord;
            // write per-attempt log
            $attemptLog = $runsdir . "/{$name}.attempt{$attempt}.log";
            $combined = "Attempt: {$attempt}\n" . json_encode($attemptRecord, JSON_PRETTY_PRINT) . "\n";
            file_put_contents($attemptLog, $combined, LOCK_EX);
            @copy($attemptLog, $stage['log']);
            $finalStatus = 'fail'; $finalExit = 1;
            break;
        }

        // set non-blocking
        stream_set_blocking($pipes[1], false);
        stream_set_blocking($pipes[2], false);
        $stdout = ''; $stderr = '';
        $killed = false;

        // prepare for select-based reading (poll-only, wall-clock enforces timeout)
        $read = [$pipes[1], $pipes[2]];
        $write = null; $except = null;

        while (true) {
            $status = proc_get_status($proc);
            $now = microtime(true);
            $elapsed = $now - $start;

            // enforce timeout by wall-clock only
            if ($timeout !== null && $elapsed >= $timeout) {
                // try graceful terminate then force kill
                @proc_terminate($proc);
                $pinfo = proc_get_status($proc);
                $pid = $pinfo['pid'] ?? null;
                if ($pid) {
                    if (stripos(PHP_OS, 'WIN') === 0) {
                        @exec("taskkill /F /T /PID $pid 2>&1", $out, $rc);
                    } else {
                        if (function_exists('posix_kill')) { @posix_kill($pid, 9); }
                    }
                }
                $killed = true;
                // drain output after kill
                $stdout .= stream_get_contents($pipes[1]);
                $stderr .= stream_get_contents($pipes[2]);
                break;
            }

            // poll for available data with a small tick
            $r = $read; $w = $write; $e = $except;
            $num = @stream_select($r, $w, $e, 0, $tick_usec);
            if ($num === false) {
                usleep(100000);
            } elseif ($num > 0) {
                foreach ($r as $readable) {
                    $data = stream_get_contents($readable);
                    if ($readable === $pipes[1]) { $stdout .= $data; }
                    if ($readable === $pipes[2]) { $stderr .= $data; }
                }
            }

            // check if process exited
            $status = proc_get_status($proc);
            if (!$status['running']) {
                // drain remaining output
                $stdout .= stream_get_contents($pipes[1]);
                $stderr .= stream_get_contents($pipes[2]);
                break;
            }
        }

        @fclose($pipes[1]); @fclose($pipes[2]);
        // when we killed the process due to timeout, return deterministic exit and duration
        if ($killed) {
            $exit = 124;
            $duration = ($timeout !== null) ? (int)($timeout * 1000) : (int)((microtime(true) - $start) * 1000);
            $attemptRecord = [ 'attempt' => $attempt, 'exit_code' => $exit, 'duration_ms' => $duration, 'status' => 'timeout', 'stdout' => $stdout, 'stderr' => $stderr ];
            $attempts_info[] = $attemptRecord;
            // per-attempt log
            $attemptLog = $runsdir . "/{$name}.attempt{$attempt}.log";
            $combined = "Attempt: {$attempt}\n" . json_encode($attemptRecord, JSON_PRETTY_PRINT) . "\nSTDOUT:\n" . $stdout . "\nSTDERR:\n" . $stderr . "\n";
            file_put_contents($attemptLog, $combined, LOCK_EX);
            @copy($attemptLog, $stage['log']);
            $finalStatus = 'timeout'; $finalExit = $exit;
            if ($attempt < $attempts) { continue; }
            break;
        }

        $exit = proc_close($proc);
        $duration = (int)((microtime(true) - $start) * 1000);


        if ($exit === 0) {
            $attemptRecord = [ 'attempt' => $attempt, 'exit_code' => $exit, 'duration_ms' => $duration, 'status' => 'pass', 'stdout' => $stdout, 'stderr' => $stderr ];
            $attempts_info[] = $attemptRecord;
            $attemptLog = $runsdir . "/{$name}.attempt{$attempt}.log";
            $combined = "Attempt: {$attempt}\n" . json_encode($attemptRecord, JSON_PRETTY_PRINT) . "\nSTDOUT:\n" . $stdout . "\nSTDERR:\n" . $stderr . "\n";
            file_put_contents($attemptLog, $combined, LOCK_EX);
            @copy($attemptLog, $stage['log']);
            $finalStatus = 'pass'; $finalExit = 0;
            break;
        }

        $attemptRecord = [ 'attempt' => $attempt, 'exit_code' => $exit, 'duration_ms' => $duration, 'status' => 'fail', 'stdout' => $stdout, 'stderr' => $stderr ];
        $attempts_info[] = $attemptRecord;
        $attemptLog = $runsdir . "/{$name}.attempt{$attempt}.log";
        $combined = "Attempt: {$attempt}\n" . json_encode($attemptRecord, JSON_PRETTY_PRINT) . "\nSTDOUT:\n" . $stdout . "\nSTDERR:\n" . $stderr . "\n";
        file_put_contents($attemptLog, $combined, LOCK_EX);
        @copy($attemptLog, $stage['log']);
        $finalStatus = 'fail'; $finalExit = $exit;
        if ($attempt < $attempts) { continue; }
    }
    // Normalize final exit code by final status
    function normalize_exit_code($status, $exit) {
        if ($status === 'pass') { return 0; }
        if ($status === 'timeout') { return 124; }
        return ($exit && is_int($exit)) ? $exit : 1;
    }

    $finalExit = normalize_exit_code($finalStatus, $finalExit);

    $stageobj = [
        'stage' => $name,
        'status' => $finalStatus,
        'final_status' => $finalStatus,
        'exit_code' => $finalExit,
        'attempts' => count($attempts_info),
        'timeout_sec' => $timeout,
        'attempts_info' => $attempts_info,
        'duration_ms' => array_reduce($attempts_info, function($carry, $it){ return $carry + ($it['duration_ms'] ?? 0); }, 0),
        'log_file' => basename($stage['log'])
    ];

    file_put_contents($runsdir . "/stage_{$name}.json", json_encode($stageobj, JSON_PRETTY_PRINT));
    @copy($runsdir . "/stage_{$name}.json", $latestdir . "/stage_{$name}.json");
    // also save full log (combine latest attempt stdout/stderr) for convenience
    $last = end($attempts_info);
    if ($last) {
        $combined = "Attempt summary for {$name}:\n" . json_encode($last, JSON_PRETTY_PRINT) . "\n";
        file_put_contents($stage['log'], $combined, FILE_APPEND | LOCK_EX);
    }

    return $stageobj;
}

try {
    // Delegate contract-check and compile-only to compiler
    if ($mode === 'contract-check' || $mode === 'compile-only') {
        $cmd = php_cmd('tools/pipeline_compiler.php') . ' --mode=' . escapeshellarg($mode);
        passthru($cmd, $rc);
        exit($rc);
    }

    // Default behavior: compile then execute. `--mode=execute-only` skips compilation.
    if ($mode !== 'execute-only') {
        $cmd = php_cmd('tools/pipeline_compiler.php') . ' --mode=compile-only';
        $compilerOutPath = $runsdir . '/compiler.out';
        $fullCmd = $cmd . ' > ' . escapeshellarg($compilerOutPath) . ' 2>&1';
        passthru($fullCmd, $rc);
        $compilerOut = file_exists($compilerOutPath) ? file_get_contents($compilerOutPath) : '';
        if ($rc !== 0) {
            fwrite(STDERR, "pipeline compiler failed with exit code $rc\n");
            fwrite(STDERR, $compilerOut);
            exit($rc);
        }
        // Match compile_wrapper behavior: fail on explicit PHP diagnostics only.
        if (preg_match('/\bWarning\b/i', $compilerOut) || preg_match('/\bDeprecated\b/i', $compilerOut) || preg_match('/\bNotice\b/i', $compilerOut)) {
            fwrite(STDERR, "Compiler emitted warnings/notices/deprecations; failing CI\n");
            fwrite(STDERR, $compilerOut);
            exit(3);
        }
    }

    // Load the compiled artifact produced by the compiler and validate strictly
    $compiledPath = __DIR__ . '/runs/latest/pipeline.compiled.json';
    if (!file_exists($compiledPath)) {
        fwrite(STDERR, "Compiled pipeline not found at $compiledPath\n");
        exit(2);
    }
    $rawc = file_get_contents($compiledPath);
    $dec = json_decode($rawc, true);
    if (json_last_error() !== JSON_ERROR_NONE || !is_array($dec)) {
        fwrite(STDERR, "Invalid JSON in compiled pipeline: $compiledPath\n");
        exit(2);
    }
    if (!isset($dec['resolved_order']) || !is_array($dec['resolved_order'])) {
        fwrite(STDERR, "Invalid compiled pipeline: missing resolved_order\n");
        exit(2);
    }
    if (!isset($dec['nodes']) || !is_array($dec['nodes'])) {
        fwrite(STDERR, "Invalid compiled pipeline: missing nodes map\n");
        exit(2);
    }

    // validate nodes and construct runtime stage defs (log file paths under new run dir)
    $newStages = [];
    foreach ($dec['resolved_order'] as $n) {
        if (!isset($dec['nodes'][$n]) || !is_array($dec['nodes'][$n])) {
            fwrite(STDERR, "Compiled pipeline missing node definition for '$n'\n"); exit(2);
        }
        $nd = $dec['nodes'][$n];
        if (!isset($nd['cmd']) || !is_string($nd['cmd'])) { fwrite(STDERR, "Compiled node '$n' missing 'cmd'\n"); exit(2); }
        if (!array_key_exists('timeout_sec', $nd)) { fwrite(STDERR, "Compiled node '$n' missing 'timeout_sec'\n"); exit(2); }
        if (!array_key_exists('retries', $nd)) { fwrite(STDERR, "Compiled node '$n' missing 'retries'\n"); exit(2); }
        $logname = isset($nd['log']) && $nd['log'] ? basename($nd['log']) : ($n . '.log');
        $timeoutSec = $nd['timeout_sec'];
        if ($timeoutSec !== null && (is_int($timeoutSec) || ctype_digit((string)$timeoutSec))) {
            $timeoutSec = (int)$timeoutSec;
        }
        $newStages[$n] = [
            'cmd' => $nd['cmd'],
            'timeout_sec' => $timeoutSec,
            'retries' => (int)$nd['retries'],
            'required' => !empty($nd['required']),
            'log' => $runsdir . '/' . $logname,
        ];
    }
    $stages = $newStages;
    $run_stages = $dec['resolved_order'];
    $total_start = microtime(true);
    $anyFailure = false;

    foreach ($run_stages as $name) {
        if (!isset($stages[$name])) { fwrite(STDERR, "Unknown stage: $name\n"); exit(2); }
        echo "Running stage: $name\n";
        // validate stage definition to catch misconfigurations early
        try {
            $stagedef = validate_stage_def($name, $stages[$name], $stage_defaults);
        } catch (Exception $ve) {
            fwrite(STDERR, "Invalid stage definition for $name: " . $ve->getMessage() . "\n");
            exit(2);
        }
        $result = run_stage($name, $stagedef, $runsdir, $latestdir);
        $summary['stages']->{$name} = $result['status'];
        $summary['total_duration_ms'] += $result['duration_ms'];
        if ($result['status'] === 'fail') {
            $anyFailure = true;
            $summary['status'] = 'fail';
            $summary['failed_stage'] = $name;
            // write partial summary and copy to latest
            file_put_contents($runsdir . '/run_summary.json', json_encode($summary, JSON_PRETTY_PRINT));
            @copy($runsdir . '/run_summary.json', $latestdir . '/run_summary.json');
            echo "Stage $name failed (required=" . ($stages[$name]['required'] ? 'true' : 'false') . ")\n";
            if (!empty($stages[$name]['required'])) {
                exit(1);
            }
            // otherwise continue
        }
    }

    $total_end = microtime(true);
    $summary['total_duration_ms'] = (int)(($total_end - $total_start) * 1000);
    file_put_contents($runsdir . '/run_summary.json', json_encode($summary, JSON_PRETTY_PRINT));
    @copy($runsdir . '/run_summary.json', $latestdir . '/run_summary.json');
    // write an index.json mapping stages to files for easier consumption
    $index = [ 'run_id' => $runid, 'stages' => new stdClass() ];
    foreach ($summary['stages'] as $sname => $sstatus) {
        $index['stages']->{$sname} = "stage_{$sname}.json";
    }
    file_put_contents($runsdir . '/index.json', json_encode($index, JSON_PRETTY_PRINT));
    @copy($runsdir . '/index.json', $latestdir . '/index.json');
    // artifact validation is performed as a separate pipeline stage `validate_artifacts`
    if ($anyFailure) { echo "Completed with failures. See $runsdir and tools/runs/latest\n"; exit(1); }
    echo "All stages passed. Logs in $runsdir\n";
    exit(0);

} catch (Exception $e) {
    $errSummary = [ 'run_id' => $runid, 'status' => 'fail', 'stages' => $summary['stages'], 'failed_stage' => 'exception', 'total_duration_ms' => $summary['total_duration_ms'], 'error' => $e->getMessage() ];
    file_put_contents($runsdir . '/run_summary.json', json_encode($errSummary, JSON_PRETTY_PRINT));
    @copy($runsdir . '/run_summary.json', $latestdir . '/run_summary.json');
    fwrite(STDERR, "Exception: " . $e->getMessage() . "\n");
    exit(2);
}
