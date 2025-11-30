<?php
// Admin tool: list and optionally remove orphaned Ollama AI provider rows.
// Usage: visit this page as site admin. First view lists matching rows.
// To delete them, follow the confirmation link (adds ?confirm=1).

require_once __DIR__ . '/../../../config.php';
require_login();
if (!is_siteadmin()) {
    http_response_code(403);
    echo 'Access denied: site admin only.';
    exit;
}

global $DB;

$like = '%ollama%';
// Detect which columns exist in the table and build a safe WHERE clause.
try {
    $cols = $DB->get_columns('ai_providers');
} catch (Exception $e) {
    echo 'Error inspecting ai_providers table columns: ' . s($e->getMessage());
    echo '</pre>';
    exit;
}

$available = array_keys($cols);
$wheres = array();
$params = array();
if (in_array('name', $available)) {
    $wheres[] = 'name LIKE ?';
    $params[] = $like;
}
if (in_array('component', $available)) {
    $wheres[] = 'component LIKE ?';
    $params[] = $like;
}
// Fallback: if neither column exists, try matching on 'name' only (best effort).
if (empty($wheres)) {
    echo "Warning: neither 'name' nor 'component' columns exist in {ai_providers}. Trying 'name' as fallback.\n\n";
    $wheres[] = 'name LIKE ?';
    $params[] = $like;
}

$sql = 'SELECT * FROM {ai_providers} WHERE ' . implode(' OR ', $wheres);
try {
    $records = $DB->get_records_sql($sql, $params);
} catch (dml_exception $e) {
    echo 'Database error when querying ai_providers: ' . s($e->getMessage());
    echo '</pre>';
    exit;
}

echo '<pre>';
if (empty($records)) {
    echo "No AI provider rows found matching 'ollama'.\n";
    echo '</pre>';
    exit;
}

echo "Found " . count($records) . " provider record(s):\n\n";
foreach ($records as $r) {
    echo "id: {$r->id}\n";
    echo "name: {$r->name}\n";
    echo "component: {$r->component}\n";
    echo "enabled: {$r->enabled}\n";
    echo "config: " . (isset($r->config) ? $r->config : '') . "\n";
    echo "timecreated: " . (isset($r->timecreated) ? date('c', $r->timecreated) : '') . "\n";
    echo "\n";
}

$confirm = optional_param('confirm', 0, PARAM_INT);
if (!$confirm) {
    $self = new moodle_url('/local/autocurriculum/admin/remove_ollama.php');
    $confirmurl = new moodle_url($self, array('confirm' => 1));
    echo "To delete these rows, click: " . html_writer::link($confirmurl, 'Delete all Ollama provider rows (backup will be created)') . "\n";
    echo "(OR append ?confirm=1 to the URL)\n";
    echo '</pre>';
    exit;
}

// Create a backup file in this plugin folder.
$backupdir = __DIR__ . '/../../';
if (!is_dir($backupdir)) {
    $backupdir = __DIR__ . '/';
}
$backupfile = $backupdir . 'backup_ai_providers_ollama_' . date('Ymd_His') . '.json';
file_put_contents($backupfile, json_encode(array_values($records), JSON_PRETTY_PRINT));

$deleted = 0;
foreach ($records as $r) {
    if ($DB->delete_records('ai_providers', array('id' => $r->id))) {
        $deleted++;
    }
}

echo "Backup written to: $backupfile\n";
echo "Deleted records: $deleted\n";
echo "Done. Please purge Moodle caches (Site administration -> Development -> Purge all caches).\n";
echo '</pre>';

// End of file
