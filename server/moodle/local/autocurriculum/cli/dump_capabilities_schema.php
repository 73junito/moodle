<?php
// CLI: dump mdl_capabilities table columns and a sample capability row.
define('CLI_SCRIPT', true);
require_once(__DIR__ . '/../../../config.php');
global $DB;
if (PHP_SAPI !== 'cli') {
    echo "CLI only\n";
    exit(1);
}

try {
    $cols = $DB->get_records_sql("SHOW COLUMNS FROM {capabilities}");
    echo "Columns in mdl_capabilities:\n";
    foreach ($cols as $c) {
        echo json_encode($c) . "\n";
    }
    $sample = $DB->get_record('capabilities', ['name' => 'moodle/site:config'], '*', IGNORE_MISSING);
    echo "\nSample 'moodle/site:config' row:\n";
    echo json_encode($sample, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES) . "\n";
} catch (Exception $e) {
    fwrite(STDERR, "Error: " . $e->getMessage() . "\n");
    exit(2);
}
return 0;
