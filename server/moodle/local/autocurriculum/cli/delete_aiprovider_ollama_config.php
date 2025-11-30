<?php
// CLI: delete config_plugins rows where plugin = 'aiprovider_ollama'.
// Usage: php delete_aiprovider_ollama_config.php

define('CLI_SCRIPT', true);
require_once(__DIR__ . '/../../../config.php');
global $DB;

if (PHP_SAPI !== 'cli') {
    echo "This script must be run from CLI.\n";
    exit(1);
}

$pluginname = 'aiprovider_ollama';
$recs = $DB->get_records('config_plugins', ['plugin' => $pluginname]);
if (empty($recs)) {
    echo "No config_plugins rows for plugin '$pluginname' found.\n";
    exit(0);
}

foreach ($recs as $r) {
    $deleted = $DB->delete_records('config_plugins', ['id' => $r->id]);
    echo ($deleted ? "Deleted id={$r->id} plugin={$r->plugin} name={$r->name}\n" : "Failed to delete id={$r->id}\n");
}

echo "Done.\n";
return 0;
