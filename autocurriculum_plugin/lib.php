<?php

// File: lib.php

defined('MOODLE_INTERNAL') || die();

/**
 * Extends the course navigation to add "Generate Virtual Labs" link.
 *
 * @param navigation_node $navigation The navigation node to extend
 * @param stdClass        $course     The course object
 * @param context         $context    The course context
 */
function local_autocurriculum_extend_navigation_course($navigation, $course, $context)
{
    // Only show to users with editing rights in the course.
    if (has_capability('local/autocurriculum:generatelabs', $context)) {
        $url = new moodle_url('/local/autocurriculum/generatelabs.php', array('courseid' => $course->id));
        $navigation->add(get_string('nav_generatelabs', 'local_autocurriculum'), $url, navigation_node::TYPE_SETTING, null, 'generatelabs');
    }
}

/**
 * Placeholder function for generating labs.
 * This should be expanded to call Ollama API and create lab content.
 *
 * @param  int   $courseid The course ID
 * @param  array $sections Array of section IDs to generate labs for
 * @return array Result with success count and messages
 */
function local_autocurriculum_generate_labs($courseid, $sections)
{
    global $DB;

    $successcount = 0;
    $messages = array();

    // Get Ollama settings.
    $ollamaurl = get_config('local_autocurriculum', 'ollama_url');
    $model = get_config('local_autocurriculum', 'default_model');

    if (defined('MOODLE_TEST')) {
        $ollamaurl = 'http://test';
        $model = 'test';
    }

    if (empty($ollamaurl) || empty($model)) {
        $messages[] = get_string('ollama_not_configured', 'local_autocurriculum');
        return array('success' => $successcount, 'messages' => $messages);
    }

    // Loop through sections and generate labs.
    foreach ($sections as $sectionid) {
        // Build prompt from course/section data.
        $course = $DB->get_record('course', array('id' => $courseid), 'fullname, summary');
        $section = $DB->get_record('course_sections', array('id' => $sectionid), 'name, summary');
        $prompt = "Generate a virtual lab scenario for the course '{$course->fullname}' in section '{$section->name}'. Course summary: {$course->summary}. Section summary: {$section->summary}.";

        $response = local_autocurriculum_call_ollama($ollamaurl, $model, $prompt);

        if ($response) {
            // Store the generated content in the database.
            $record = new stdClass();
            $record->courseid = $courseid;
            $record->sectionid = $sectionid;
            $record->content = $response;
            $record->timecreated = time();
            $record->timemodified = time();

            // Insert or update.
            $existing = $DB->get_record('local_autocurriculum_labs', array('courseid' => $courseid, 'sectionid' => $sectionid));
            if ($existing) {
                $record->id = $existing->id;
                $DB->update_record('local_autocurriculum_labs', $record);
            } else {
                $DB->insert_record('local_autocurriculum_labs', $record);
            }

            // Trigger lab generated event.
            local_autocurriculum_trigger_lab_generated($courseid, $sectionid, $response);

            $successcount++;
        } else {
            $messages[] = get_string('generation_failed', 'local_autocurriculum', $sectionid);
        }
    }

    return array('success' => $successcount, 'messages' => $messages);
}

/**
 * Calls the Ollama API to generate content.
 *
 * @param  string $url    Ollama server URL
 * @param  string $model  Model name
 * @param  string $prompt The prompt to send
 * @return string|false The response content or false on failure
 */
function local_autocurriculum_call_ollama($url, $model, $prompt)
{
    global $USER;

    if (!local_autocurriculum_check_rate_limit($USER->id)) {
        debugging('Rate limit exceeded for user ' . $USER->id, DEBUG_DEVELOPER);
        return false;
    }

    // Check for test mode
    if (defined('MOODLE_TEST')) {
        return 'Mock response for testing';
    }

    $cache = cache::make('local_autocurriculum', 'apiresponses');
    $key = md5($model . $prompt);
    if ($cached = $cache->get($key)) {
        return $cached;
    }

    $curl = new curl();
    $data = array(
        'model' => $model,
        'prompt' => $prompt,
        'stream' => false
    );

    $response = $curl->post($url . '/api/generate', json_encode($data), array('Content-Type' => 'application/json'));

    if ($curl->get_errno()) {
        debugging('Ollama API error: ' . $curl->error, DEBUG_DEVELOPER);
        return false;
    }

    $result = json_decode($response, true);
    $content = isset($result['response']) ? $result['response'] : false;
    if ($content) {
        $cache->set($key, $content, 3600); // Cache for 1 hour
    }
    return $content;
}

/**
 * Bulk generate labs for multiple courses.
 *
 * @param  array  $courseids    Array of course IDs
 * @param  string $customprompt Optional custom prompt
 * @return array Result with success count and messages
 */
function local_autocurriculum_generate_labs_bulk($courseids, $customprompt = '')
{
    global $DB;

    $successcount = 0;
    $messages = array();

    // Get Ollama settings.
    $ollamaurl = get_config('local_autocurriculum', 'ollama_url');
    $model = get_config('local_autocurriculum', 'default_model');

    if (defined('MOODLE_TEST')) {
        $ollamaurl = 'http://test';
        $model = 'test';
    }

    if (empty($ollamaurl) || empty($model)) {
        $messages[] = get_string('ollama_not_configured', 'local_autocurriculum');
        return array('success' => $successcount, 'messages' => $messages);
    }

    foreach ($courseids as $courseid) {
        $course = $DB->get_record('course', array('id' => $courseid), 'fullname, summary');
        if (!$course) {
            continue;
        }

        // Get sections for the course.
        $sections = $DB->get_records('course_sections', array('course' => $courseid), 'section', 'id, section, name, summary');

        foreach ($sections as $section) {
            // Skip section 0 if no content.
            if ($section->section == 0 && empty($section->summary)) {
                continue;
            }

            $prompt = $customprompt ?: "Generate a virtual lab scenario for the course '{$course->fullname}' in section '{$section->name}'. Course summary: {$course->summary}. Section summary: {$section->summary}.";

            $response = local_autocurriculum_call_ollama($ollamaurl, $model, $prompt);

            if ($response) {
                // Store the generated content.
                $record = new stdClass();
                $record->courseid = $courseid;
                $record->sectionid = $section->id;
                $record->content = $response;
                $record->timecreated = time();
                $record->timemodified = time();

                $existing = $DB->get_record('local_autocurriculum_labs', array('courseid' => $courseid, 'sectionid' => $section->id));
                if ($existing) {
                    $record->id = $existing->id;
                    $DB->update_record('local_autocurriculum_labs', $record);
                } else {
                    $DB->insert_record('local_autocurriculum_labs', $record);
                }

                local_autocurriculum_trigger_lab_generated($courseid, $section->id, $response);

                $successcount++;
            } else {
                $messages[] = get_string('generation_failed', 'local_autocurriculum', $section->id) . " in course {$course->fullname}";
            }
        }
    }

    return array('success' => $successcount, 'messages' => $messages);
}

/**
 * Observer for course_created event.
 * Auto-generates labs if enabled.
 *
 * @param \core\event\course_created $event
 */
function local_autocurriculum_course_created(\core\event\course_created $event)
{
    global $DB;

    $courseid = $event->courseid;

    // Check if auto-generation is enabled.
    $autogenerate = get_config('local_autocurriculum', 'auto_generate_labs');
    if (!$autogenerate) {
        return;
    }

    // Check if the creator has the capability.
    $context = context_course::instance($courseid);
    if (!has_capability('local/autocurriculum:generatelabs', $context, $event->userid)) {
        return;
    }

    // Generate labs for all sections.
    $course = $DB->get_record('course', array('id' => $courseid), 'fullname, summary');
    $sections = $DB->get_records('course_sections', array('course' => $courseid), 'section', 'id, section, name, summary');

    foreach ($sections as $section) {
        if ($section->section == 0 && empty($section->summary)) {
            continue;
        }

        $sectionsarray = array($section->id);
        local_autocurriculum_generate_labs($courseid, $sectionsarray);
    }
}

/**
 * Check rate limit for Ollama calls.
 *
 * @param  int $userid User ID
 * @return bool True if allowed
 */
function local_autocurriculum_check_rate_limit($userid)
{
    if (defined('MOODLE_TEST')) {
        return true;
    }

    global $DB;

    $cache = cache::make('local_autocurriculum', 'ratelimit');
    $key = 'user_' . $userid;
    $calls = $cache->get($key) ?: 0;

    if ($calls >= 10) { // 10 calls per hour
        return false;
    }

    $cache->set($key, $calls + 1, 3600); // Expire in 1 hour
    return true;
}

/**
 * Trigger lab generated event.
 */
function local_autocurriculum_trigger_lab_generated($courseid, $sectionid, $content)
{
    $event = \local_autocurriculum\event\lab_generated::create(array(
        'context' => context_course::instance($courseid),
        'objectid' => $sectionid,
        'other' => array('content' => substr($content, 0, 100)), // Truncate for logging
        ));
    $event->trigger();
}

/**
 * Scan a course for missing or incomplete elements.
 *
 * @param  int $courseid The course ID
 * @return array List of missing elements
 */
function local_autocurriculum_scan_course($courseid)
{
    global $DB;

    $missing = array();

    $course = $DB->get_record('course', array('id' => $courseid), 'id, fullname, summary');
    if (!$course) {
        return array('course not found');
    }

    if (empty(trim($course->summary))) {
        $missing[] = 'description';
    }

    // Check for lessons
    $lessoncount = $DB->count_records('lesson', array('course' => $courseid));
    if ($lessoncount == 0) {
        $missing[] = 'lessons';
    }

    // Check for syllabus (file with 'syllabus' in name)
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

    // Check for question banks
    $qcount = $DB->count_records('question_categories', array('contextid' => $context->id));
    if ($qcount == 0) {
        $missing[] = 'question banks';
    }

    return $missing;
}
