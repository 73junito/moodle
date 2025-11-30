<?php
// CLI: list capabilities whose name starts with 'contenttype/'.
define('CLI_SCRIPT', true);
require_once __DIR__ . '/../../../config.php';
global $DB;
if (PHP_SAPI !== 'cli') {
    echo "CLI only\n";
    exit(1);
}

$rows = $DB->get_records_sql("SELECT * FROM {capabilities} WHERE name LIKE ?", ['contenttype/%']);
echo json_encode(array_values($rows), JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES) . "\n";
return 0;
