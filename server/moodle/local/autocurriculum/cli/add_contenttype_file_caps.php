<?php
// CLI: insert minimal capability rows for contenttype/file if missing.
// Usage: php add_contenttype_file_caps.php

define('CLI_SCRIPT', true);
require_once __DIR__ . '/../../../config.php';
global $DB;

if (PHP_SAPI !== 'cli') {
    echo "CLI only\n";
    exit(1);
}

$caps = [
    [
        'name' => 'contenttype/file:access',
        'captype' => 'read',
        'contextlevel' => 50,
        'component' => 'contenttype_file',
        'riskbitmask' => 0,
    ],
    [
        'name' => 'contenttype/file:upload',
        'captype' => 'write',
        'contextlevel' => 50,
        'component' => 'contenttype_file',
        'riskbitmask' => 16,
    ],
    [
        'name' => 'contenttype/file:manage',
        'captype' => 'write',
        'contextlevel' => 50,
        'component' => 'contenttype_file',
        'riskbitmask' => 0,
    ],
];

$inserted = [];
foreach ($caps as $c) {
    $existing = $DB->get_record('capabilities', ['name' => $c['name']], '*', IGNORE_MISSING);
    if ($existing) {
        echo "Already exists: {$c['name']} (id={$existing->id})\n";
        continue;
    }
    $rec = (object) $c;
    $id = $DB->insert_record('capabilities', $rec);
    if ($id) {
        echo "Inserted capability {$c['name']} as id=$id\n";
        $inserted[] = $id;
    } else {
        echo "Failed to insert {$c['name']}\n";
    }
}

if (!empty($inserted)) {
    echo "Purging caches to refresh capabilities...\n";
    try {
        // Use core function to purge caches via CLI.
        // Call purge_caches.php
        passthru('"' . PHP_BINARY . '" "' . $CFG->dirroot . '/admin/cli/purge_caches.php"');
    } catch (Exception $e) {
        fwrite(STDERR, "Could not purge caches: " . $e->getMessage() . "\n");
    }
}

echo "Done.\n";
return 0;
