<?php
define('CLI_SCRIPT', true);

require_once(__DIR__ . '/../../../config.php');
require_once($CFG->libdir . '/clilib.php');
require_once($CFG->dirroot . '/local/autocurriculum/lib.php');

// Get CLI options.
$longoptions = array(
    'courses' => '',
    'help' => false,
);

$options = cli_get_options($longoptions);

if ($options['help']) {
    echo "Scan courses for missing or incomplete descriptions, lessons, syllabus, and question banks.\n";
    echo "Usage: php scan_courses.php [--courses=1,2,3]\n";
    echo "If --courses is not specified, scans all courses.\n";
    exit(0);
}

if (!empty($options['courses'])) {
    $courseids = explode(',', $options['courses']);
} else {
    global $DB;
    $courses = $DB->get_records('course', null, '', 'id');
    $courseids = array_keys($courses);
}

echo "Scanning " . count($courseids) . " courses...\n";

foreach ($courseids as $courseid) {
    $missing = local_autocurriculum_scan_course($courseid);
    if (!empty($missing)) {
        $course = $DB->get_record('course', array('id' => $courseid), 'fullname');
        echo "Course: {$course->fullname} (ID: {$courseid}) - Missing: " . implode(', ', $missing) . "\n";
    }
}

echo "Scan complete.\n";