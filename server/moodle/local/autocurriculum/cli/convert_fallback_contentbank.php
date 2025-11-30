<?php
// CLI script: convert fallback contentbank entries (contenttype_file) to use the installed plugin
// Usage: php convert_fallback_contentbank.php [--dry-run] [--limit=N]

define('CLI_SCRIPT', true);
require(__DIR__ . '/../../../config.php');
require_once($CFG->dirroot . '/lib/clilib.php');
global $DB, $CFG;

list($options, $unrecognized) = cli_get_params(
    ['help' => false, 'dry-run' => false, 'limit' => 0],
    ['h' => 'help']
);

if ($options['help']) {
    $help = "Convert fallback contentbank entries (contenttype_file) to use plugin's handlers.\n\n" .
        "Options:\n  --dry-run       : Do not modify DB, just report actions.\n" .
        "  --limit=N       : Process at most N items.\n";
    echo $help;
    exit(0);
}

$dryrun = (bool)$options['dry-run'];
$limit = (int)$options['limit'];

$contentbank = new core_contentbank\contentbank();

$sql = "contenttype = :ct";
$params = ['ct' => 'contenttype_file'];
if ($limit > 0) {
    $records = $DB->get_records_select('contentbank_content', $sql, $params, 'id ASC', '*', 0, $limit);
} else {
    $records = $DB->get_records_select('contentbank_content', $sql, $params, 'id ASC');
}

echo "Found " . count($records) . " fallback contentbank entries to convert.\n";

foreach ($records as $rec) {
    $id = (int)$rec->id;
    $name = $rec->name ?? '(no name)';
    echo "Processing content id=$id name=" . s($name) . "... ";

    try {
        $content = $contentbank->get_content_from_id($id);
    } catch (Exception $e) {
        echo "could not load content: " . $e->getMessage() . "\n";
        continue;
    }

    $contenttype = $content->get_content_type_instance();
    $file = $content->get_file();
    if (empty($file)) {
        echo "no attached file, skipping.\n";
        continue;
    }

    if ($dryrun) {
        echo "would call replace_content() with file " . $file->get_filename() . "\n";
        continue;
    }

    try {
        $updated = $contenttype->replace_content($file, $content);
        if ($updated) {
            echo "converted successfully.\n";
        } else {
            echo "replace_content returned false.\n";
        }
    } catch (Exception $e) {
        echo "error during conversion: " . $e->getMessage() . "\n";
    }
}

echo "Conversion run complete.\n";
