<?php
// Minimal stage registry shared by compiler and executor.
// Implements php_cmd() and get_stage_registry($runsdir = null).
// Keep this file intentionally small and deterministic — no side effects.

if (!function_exists('php_cmd')) {
    function php_cmd(string $script): string {
        // Prefer PHP_BINARY when available; fall back to `php` in PATH.
        $php = defined('PHP_BINARY') && PHP_BINARY ? PHP_BINARY : 'php';
        // If $script is a relative path, make it relative to repository root (tools/..\
        $scriptPath = $script;
        if (!preg_match('#^([A-Za-z]:)?[\\/]|^\\\/#', $script)) {
            $scriptPath = __DIR__ . '/' . $script;
        }
        return escapeshellarg($php) . ' ' . escapeshellarg($scriptPath);
    }
}

if (!function_exists('get_stage_registry')) {
    /**
     * Return an associative array of runtime stage definitions.
     * Each entry is an array with keys: cmd, timeout_sec, retries, optional required, optional log.
     * When $runsdir is provided, `log` entries are full paths under that directory and
     * `validate_artifacts` is supplied with an explicit --runsdir flag.
     */
    function get_stage_registry(?string $runsdir = null): array {
        $r = [];

        $r['bootstrap'] = [
            'cmd' => php_cmd('tools/bootstrap.php') . ' --force',
            'timeout_sec' => 120,
            'retries' => 1,
            'required' => true,
            'log' => $runsdir ? $runsdir . '/bootstrap.log' : 'bootstrap.log',
        ];

        $r['validate'] = [
            'cmd' => php_cmd('tools/validate_course_structure.php'),
            'timeout_sec' => 30,
            'retries' => 0,
            'required' => true,
            'log' => $runsdir ? $runsdir . '/validate.log' : 'validate.log',
        ];

        $r['cron'] = [
            'cmd' => php_cmd('admin/cli/cron.php'),
            'timeout_sec' => 180,
            'retries' => 1,
            'required' => false,
            'log' => $runsdir ? $runsdir . '/cron.log' : 'cron.log',
        ];

        $r['smoke'] = [
            'cmd' => php_cmd('tools/smoke_run.php'),
            'timeout_sec' => 60,
            'retries' => 0,
            'required' => true,
            'log' => $runsdir ? $runsdir . '/smoke_run.log' : 'smoke_run.log',
        ];

        // validate_artifacts needs the runsdir to inspect emitted files; include flag only when runsdir provided
        $validateCmd = php_cmd('tools/validate_artifacts.php');
        if ($runsdir) {
            $validateCmd .= ' --runsdir=' . escapeshellarg($runsdir);
        }
        $r['validate_artifacts'] = [
            'cmd' => $validateCmd,
            'timeout_sec' => 15,
            'retries' => 0,
            'required' => true,
            'log' => $runsdir ? $runsdir . '/validate_artifacts.log' : 'validate_artifacts.log',
        ];

        return $r;
    }
}
