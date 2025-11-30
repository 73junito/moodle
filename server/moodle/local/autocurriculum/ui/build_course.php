<?php
require(__DIR__ . '/../../config.php');

require_login();
$context = context_system::instance();
require_capability('local/ase_builder:build', $context);

require_sesskey();

$PAGE->set_context($context);
$PAGE->set_url(new moodle_url('/local/ase_builder/ui/build_course.php'));
$PAGE->set_title(get_string('buildcourses', 'local_ase_builder'));
$PAGE->set_heading(get_string('buildcourses', 'local_ase_builder'));

echo $OUTPUT->header();

$builder = new \local_ase_builder\builder\course_builder();
$builder->build_all_programs();

echo $OUTPUT->notification(get_string('build_success', 'local_ase_builder'), 'notifysuccess');

$backurl = new moodle_url('/local/ase_builder/ui/dashboard.php');
echo html_writer::link($backurl, get_string('dashboard', 'local_ase_builder'));

echo $OUTPUT->footer();
