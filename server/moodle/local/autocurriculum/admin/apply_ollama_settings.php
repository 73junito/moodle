<?php
// Admin tool: backup and apply Ollama provider "Generate text" action settings.
// Location: moodle/local/autocurriculum/admin/apply_ollama_settings.php

require_once __DIR__ . '/../../../config.php';
require_login();
if (!is_siteadmin()) {
    throw new \moodle_exception('adminonly', 'local_autocurriculum');
}

$context = context_system::instance();
$PAGE->set_context($context);
$PAGE->set_url(new \moodle_url('/local/autocurriculum/admin/apply_ollama_settings.php'));
$PAGE->set_title(get_string('applyollamasettings', 'local_autocurriculum'));
$PAGE->set_heading(get_string('applyollamasettings', 'local_autocurriculum'));

// Read incoming params.
$confirm = optional_param('confirm', 0, PARAM_INT);
$action = optional_param('action', '', PARAM_ALPHA);
$systeminstruction = optional_param('system_instruction', '', PARAM_RAW_TRIMMED);
$extrajson = optional_param('extra_json', '', PARAM_RAW);

echo $OUTPUT->header();
echo $OUTPUT->heading('Apply Ollama Generate text settings');

// Find candidate providers. Be defensive: table or columns may differ between instances.
try {
    $providers = $DB->get_records('ai_providers');
} catch (\Exception $e) {
    echo $OUTPUT->notification(
        'Database table "ai_providers" not found or inaccessible: ' . s($e->getMessage()),
        core\notification::ERROR
    );
    echo $OUTPUT->footer();
    exit;
}

$matches = [];
foreach ($providers as $prov) {
    $text = json_encode($prov);
    if (stripos($text, 'ollama') !== false || stripos($text, 'aiprovider_ollama') !== false) {
        $matches[] = $prov;
    }
}

if (empty($matches)) {
    echo $OUTPUT->notification('No provider rows matching "ollama" were found in "ai_providers".', core\notification::INFO);
    echo $OUTPUT->single_button(new moodle_url('/admin/search.php', ['query' => 'ollama']), 'Search admin');
    echo $OUTPUT->footer();
    exit;
}

// Show a simple preview table.
echo \html_writer::start_tag('div', ['class' => 'box']);
echo \html_writer::tag('p', 'Found ' . count($matches) . ' matching provider row(s).');
echo \html_writer::start_tag('ul');
foreach ($matches as $m) {
    echo \html_writer::tag('li', 'id=' . $m->id . ' — ' . format_string(isset($m->name) ? $m->name : (isset($m->providername) ? $m->providername : '[unknown]')));
}
echo \html_writer::end_tag('ul');
echo \html_writer::end_tag('div');

// Display editable form for system instruction and extra JSON.
if (empty($systeminstruction)) {
    // Provide a sensible default system instruction — admin can edit before applying.
    $systeminstruction = "You are an expert teaching assistant. Answer concisely and return results suitable for Moodle course content generation.";
}
if (empty($extrajson)) {
    $extrajson = json_encode(['temperature' => 0.2, 'top_p' => 0.95], JSON_PRETTY_PRINT);
}

if (!$confirm) {
    $formurl = new \moodle_url('/local/autocurriculum/admin/apply_ollama_settings.php');
    echo \html_writer::start_tag('form', ['method' => 'post', 'action' => $formurl->out(false)]);
    echo \html_writer::tag('label', 'System instruction');
    echo \html_writer::empty_tag('br');
    echo \html_writer::tag('textarea', s($systeminstruction), ['name' => 'system_instruction', 'rows' => 6, 'cols' => 80]);
    echo \html_writer::empty_tag('br');
    echo \html_writer::tag('label', 'Extra parameters (JSON)');
    echo \html_writer::empty_tag('br');
    echo \html_writer::tag('textarea', s($extrajson), ['name' => 'extra_json', 'rows' => 6, 'cols' => 80]);
    echo \html_writer::empty_tag('br');
    // Two actions: preview (dry-run) or apply (writes backup and updates DB).
    echo \html_writer::empty_tag('input', ['type' => 'hidden', 'name' => 'confirm', 'value' => 1]);
    echo \html_writer::empty_tag('input', ['type' => 'hidden', 'name' => 'sesskey', 'value' => sesskey()]);
    echo \html_writer::empty_tag('br');
    echo \html_writer::tag('button', 'Preview changes (dry-run)', ['type' => 'submit', 'name' => 'action', 'value' => 'preview', 'class' => 'btn btn-secondary']);
    echo ' ';
    echo \html_writer::tag('button', 'Apply settings to matched providers', ['type' => 'submit', 'name' => 'action', 'value' => 'apply', 'class' => 'btn btn-primary']);
    echo \html_writer::end_tag('form');
    echo $OUTPUT->footer();
    exit;
}

// If user requested a preview (dry-run), compute and display intended JSON diffs without touching DB.
$extra = json_decode($extrajson, true);
if ($extrajson !== '' && $extra === null) {
    echo $OUTPUT->notification('Invalid JSON provided for extra parameters. Please go back and fix it.', core\notification::ERROR);
    echo $OUTPUT->footer();
    exit;
}

if ($action === 'preview') {
    $previewresults = [];
    foreach ($matches as $prov) {
        $id = $prov->id;
        $provobj = clone $prov;
        $previewresults[] = ['id' => $id, 'before' => null, 'after' => null, 'note' => ''];
        // Choose candidate column as below.
    }

    // Determine candidate column like we do for apply.
    $columns = [];
    try {
        $cols = $DB->get_columns('ai_providers');
        $columns = array_keys($cols);
    } catch (Exception $e) {
        // ignore
    }
    $candidatecols = ['settings', 'config', 'actions', 'actionsettings', 'params', 'data'];
    $usedcol = null;
    foreach ($candidatecols as $c) {
        if (empty($columns) || in_array($c, $columns, true)) {
            $usedcol = $c;
            break;
        }
    }

    echo $OUTPUT->heading('Preview of changes (dry-run)');
    foreach ($matches as $prov) {
        $id = $prov->id;
        if ($usedcol && isset($prov->{$usedcol}) && is_string($prov->{$usedcol})) {
            $data = json_decode($prov->{$usedcol}, true);
            if (is_array($data) && isset($data['actions']) && is_array($data['actions'])) {
                $before = json_encode($data, JSON_PRETTY_PRINT);
                foreach ($data['actions'] as &$actionitem) {
                    if (isset($actionitem['name']) && strtolower(trim($actionitem['name'])) === 'generate text') {
                        $actionitem['model'] = 'qwen3-vl';
                        $actionitem['system_instruction'] = $systeminstruction;
                        $actionitem['extra'] = $extra;
                    }
                }
                unset($actionitem);
                $after = json_encode($data, JSON_PRETTY_PRINT);
                echo \html_writer::tag('h4', "Provider id={$id}");
                echo \html_writer::tag('pre', s($before));
                echo \html_writer::tag('pre', s($after));
            } else {
                echo \html_writer::tag('p', "Provider id={$id} column '{$usedcol}' is not a JSON object with 'actions' array; preview unavailable.");
            }
        } else {
            echo \html_writer::tag('p', "Provider id={$id} does not have a usable '{$usedcol}' column; preview unavailable.");
        }
    }

    echo $OUTPUT->single_button(new moodle_url('/local/autocurriculum/admin/apply_ollama_settings.php'), 'Back to form');
    echo $OUTPUT->footer();
    exit;
}

// Proceed to apply: verify sesskey and create backup.
require_sesskey();

$backupdir = $CFG->dataroot . '/local_autocurriculum_backups';
if (!file_exists($backupdir)) {
    if (!mkdir($backupdir, 0777, true) && !is_dir($backupdir)) {
        echo $OUTPUT->notification('Failed to create backup directory: ' . s($backupdir), core\notification::ERROR);
        echo $OUTPUT->footer();
        exit;
    }
}

$backupfile = $backupdir . '/ollama_backup_' . date('Ymd_His') . '.json';
file_put_contents($backupfile, json_encode($matches, JSON_PRETTY_PRINT));
echo $OUTPUT->notification('Backup written to: ' . s($backupfile), core\notification::SUCCESS);

$columns = [];
try {
    $cols = $DB->get_columns('ai_providers');
    $columns = array_keys($cols);
} catch (\Exception $e) {
    // Be permissive — we'll try to operate on commonly used columns below.
}

$candidatecols = ['settings', 'config', 'actions', 'actionsettings', 'params', 'data'];
$usedcol = null;
foreach ($candidatecols as $c) {
    if (empty($columns) || in_array($c, $columns, true)) {
        $usedcol = $c;
        break;
    }
}

$results = [];
foreach ($matches as $prov) {
    $provobj = clone $prov;
    $id = $prov->id;
    $updated = false;

    if ($usedcol && isset($provobj->{$usedcol}) && is_string($provobj->{$usedcol})) {
        $data = json_decode($provobj->{$usedcol}, true);
        if (is_array($data) && isset($data['actions']) && is_array($data['actions'])) {
            foreach ($data['actions'] as &$action) {
                if (isset($action['name']) && strtolower(trim($action['name'])) === 'generate text') {
                    $action['model'] = 'qwen3-vl';
                    $action['system_instruction'] = $systeminstruction;
                    $action['extra'] = $extra;
                    $updated = true;
                }
            }
            unset($action);
            if ($updated) {
                $rec = new stdClass();
                $rec->id = $id;
                $rec->{$usedcol} = json_encode($data);
                try {
                    $DB->update_record('ai_providers', $rec);
                    $results[] = "Updated provider id={$id} column={$usedcol}";
                } catch (\Exception $e) {
                    $results[] = "Failed to update provider id={$id}: " . $e->getMessage();
                }
            } else {
                $results[] = "No 'Generate text' action found for provider id={$id}; no changes applied.";
            }
        } else {
            $results[] = "Provider id={$id} column '{$usedcol}' is not a JSON object with 'actions' array; manual update required.";
        }
    } else {
        $results[] = "Provider id={$id} does not have a usable '{$usedcol}' column; manual update required.";
    }
}

echo \html_writer::start_tag('div', ['class' => 'box']);
echo \html_writer::tag('h3', 'Operation results');
echo \html_writer::start_tag('ul');
foreach ($results as $r) {
    echo \html_writer::tag('li', s($r));
}
echo \html_writer::end_tag('ul');
echo \html_writer::end_tag('div');

echo $OUTPUT->notification('If updates were applied, consider purging caches and resetting opcache (admin utilities under local/autocurriculum/admin).', core\notification::INFO);

echo $OUTPUT->single_button(new \moodle_url('/local/autocurriculum/admin/remove_ollama.php'), 'Back to provider cleanup');
echo $OUTPUT->footer();

// End of file
