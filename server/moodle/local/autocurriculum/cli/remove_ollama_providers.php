<?php
// CLI utility: list and optionally remove ai provider rows for Ollama.
// Usage: php remove_ollama_providers.php --dry-run
//        php remove_ollama_providers.php --confirm

define('CLI_SCRIPT', true);
require __DIR__ . '/../../../config.php';
global $DB;
// CLI params.
$options = getopt('', ['dry-run', 'confirm']);
$dryrun = isset($options['dry-run']);
$confirm = isset($options['confirm']);

// Find matching records (match component OR name containing 'ollama').
$like = '%ollama%';
$cols = $DB->get_columns('ai_providers');
$available = array_keys($cols);
$wheres = [];
$params = [];
if (in_array('component', $available)) {
    $wheres[] = 'component LIKE ?';
    $params[] = $like;
}
if (in_array('name', $available)) {
    $wheres[] = 'name LIKE ?';
    $params[] = $like;
}
if (empty($wheres)) {
    // Fallback: try name only.
    $wheres[] = 'name LIKE ?';
    $params[] = $like;
}

$sql = 'SELECT * FROM {ai_providers} WHERE ' . implode(' OR ', $wheres);
$records = $DB->get_records_sql($sql, $params);

echo "Found " . count($records) . " ai_provider record(s) matching 'ollama'.\n";
if (empty($records)) {
    exit(0);
}

foreach ($records as $r) {
    echo "id={$r->id} name=" . ($r->name ?? '') . " component=" . ($r->component ?? '') . " enabled=" . ($r->enabled ?? '') . "\n";
}

// Backup to plugin folder in this plugin if possible, otherwise current dir.
$backupdir = __DIR__ . '/../';
if (!is_dir($backupdir)) {
    $backupdir = __DIR__ . '/';
}
$backupfile = $backupdir . 'backup_ai_providers_ollama_' . date('Ymd_His') . '.json';
file_put_contents($backupfile, json_encode(array_values($records), JSON_PRETTY_PRINT));
echo "Backup written to: $backupfile\n";

if ($dryrun && !$confirm) {
    echo "Dry-run: no changes made. Re-run with --confirm to delete these rows.\n";
    exit(0);
}

if (!$confirm) {
    echo "No --confirm supplied. Use --confirm to delete the listed rows.\n";
    exit(0);
}

$deleted = 0;
foreach ($records as $r) {
    if ($DB->delete_records('ai_providers', ['id' => $r->id])) {
        $deleted++;
        echo "Deleted id={$r->id}\n";
    } else {
        echo "Failed to delete id={$r->id}\n";
    }
}

echo "Deleted: $deleted\n";
echo "Done. Consider purging caches (admin -> Development -> Purge all caches).\n";
