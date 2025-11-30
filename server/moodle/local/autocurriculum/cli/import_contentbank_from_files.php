<?php
// CLI script: import generated HTML files into Moodle Content bank.
// Usage: php import_contentbank_from_files.php [--dry-run] [--userid=2]

define('CLI_SCRIPT', true);
require __DIR__ . '/../../../config.php';
require_once $CFG->dirroot . '/lib/clilib.php';
global $DB, $CFG;

list($options, $unrecognized) = cli_get_params(
    ['help' => false, 'dry-run' => false, 'userid' => 0, 'force' => false],
    ['h' => 'help']
);

if ($options['help']) {
    $help = "Import generated HTML files from dataroot/local_autocurriculum_contentbank into Content bank.\n\n" .
        "Options:\n  --dry-run       : Do not write to DB, just show what would be done.\n" .
        "  --userid=ID     : User id to set as owner (defaults to admin).\n";
    echo $help;
    exit(0);
}

$dryrun = (bool)$options['dry-run'];
$force = (bool)$options['force'];
$userid = (int)$options['userid'];
if (empty($userid)) {
    $admin = get_admin();
    $userid = $admin->id;
}

$dir = $CFG->dataroot . '/local_autocurriculum_contentbank';
if (!is_dir($dir)) {
    cli_error("Directory not found: $dir\n");
}

$files = glob($dir . '/*.html');
if (empty($files)) {
    cli_writeln("No HTML files found in $dir\n");
    exit(0);
}

echo "Found " . count($files) . " files to import.\n";

$fs = get_file_storage();
$contentbank = new core_contentbank\contentbank();

foreach ($files as $file) {
    $basename = basename($file);
    // Determine target context from filename pattern: category_{id}.html or course_{id}.html
    if (preg_match('/^category_(\d+)\.html$/', $basename, $m)) {
        $id = (int)$m[1];
        $context = context_coursecat::instance($id);
        $target = "category id=$id";
    } elseif (preg_match('/^course_(\d+)\.html$/', $basename, $m)) {
        $id = (int)$m[1];
        $context = context_course::instance($id);
        $target = "course id=$id";
    } else {
        echo "Skipping unrecognized file name: $basename\n";
        continue;
    }

    echo "Importing $basename into content bank context: $target\n";

    // If a contentbank entry with this name already exists in this context, handle it.
    $existing = $DB->get_record('contentbank_content', ['contextid' => $context->id, 'name' => $basename]);
    if ($existing && !$force) {
        echo "  Skipping - contentbank entry already exists (id={$existing->id}). Use --force to replace.\n";
        continue;
    }

    // Create a stored_file in the target context as a temporary file (component: local_autocurriculum).
    $filerecord = [
        'contextid' => $context->id,
        'component' => 'local_autocurriculum',
        'filearea'  => 'generated',
        'itemid'    => 0,
        'filepath'  => '/',
        'filename'  => $basename,
        'timecreated' => time(),
        'timemodified' => time(),
    ];

    if ($dryrun) {
        echo "  [dry-run] would create stored_file and call contentbank->create_content_from_file()\n";
        continue;
    }

    try {
        $stored = $fs->create_file_from_pathname($filerecord, $file);
    } catch (Exception $e) {
        // If the file already exists in the area, reuse the existing stored_file instead of failing.
        $existingstored = $fs->get_file($context->id, 'local_autocurriculum', 'generated', 0, '/', $basename);
        if ($existingstored) {
            $stored = $existingstored;
        } else {
            echo "  Failed to create stored_file: " . $e->getMessage() . "\n";
            continue;
        }
    }

    // Decide how to import the file: prefer the contentbank API when a contenttype supports the extension.
    $extension = $contentbank->get_extension($basename);
    $supporter = $contentbank->get_extension_supporter($extension, $context);

    if ($supporter !== null) {
        try {
            if ($existing) {
                // Replace existing content using plugin replace_content.
                if ($dryrun) {
                    echo "  [dry-run] would replace existing content id={$existing->id} using contentbank plugin.\n";
                } else {
                    try {
                        $content = $contentbank->get_content_from_id($existing->id);
                        $contenttypeinstance = $content->get_content_type_instance();
                        $contenttypeinstance->replace_content($stored, $content);
                        echo "  Replaced existing content id={$existing->id} name=" . s($content->get_name()) . "\n";
                    } catch (Exception $e) {
                        echo "  Error replacing existing content: " . $e->getMessage() . "\n";
                    }
                }
            } else {
                // Create new content from file.
                $content = $contentbank->create_content_from_file($context, $userid, $stored);
                if ($content) {
                    echo "  Created content id=" . $content->get_id() . " name=" . s($content->get_name()) . "\n";
                } else {
                    echo "  create_content_from_file returned null — maybe unsupported extension.\n";
                }
            }
        } catch (Exception $e) {
            echo "  Error creating/replacing content: " . $e->getMessage() . "\n";
        }
    } else {
        // No contenttype supporter registered for this extension. Fall back to creating a
        // contentbank_content DB entry with contenttype 'contenttype_file' and attach the file
        // into the 'contentbank','public' area for that record.
        global $DB;

        $record = new stdClass();
        $record->name = $basename;
        $record->usercreated = $userid;
        $record->timecreated = time();
        $record->timemodified = $record->timecreated;
        $record->usermodified = $record->usercreated;
        $record->contenttype = 'contenttype_file';
        $record->contextid = $context->id;
        $record->configdata = '';
        $record->instanceid = 0;
        try {
            if ($existing) {
                // If record exists and --force, we will reuse it instead of inserting a duplicate.
                $record->id = $existing->id;
            } else {
                $record->id = $DB->insert_record('contentbank_content', $record);
            }
        } catch (Exception $e) {
            echo "  Failed to create contentbank_content record: " . $e->getMessage() . "\n";
            continue;
        }

        // Move the stored file into the contentbank public area for the newly created content.
        $destfilerecord = [
            'contextid' => $context->id,
            'component' => 'contentbank',
            'filearea'  => 'public',
            'itemid'    => $record->id,
            'filepath'  => '/',
            'filename'  => $basename,
            'timecreated' => time(),
            'timemodified' => time(),
        ];

        try {
            if ($dryrun) {
                echo "  [dry-run] would attach or replace file for contentbank record id=" . $record->id . "\n";
            } else {
                // Check if a file already exists in the contentbank public area for this content.
                $existingfile = $fs->get_file($context->id, 'contentbank', 'public', $record->id, '/', $basename);
                if ($existingfile) {
                    // Replace existing file content to avoid duplicate pathnamehash errors.
                    try {
                        $existingfile->replace_file_with($stored);
                        echo "  Replaced file for content id=" . $record->id . "\n";
                    } catch (Exception $e) {
                        echo "  Failed to replace existing file: " . $e->getMessage() . "\n";
                        continue;
                    }
                } else {
                    // Create the file in the contentbank public area.
                    $newstored = $fs->create_file_from_storedfile($destfilerecord, $stored);
                    echo "  Created fallback content id=" . $record->id . " and attached file.\n";
                }
            }
        } catch (Exception $e) {
            echo "  Failed to attach file to contentbank record: " . $e->getMessage() . "\n";
            // Cleanup DB record to avoid orphaned entries.
            if (empty($existing)) {
                $DB->delete_records('contentbank_content', ['id' => $record->id]);
            }
            continue;
        }
    }
}

echo "Import complete.\n";
