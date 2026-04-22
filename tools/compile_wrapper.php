<?php
// Wrapper to run the pipeline compiler, capture output, and fail on warnings.
$cmd = PHP_BINARY . ' ' . escapeshellarg(__DIR__ . '/pipeline_compiler.php') . ' --mode=compile-only';
$runsdir = __DIR__ . '/runs';
if (!file_exists($runsdir)) { @mkdir($runsdir, 0777, true); }
$outPath = $runsdir . '/compile_wrapper.out';
$fullCmd = $cmd . ' > ' . escapeshellarg($outPath) . ' 2>&1';
passthru($fullCmd, $rc);
$out = file_exists($outPath) ? file_get_contents($outPath) : '';
echo $out;
if ($rc !== 0) { exit($rc); }
// Treat explicit PHP runtime messages as CI-worthy issues. Use word-boundary regex
// to avoid accidental matches inside normal text.
if (preg_match('/\bWarning\b/i', $out) || preg_match('/\bDeprecated\b/i', $out) || preg_match('/\bNotice\b/i', $out)) {
    fwrite(STDERR, "Compiler emitted warnings/notices/deprecations; failing CI\n");
    exit(3);
}
exit(0);
