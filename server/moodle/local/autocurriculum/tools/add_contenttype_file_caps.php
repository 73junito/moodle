<?php
// CLI: insert minimal contenttype/file capability rows if missing.
// Usage: php add_contenttype_file_caps.php [--confirm]

define('CLI_SCRIPT', true);
require_once(__DIR__ . '/../../../../config.php');
global $DB;

if (PHP_SAPI !== 'cli') {
    echo "This script must be run from CLI.\n";
    exit(1);
}

$confirm = in_array('--confirm', $argv, true);
$need = [
    'contenttype/file:access' => ['riskbitmask' => 0, 'captype' => 'read', 'contextlevel' => CONTEXT_COURSE, 'component' => 'contenttype_file'],
    'contenttype/file:manage' => ['riskbitmask' => 0, 'captype' => 'write', 'contextlevel' => CONTEXT_COURSE, 'component' => 'contenttype_file'],
    'contenttype/file:upload' => ['riskbitmask' => 0, 'captype' => 'write', 'contextlevel' => CONTEXT_COURSE, 'component' => 'contenttype_file'],
];

$existing = $DB->get_records_menu('capabilities', null, '', 'name,id');

$toinsert = [];
foreach ($need as $name => $props) {
    if (!isset($existing[$name])) {
        $toinsert[$name] = $props;
    } else {
        echo "Already exists: $name (id={$existing[$name]})\n";
    }
}

if (empty($toinsert)) {
    echo "No capabilities to insert.\n";
    exit(0);
}

echo "Will insert " . count($toinsert) . " capability(ies).\n";
if (!$confirm) {
    echo "Dry-run: re-run with --confirm to apply.\n";
    exit(0);
}

foreach ($toinsert as $name => $props) {
    $record = (object)[
        'name' => $name,
        'captype' => $props['captype'],
        'contextlevel' => $props['contextlevel'],
        'component' => $props['component'],
        'riskbitmask' => $props['riskbitmask'],
    ];
    $id = $DB->insert_record('capabilities', $record);
    echo "Inserted capability $name as id=$id\n";
}

// purge caches so capabilities re-register
echo "Purging caches to refresh capabilities...\n";
require_once($CFG->dirroot . '/admin/cli/purge_caches.php');

return 0;
