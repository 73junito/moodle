<?php
// CLI: Scan Moodle DB for leftover 'ollama' references (read-only).
// Usage: php check_leftover_ollama.php

define('CLI_SCRIPT', true);
require_once __DIR__ . '/../../../config.php';
global $DB;

// Only allow CLI.
if (PHP_SAPI !== 'cli') {
    echo "This script must be run from CLI.\n";
    exit(1);
}

$like = '%ollama%';
$out = [];

try {
    $out['ai_providers'] = $DB->get_records_select('ai_providers', "name LIKE ? OR provider LIKE ?", [$like, $like]);
    $out['config_plugins'] = $DB->get_records_select('config_plugins', "plugin LIKE ? OR name LIKE ? OR value LIKE ?", [$like, $like, $like]);
    $out['config'] = $DB->get_records_select('config', "name LIKE ? OR value LIKE ?", [$like, $like]);
    $out['local_plugins_dirs'] = [];
    // Scan local plugins directories for any folders named 'ollama' or containing 'ollama'.
    $localdir = $CFG->dirroot . '/local';
    if (is_dir($localdir)) {
        $items = scandir($localdir);
        foreach ($items as $it) {
            if ($it === '.' || $it === '..') {
                continue;
            }
            if (stripos($it, 'ollama') !== false) {
                $out['local_plugins_dirs'][] = $it;
            }
        }
    }
    echo json_encode($out, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES) . "\n";
} catch (Exception $e) {
    fwrite(STDERR, "Error querying DB: " . $e->getMessage() . "\n");
    exit(2);
}

return 0;
