<?php
// File: index.php

require(__DIR__ . '/../../config.php');

require_login();

$context = context_system::instance();
require_capability('moodle/site:config', $context);

$PAGE->set_url('/local/autocurriculum/index.php');
$PAGE->set_context($context);
$PAGE->set_title(get_string('pluginname', 'local_autocurriculum'));
$PAGE->set_heading(get_string('pluginname', 'local_autocurriculum'));

echo $OUTPUT->header();
echo $OUTPUT->heading(get_string('pluginname', 'local_autocurriculum'));

echo html_writer::tag('p', 'AutoCurriculum plugin for generating virtual labs.');

echo $OUTPUT->footer();