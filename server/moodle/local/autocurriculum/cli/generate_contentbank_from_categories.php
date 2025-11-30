<?php
// CLI script: generate content (HTML) for top-level categories and their courses using Ollama.
// Usage: php generate_contentbank_from_categories.php [--dry-run] [--call-ollama]

define('CLI_SCRIPT', true);
require(__DIR__ . '/../../../config.php');
require_once($CFG->dirroot . '/lib/clilib.php');
global $DB, $CFG;

list($options, $unrecognized) = cli_get_params(
    ['help' => false, 'dry-run' => false, 'call-ollama' => false],
    ['h' => 'help']
);

if ($options['help']) {
    $help = "Generates HTML files for top-level categories and their courses using Ollama.\n\n" .
        "Options:\n  --dry-run       : Do not call Ollama or write files, just show what would be done.\n" .
        "  --call-ollama   : Actually call Ollama (default: off).\n";
    echo $help;
    exit(0);
}

$dryrun = (bool)$options['dry-run'];
$callollama = (bool)$options['call-ollama'];

$ollama_endpoint = isset($CFG->ollama_server) ? $CFG->ollama_server : 'http://localhost:11434/api/generate';
$model = 'qwen3-vl';
$systeminstruction = "You are an expert teaching assistant. Produce a concise HTML summary and suggested syllabus for the given category or course. Use headings and lists where appropriate.";

// Get top-level categories (parent = 0)
$categories = $DB->get_records('course_categories', ['parent' => 0]);
if (empty($categories)) {
    echo "No top-level categories found.\n";
    exit(0);
}

$backupdir = $CFG->dataroot . '/local_autocurriculum_contentbank';
if (!$dryrun && !file_exists($backupdir)) {
    if (!mkdir($backupdir, 0777, true) && !is_dir($backupdir)) {
        cli_error("Failed to create backup dir: $backupdir\n");
    }
}

echo "Found " . count($categories) . " top-level categories.\n";

function call_ollama($endpoint, $model, $prompt, $system = '')
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
    // Ollama often returns NDJSON (newline-delimited JSON streaming). Parse lines.
    $out = '';
    $lines = preg_split('/\r?\n/', $resp);
    foreach ($lines as $line) {
        $line = trim($line);
        if ($line === '') {
            continue;
        }
        $decoded = json_decode($line, true);
        if (!is_array($decoded)) {
            // skip non-json lines
            continue;
        }
        if (isset($decoded['response']) && is_string($decoded['response']) && $decoded['response'] !== '') {
            $out .= $decoded['response'];
        } elseif (isset($decoded['text']) && is_string($decoded['text'])) {
            $out .= $decoded['text'];
        } elseif (isset($decoded['results']) && is_array($decoded['results'])) {
            foreach ($decoded['results'] as $r) {
                if (is_string($r)) {
                    $out .= $r;
                } elseif (is_array($r) && isset($r['text'])) {
                    $out .= $r['text'];
                }
            }
        }
    }
    if ($out === '') {
        return ['error' => 'No usable text found in Ollama response', 'raw' => $resp];
    }
    return ['text' => $out];
}

foreach ($categories as $cat) {
    $catid = $cat->id;
    $catname = $cat->name;
    echo "Category: {$catname} (id={$catid})\n";

    $prompt = "Create an HTML summary and suggested syllabus for the course category named: {$catname}. Provide headings, a short description, and a bulleted list of suggested topics and week-by-week plan.";

    if ($callollama) {
        $resp = call_ollama($ollama_endpoint, $model, $prompt, $systeminstruction);
        if (isset($resp['error'])) {
            echo "  Ollama call failed: " . $resp['error'] . "\n";
            continue;
        }
        $html = $resp['text'];
    } else {
        $html = "<h1>" . s($catname) . "</h1>\n<p>(Dry-run) Generated content would appear here.</p>\n<pre>Prompt:\n" . s($prompt) . "</pre>";
    }

    $filename = $backupdir . "/category_{$catid}.html";
    if ($dryrun) {
        echo "  Would write file: {$filename}\n";
    } else {
        file_put_contents($filename, $html);
        echo "  Wrote file: {$filename}\n";
    }

    // Now generate for courses within this category (visible courses)
    $courses = $DB->get_records('course', ['category' => $catid]);
    foreach ($courses as $course) {
        $courseid = $course->id;
        $coursename = $course->fullname;
        echo "  Course: {$coursename} (id={$courseid})\n";
        $promptc = "Create an HTML summary and suggested syllabus for the course named: {$coursename}. Provide a concise description, learning outcomes, and a week-by-week plan.";
        if ($callollama) {
            $resp = call_ollama($ollama_endpoint, $model, $promptc, $systeminstruction);
            if (isset($resp['error'])) {
                echo "    Ollama call failed: " . $resp['error'] . "\n";
                continue;
            }
            $htmlc = $resp['text'];
        } else {
            $htmlc = "<h1>" . s($coursename) . "</h1>\n<p>(Dry-run) Generated content would appear here.</p>\n<pre>Prompt:\n" . s($promptc) . "</pre>";
        }
        $filecourse = $backupdir . "/course_{$courseid}.html";
        if ($dryrun) {
            echo "    Would write file: {$filecourse}\n";
        } else {
            file_put_contents($filecourse, $htmlc);
            echo "    Wrote file: {$filecourse}\n";
        }
    }
}

echo "Done. Files are under: {$backupdir}\n";
