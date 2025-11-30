<?php
// File: lib.php

defined('MOODLE_INTERNAL') || die();

/**
 * Extends the course navigation to add "Generate Virtual Labs" link.
 *
 * @param navigation_node $navigation The navigation node to extend
 * @param stdClass $course The course object
 * @param context $context The course context
 */
function local_autocurriculum_extend_navigation_course($navigation, $course, $context) {
    // Only show to users with editing rights in the course.
    if (has_capability('local/autocurriculum:generatelabs', $context)) {
        $url = new moodle_url('/local/autocurriculum/generatelabs.php', ['courseid' => $course->id]);
        $navigation->add(
            get_string('nav_generatelabs', 'local_autocurriculum'),
            $url,
            navigation_node::TYPE_SETTING,
            null,
            'generatelabs'
        );
    }
}

/**
 * Placeholder function for generating labs.
 *
 * @param int $courseid The course ID
 * @param array $sections Array of section IDs
 * @return array Result with success count and messages
 */
function local_autocurriculum_generate_labs($courseid, $sections) {
    global $DB;

    $successcount = 0;
    $messages = [];

    // Get Ollama settings.
    $ollamaurl = get_config('local_autocurriculum', 'ollama_url');
    $model = get_config('local_autocurriculum', 'default_model');

    if (defined('MOODLE_TEST')) {
        $ollamaurl = 'http://test';
        $model = 'test';
    }

    if (empty($ollamaurl) || empty($model)) {
        $messages[] = get_string('ollama_not_configured', 'local_autocurriculum');
        return ['success' => $successcount, 'messages' => $messages];
    }

    foreach ($sections as $sectionid) {
        $course = $DB->get_record('course', ['id' => $courseid], 'fullname, summary');
        $section = $DB->get_record('course_sections', ['id' => $sectionid], 'name, summary');

        $prompt = "Generate a virtual lab scenario for the course '{$course->fullname}' in section '{$section->name}'. "
            . "Course summary: {$course->summary}. Section summary: {$section->summary}.";

        $response = local_autocurriculum_call_ollama($ollamaurl, $model, $prompt);

        if ($response) {
            $record = (object)[
                'courseid' => $courseid,
                'sectionid' => $sectionid,
                'content' => $response,
                'timecreated' => time(),
                'timemodified' => time(),
            ];

            $existing = $DB->get_record(
                'local_autocurriculum_labs',
                ['courseid' => $courseid, 'sectionid' => $sectionid]
            );

            if ($existing) {
                $record->id = $existing->id;
                $DB->update_record('local_autocurriculum_labs', $record);
            } else {
                $DB->insert_record('local_autocurriculum_labs', $record);
            }

            local_autocurriculum_trigger_lab_generated($courseid, $sectionid, $response);
            $successcount++;

        } else {
            $messages[] = get_string('generation_failed', 'local_autocurriculum', $sectionid);
        }
    }

    return ['success' => $successcount, 'messages' => $messages];
}

/**
 * Calls the Ollama API to generate content.
 *
 * @param string $url Ollama server URL
 * @param string $model Model name
 * @param string $prompt The prompt to send
 * @return string|false
 */
function local_autocurriculum_call_ollama($url, $model, $prompt) {
    global $USER;

    if (!local_autocurriculum_check_rate_limit($USER->id)) {
        debugging('Rate limit exceeded for user ' . $USER->id, DEBUG_DEVELOPER);
        return false;
    }

    if (defined('MOODLE_TEST')) {
        return 'Mock response for testing';
    }

    $cache = cache::make('local_autocurriculum', 'apiresponses');
    $key = md5($model . $prompt);

    if ($cached = $cache->get($key)) {
        return $cached;
    }

    $curl = new curl();
    $data = [
        'model' => $model,
        'prompt' => $prompt,
        'stream' => false
    ];

    $response = $curl->post(
        $url . '/api/generate',
        json_encode($data),
        ['Content-Type' => 'application/json']
    );

    if ($curl->get_errno()) {
        debugging('Ollama API error: ' . $curl->error, DEBUG_DEVELOPER);
        return false;
    }

    $result = json_decode($response, true);
    $content = $result['response'] ?? false;

    if ($content) {
        $cache->set($key, $content, 3600);
    }

    return $content;
}

/**
 * Bulk generate labs for multiple courses.
 *
 * @param array $courseids
 * @param string $customprompt
 * @return array
 */
function local_autocurriculum_generate_labs_bulk($courseids, $customprompt = '') {
    global $DB;

    $successcount = 0;
    $messages = [];

    $ollamaurl = get_config('local_autocurriculum', 'ollama_url');
    $model = get_config('local_autocurriculum', 'default_model');

    if (defined('MOODLE_TEST')) {
        $ollamaurl = 'http://test';
        $model = 'test';
    }

    if (empty($ollamaurl) || empty($model)) {
        $messages[] = get_string('ollama_not_configured', 'local_autocurriculum');
        return ['success' => $successcount, 'messages' => $messages];
    }

    foreach ($courseids as $courseid) {
        $course = $DB->get_record('course', ['id' => $courseid], 'fullname, summary');
        if (!$course) {
            continue;
        }

        $sections = $DB->get_records(
            'course_sections',
            ['course' => $courseid],
            'section',
            'id, section, name, summary'
        );

        foreach ($sections as $section) {
            if ($section->section == 0 && empty($section->summary)) {
                continue;
            }

            $prompt = $customprompt ?: (
                "Generate a virtual lab scenario for the course '{$course->fullname}' in section '{$section->name}'. "
                . "Course summary: {$course->summary}. Section summary: {$section->summary}."
            );

            $response = local_autocurriculum_call_ollama($ollamaurl, $model, $prompt);

            if ($response) {
                $record = (object)[
                    'courseid' => $courseid,
                    'sectionid' => $section->id,
                    'content' => $response,
                    'timecreated' => time(),
                    'timemodified' => time(),
                ];

                $existing = $DB->get_record(
                    'local_autocurriculum_labs',
                    ['courseid' => $courseid, 'sectionid' => $section->id]
                );

                if ($existing) {
                    $record->id = $existing->id;
                    $DB->update_record('local_autocurriculum_labs', $record);
                } else {
                    $DB->insert_record('local_autocurriculum_labs', $record);
                }

                local_autocurriculum_trigger_lab_generated($courseid, $section->id, $response);
                $successcount++;

            } else {
                $messages[] =
                    get_string('generation_failed', 'local_autocurriculum', $section->id)
                    . " in course {$course->fullname}";
            }
        }
    }

    return ['success' => $successcount, 'messages' => $messages];
}

/**
 * Observer for course_created event.
 *
 * @param \core\event\course_created $event
 */
function local_autocurriculum_course_created(\core\event\course_created $event) {
    global $DB;

    $courseid = $event->courseid;

    $autogenerate = get_config('local_autocurriculum', 'auto_generate_labs');
    if (!$autogenerate) {
        return;
    }

    $context = context_course::instance($courseid);
    if (!has_capability('local/autocurriculum:generatelabs', $context, $event->userid)) {
        return;
    }

    $sections = $DB->get_records(
        'course_sections',
        ['course' => $courseid],
        'section',
        'id, section, name, summary'
    );

    foreach ($sections as $section) {
        if ($section->section == 0 && empty($section->summary)) {
            continue;
        }

        local_autocurriculum_generate_labs($courseid, [$section->id]);
    }
}

/**
 * Check rate limit for Ollama calls.
 *
 * @param int $userid
 * @return bool
 */
function local_autocurriculum_check_rate_limit($userid) {
    if (defined('MOODLE_TEST')) {
        return true;
    }

    $cache = cache::make('local_autocurriculum', 'ratelimit');
    $key = 'user_' . $userid;

    $calls = $cache->get($key) ?: 0;

    if ($calls >= 10) {
        return false;
    }

    $cache->set($key, $calls + 1, 3600);
    return true;
}

/**
 * Trigger lab generated event.
 *
 * @param int $courseid
 * @param int $sectionid
 * @param string $content
 */
function local_autocurriculum_trigger_lab_generated($courseid, $sectionid, $content) {
    $event = \local_autocurriculum\event\lab_generated::create([
        'context' => context_course::instance($courseid),
        'objectid' => $sectionid,
        'other' => ['content' => substr($content, 0, 100)],
    ]);

    $event->trigger();
}

/**
 * Scan a course for missing or incomplete elements.
 *
 * @param int $courseid
 * @return array
 */
function local_autocurriculum_scan_course($courseid) {
    global $DB;

    $missing = [];

    $course = $DB->get_record('course', ['id' => $courseid], 'id, fullname, summary');
    if (!$course) {
        return ['course not found'];
    }

    if (empty(trim($course->summary))) {
        $missing[] = 'description';
    }

    $lessoncount = $DB->count_records('lesson', ['course' => $courseid]);
    if ($lessoncount == 0) {
        $missing[] = 'lessons';
    }

    $context = context_course::instance($courseid);
    $fs = get_file_storage();
    $files = $fs->get_area_files($context->id, false, false, false, false, false, false);

    $has_syllabus = false;
    foreach ($files as $file) {
        if (stripos($file->get_filename(), 'syllabus') !== false) {
            $has_syllabus = true;
            break;
        }
    }
    if (!$has_syllabus) {
        $missing[] = 'syllabus';
    }

    $qcount = $DB->count_records('question_categories', ['contextid' => $context->id]);
    if ($qcount == 0) {
        $missing[] = 'question banks';
    }

    return $missing;
}