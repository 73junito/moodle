<?php

// File: scan.php

require __DIR__ . '/../../config.php';

require_login();
require_capability('moodle/site:config', context_system::instance()); // Require admin

$PAGE->set_url('/local/autocurriculum/scan.php');
$PAGE->set_context(context_system::instance());
$PAGE->set_title(get_string('scan_courses', 'local_autocurriculum'));
$PAGE->set_heading(get_string('scan_courses', 'local_autocurriculum'));

echo $OUTPUT->header();
echo $OUTPUT->heading(get_string('scan_courses', 'local_autocurriculum'));

// Get all courses
$courses = $DB->get_records('course', null, 'fullname', 'id, fullname');

$results = array();
foreach ($courses as $course) {
    $missing = local_autocurriculum_scan_course($course->id);
    if (!empty($missing)) {
        $results[$course->id] = array(
            'fullname' => $course->fullname,
            'missing' => $missing
        );
    }
}

if (empty($results)) {
    echo $OUTPUT->notification(get_string('no_missing_items', 'local_autocurriculum'), 'info');
} else {
    $table = new html_table();
    $table->head = array(
        get_string('course'),
        get_string('missing', 'local_autocurriculum')
    );
    $table->data = array();

    foreach ($results as $courseid => $result) {
        $missing_str = implode(
            ', ',
            array_map(
                function ($item) {
                    return get_string('missing_' . str_replace(' ', '_', $item), 'local_autocurriculum');
                },
                $result['missing']
            )
        );
        $table->data[] = array(
            $result['fullname'],
            $missing_str
        );
    }

    echo html_writer::table($table);
}

echo $OUTPUT->footer();
