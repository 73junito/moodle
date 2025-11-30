<?php
// CLI: check whether specific capability names are present in mdl_capabilities.
// Usage: php check_capabilities.php

define('CLI_SCRIPT', true);
require_once __DIR__ . '/../../../config.php';
global $DB;

if (PHP_SAPI !== 'cli') {
    echo "This script must be run from CLI.\n";
    exit(1);
}

$patterns = [
    'contenttype/file:access',
    'contenttype/file:manage',
    'contenttype/file:upload'
];

$out = [];
foreach ($patterns as $p) {
    $rec = $DB->get_record('capabilities', ['name' => $p], '*', IGNORE_MISSING);
    $out[$p] = $rec ? $rec : null;
}

echo json_encode($out, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES) . "\n";
return 0;
