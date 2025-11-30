<?php
require_once('../../config.php');
require_once('lib.php');

$id = required_param('id', PARAM_INT);

$cm = get_coursemodule_from_id('virtualgarage', $id, 0, false, MUST_EXIST);
$course = $DB->get_record('course', array('id' => $cm->course), '*', MUST_EXIST);
$virtualgarage = $DB->get_record('virtualgarage', array('id' => $cm->instance), '*', MUST_EXIST);

require_login($course, true, $cm);

$PAGE->set_url('/mod/virtualgarage/view.php', array('id' => $id));
$PAGE->set_title($course->shortname . ': ' . $virtualgarage->name);
$PAGE->set_heading($course->fullname);

echo $OUTPUT->header();

echo $OUTPUT->heading($virtualgarage->name);

if (!empty($virtualgarage->unityurl)) {
    echo '<iframe src="' . $virtualgarage->unityurl . '" width="100%" height="600"></iframe>';
}

if (!empty($virtualgarage->labcontent)) {
    echo '<div>' . $virtualgarage->labcontent . '</div>';
}

if (!empty($virtualgarage->questioncategory)) {
    // Display questions from the category.
    $questions = $DB->get_records('question', array('category' => $virtualgarage->questioncategory), 'id');
    if ($questions) {
        echo '<h3>' . get_string('questions', 'mod_virtualgarage') . '</h3>';
        echo '<ul>';
        foreach ($questions as $question) {
            echo '<li>' . $question->questiontext . '</li>';
        }
        echo '</ul>';
    }
}

echo $OUTPUT->footer();