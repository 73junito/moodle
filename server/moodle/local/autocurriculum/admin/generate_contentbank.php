<?php
// Admin page: generate content files for top-level categories and courses using Ollama.
require_once __DIR__ . '/../../../config.php';
require_login();
if (!is_siteadmin()) {
    throw new \moodle_exception('adminonly', 'local_autocurriculum');
}

$context = context_system::instance();
$PAGE->set_context($context);
$PAGE->set_url(new \moodle_url('/local/autocurriculum/admin/generate_contentbank.php'));
$PAGE->set_title('Generate Contentbank (files)');
$PAGE->set_heading('Generate Contentbank (files)');

echo $OUTPUT->header();
echo $OUTPUT->heading('Generate Contentbank files for top-level categories and courses');

$action = optional_param('action', '', PARAM_ALPHA);
$confirm = optional_param('confirm', 0, PARAM_INT);
$callollama = optional_param('call_ollama', 0, PARAM_INT);

global $DB, $CFG;

$categories = $DB->get_records('course_categories', ['parent' => 0]);
if (empty($categories)) {
    echo $OUTPUT->notification('No top-level categories found.', core\notification::INFO);
    echo $OUTPUT->footer();
    exit;
}

// Show found categories and offer dry-run or apply.
echo \html_writer::start_tag('div', ['class' => 'box']);
echo \html_writer::tag('p', 'Found ' . count($categories) . ' top-level categories.');
echo \html_writer::start_tag('ul');
foreach ($categories as $c) {
    echo \html_writer::tag('li', s($c->name) . ' (id=' . $c->id . ')');
}
echo \html_writer::end_tag('ul');
echo \html_writer::end_tag('div');

// Form
if (!$confirm) {
    $formurl = new \moodle_url('/local/autocurriculum/admin/generate_contentbank.php');
    echo \html_writer::start_tag('form', ['method' => 'post', 'action' => $formurl->out(false)]);
    echo \html_writer::tag('label', 'Call Ollama?');
    echo \html_writer::empty_tag('br');
    echo \html_writer::tag('input', null, ['type' => 'checkbox', 'name' => 'call_ollama', 'value' => 1]);
    echo \html_writer::empty_tag('br');
    echo \html_writer::empty_tag('input', ['type' => 'hidden', 'name' => 'confirm', 'value' => 1]);
    echo \html_writer::empty_tag('input', ['type' => 'hidden', 'name' => 'sesskey', 'value' => sesskey()]);
    echo \html_writer::empty_tag('br');
    echo \html_writer::tag('button', 'Preview (dry-run)', ['type' => 'submit', 'name' => 'action', 'value' => 'preview', 'class' => 'btn btn-secondary']);
    echo ' ';
    echo \html_writer::tag('button', 'Generate and write files', ['type' => 'submit', 'name' => 'action', 'value' => 'apply', 'class' => 'btn btn-primary']);
    echo \html_writer::end_tag('form');
    echo $OUTPUT->footer();
    exit;
}

// Process action
require_sesskey();
$dryrun = ($action === 'preview');
$call = ($callollama == 1);

$ollama_endpoint = isset($CFG->ollama_server) ? $CFG->ollama_server : 'http://localhost:11434/api/generate';
$model = 'qwen3-vl';
$systeminstruction = "You are an expert teaching assistant. Produce a concise HTML summary and suggested syllabus for the given category or course. Use headings and lists where appropriate.";

function call_ollama_sync($endpoint, $model, $prompt, $system = '')
{
    $payload = ['model' => $model, 'prompt' => $prompt];
    if ($system !== '') {
        $payload['system'] = $system;
    }
    $ch = curl_init();
    curl_setopt($ch, CURLOPT_URL, $endpoint);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_HTTPHEADER, ['Content-Type: application/json']);
    curl_setopt($ch, CURLOPT_POST, true);
    curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($payload));
    $resp = curl_exec($ch);
    if ($resp === false) {
        $err = curl_error($ch);
        curl_close($ch);
        return ['error' => $err];
    }
    curl_close($ch);
    // Ollama may return NDJSON (streaming JSON objects one per line). Parse accordingly.
    $out = '';
    $lines = preg_split('/\r?\n/', $resp);
    foreach ($lines as $line) {
        $line = trim($line);
        if ($line === '') { continue;
        }
        $decoded = json_decode($line, true);
        if (!is_array($decoded)) { continue;
        }
        if (isset($decoded['response']) && is_string($decoded['response']) && $decoded['response'] !== '') {
            $out .= $decoded['response'];
        } elseif (isset($decoded['text']) && is_string($decoded['text'])) {
            $out .= $decoded['text'];
        } elseif (isset($decoded['results']) && is_array($decoded['results'])) {
            foreach ($decoded['results'] as $r) {
                if (is_string($r)) { $out .= $r;
                } elseif (is_array($r) && isset($r['text'])) { $out .= $r['text'];
                }
            }
        }
    }
    if ($out === '') {
        return ['error' => 'No usable text found in Ollama response', 'raw' => $resp];
    }
    return ['text' => $out];
}

$backupdir = $CFG->dataroot . '/local_autocurriculum_contentbank';
if (!$dryrun && !file_exists($backupdir)) {
    if (!mkdir($backupdir, 0777, true) && !is_dir($backupdir)) {
        echo $OUTPUT->notification('Failed to create backup dir: ' . s($backupdir), core\notification::ERROR);
        echo $OUTPUT->footer();
        exit;
    }
}

foreach ($categories as $cat) {
    $catid = $cat->id;
    $catname = $cat->name;
    $prompt = "Create an HTML summary and suggested syllabus for the course category named: {$catname}. Provide headings, a short description, and a bulleted list of suggested topics and week-by-week plan.";
    if ($call) {
        $resp = call_ollama_sync($ollama_endpoint, $model, $prompt, $systeminstruction);
        if (isset($resp['error'])) {
            echo $OUTPUT->notification('Ollama call failed for category ' . s($catname) . ': ' . s($resp['error']), core\notification::ERROR);
            continue;
        }
        $html = $resp['text'];
    } else {
        $html = "<h1>" . s($catname) . "</h1>\n<p>(Dry-run) Generated content would appear here.</p>\n<pre>Prompt:\n" . s($prompt) . "</pre>";
    }
    $file = $backupdir . '/category_' . $catid . '.html';
    if ($dryrun) {
        echo \html_writer::tag('p', 'Would write file: ' . s($file));
    } else {
        file_put_contents($file, $html);
        echo \html_writer::tag('p', 'Wrote file: ' . s($file));
    }

    $courses = $DB->get_records('course', ['category' => $catid]);
    foreach ($courses as $course) {
        $promptc = "Create an HTML summary and suggested syllabus for the course named: {$course->fullname}. Provide a concise description, learning outcomes, and a week-by-week plan.";
        if ($call) {
            $resp = call_ollama_sync($ollama_endpoint, $model, $promptc, $systeminstruction);
            if (isset($resp['error'])) {
                echo $OUTPUT->notification('Ollama call failed for course ' . s($course->fullname) . ': ' . s($resp['error']), core\notification::ERROR);
                continue;
            }
            $htmlc = $resp['text'];
        } else {
            $htmlc = "<h1>" . s($course->fullname) . "</h1>\n<p>(Dry-run) Generated content would appear here.</p>\n<pre>Prompt:\n" . s($promptc) . "</pre>";
        }
        $filec = $backupdir . '/course_' . $course->id . '.html';
        if ($dryrun) {
            echo \html_writer::tag('p', 'Would write file: ' . s($filec));
        } else {
            file_put_contents($filec, $htmlc);
            echo \html_writer::tag('p', 'Wrote file: ' . s($filec));
        }
    }
}

echo $OUTPUT->notification('Operation complete. Files are in: ' . s($backupdir), core\notification::INFO);
echo $OUTPUT->footer();
