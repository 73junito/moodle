<?php
require __DIR__ . '/../../config.php';

require_login();
$context = context_system::instance();
require_capability('local/ase_builder:view', $context);

$pagetitle = get_string('dashboard', 'local_ase_builder');

$PAGE->set_context($context);
$PAGE->set_url(new moodle_url('/local/ase_builder/ui/dashboard.php'));
$PAGE->set_title($pagetitle);
$PAGE->set_heading($pagetitle);

echo $OUTPUT->header();

echo html_writer::tag('h2', $pagetitle);

echo html_writer::tag('p', get_string('build_summary', 'local_ase_builder'));

$buildurl = new moodle_url('/local/ase_builder/ui/build_course.php');

echo html_writer::start_tag('form', ['method' => 'post', 'action' => $buildurl]);
echo html_writer::empty_tag('input', ['type' => 'hidden', 'name' => 'sesskey', 'value' => sesskey()]);
echo html_writer::empty_tag(
    'input', ['type' => 'submit', 'value' => get_string('build_now', 'local_ase_builder'),
    'class' => 'btn btn-primary']
);
echo html_writer::end_tag('form');

echo $OUTPUT->footer();
