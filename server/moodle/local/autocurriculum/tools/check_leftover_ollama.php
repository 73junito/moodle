<?php
// CLI: scan DB and local plugin dirs for leftover 'ollama' references.
// Usage: php check_leftover_ollama.php

define('CLI_SCRIPT', true);
require_once __DIR__ . '/../../../../config.php';
global $DB;

if (PHP_SAPI !== 'cli') {
    echo "This script must be run from CLI.\n";
    exit(1);
}

$result = ['ai_providers' => [], 'config_plugins' => [], 'config' => [], 'local_plugins_dirs' => []];

// ai_providers (older moodle installs may not have 'component' column)
try {
    $rows = $DB->get_records_select('ai_providers', "name LIKE ? OR provider LIKE ?", ['%ollama%', '%ollama%']);
    foreach ($rows as $r) {
        $result['ai_providers'][$r->id] = (array)$r;
    }
} catch (Exception $e) {
    $result['ai_providers_error'] = $e->getMessage();
}

// config_plugins
$rows = $DB->get_records_select('config_plugins', "plugin LIKE ? OR name LIKE ? OR value LIKE ?", ['%ollama%', '%ollama%', '%ollama%']);
foreach ($rows as $r) {
    $result['config_plugins'][$r->id] = (array)$r;
}

// config
$rows = $DB->get_records_select('config', "name LIKE ? OR value LIKE ?", ['%ollama%', '%ollama%']);
foreach ($rows as $r) {
    $result['config'][$r->id] = (array)$r;
}

// local plugins directories
$d = __DIR__ . '/../../..';
foreach (scandir($d) as $entry) {
    if (stripos($entry, 'ollama') !== false) {
        $result['local_plugins_dirs'][] = $entry;
    }
}

echo json_encode($result, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES);
return 0;
<?php
// CLI: Scan Moodle DB for leftover 'ollama' references (read-only).
// Usage: php check_leftover_ollama.php

define('CLI_SCRIPT', true);
require_once __DIR__ . '/../../../../config.php';
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
