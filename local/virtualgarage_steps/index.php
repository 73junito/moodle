<?php
// File: index.php

require(__DIR__ . '/../../config.php');

require_login();

$context = context_system::instance();
require_capability('local/virtualgarage_steps:viewscenarios', $context);

$PAGE->set_url('/local/virtualgarage_steps/index.php');
$PAGE->set_context($context);
$PAGE->set_title(get_string('pluginname', 'local_virtualgarage_steps'));
$PAGE->set_heading(get_string('pluginname', 'local_virtualgarage_steps'));

echo $OUTPUT->header();
echo $OUTPUT->heading(get_string('pluginname', 'local_virtualgarage_steps'));

echo html_writer::tag('p', 'Manage and view virtual garage scenarios and steps.');

// Placeholder: List scenarios
global $DB;
$scenarios = $DB->get_records('virtualgarage_scenarios');
if ($scenarios) {
    echo html_writer::start_tag('ul');
    foreach ($scenarios as $scenario) {
        echo html_writer::tag('li', $scenario->title . ' (' . $scenario->scenarioid . ')');
    }
    echo html_writer::end_tag('ul');
} else {
    echo html_writer::tag('p', 'No scenarios found.');
}

echo $OUTPUT->footer();