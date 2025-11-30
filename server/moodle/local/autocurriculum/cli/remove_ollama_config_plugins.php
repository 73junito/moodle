<?php
// CLI: backup and optionally remove config_plugins entries matching 'ollama'.
// Usage: php remove_ollama_config_plugins.php [--confirm]

define('CLI_SCRIPT', true);
require_once __DIR__ . '/../../../config.php';
global $DB;

if (PHP_SAPI !== 'cli') {
    echo "This script must be run from CLI.\n";
    exit(1);
}

$confirm = in_array('--confirm', $argv, true);
$like = '%ollama%';

$records = $DB->get_records_select('config_plugins', "plugin LIKE ? OR name LIKE ? OR value LIKE ?", [$like, $like, $like]);

if (empty($records)) {
    echo "No config_plugins entries matching 'ollama' found.\n";
    exit(0);
}

$backupdir = __DIR__ . '/..';
$filename = $backupdir . '/backup_config_plugins_ollama_' . date('Ymd_His') . '.json';
file_put_contents($filename, json_encode(array_values($records), JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES));
echo "Backup written to: $filename\n";

echo "Found " . count($records) . " config_plugins record(s) matching 'ollama'.\n";

if (!$confirm) {
    echo "Dry-run: no changes made. Re-run with --confirm to delete these rows.\n";
    exit(0);
}

$deleted = 0;
foreach ($records as $r) {
    if ($DB->delete_records('config_plugins', ['id' => $r->id])) {
        echo "Deleted id={$r->id} plugin={$r->plugin} name={$r->name}\n";
        $deleted++;
    }
}

echo "Deleted: $deleted\n";
return 0;
