<?php
// File: bulkgeneratelabs.php

require(__DIR__ . '/../../config.php');
require_once($CFG->libdir . '/formslib.php');

require_login();

$context = context_system::instance();
require_capability('local/autocurriculum:bulkgeneratelabs', $context);

$PAGE->set_url('/local/autocurriculum/bulkgeneratelabs.php');
$PAGE->set_context($context);
$PAGE->set_title(get_string('bulk_generatelabs', 'local_autocurriculum'));
$PAGE->set_heading(get_string('bulk_generatelabs', 'local_autocurriculum'));

class bulkgeneratelabs_form extends moodleform {
    public function definition() {
        $mform = $this->_form;

        // Get all courses the user can access.
        $courses = enrol_get_my_courses();
        $courseoptions = array();
        foreach ($courses as $course) {
            $courseoptions[$course->id] = $course->fullname;
        }

        $mform->addElement(
            'select',
            'courses',
            get_string('select_courses', 'local_autocurriculum'),
            $courseoptions,
            array('multiple' => true)
        );
        $mform->addRule('courses', get_string('required'), 'required', null, 'client');

        $mform->addElement(
            'textarea',
            'customprompt',
            get_string('custom_prompt', 'local_autocurriculum'),
            'rows="5" cols="50"'
        );
        $mform->setType('customprompt', PARAM_TEXT);

        $this->add_action_buttons(true, get_string('generate_bulk', 'local_autocurriculum'));
    }
}

$form = new bulkgeneratelabs_form();

if ($form->is_cancelled()) {
    redirect(new moodle_url('/my'));
} else if ($data = $form->get_data()) {
    $selectedcourses = $data->courses;
    $customprompt = $data->customprompt;

    $result = local_autocurriculum_generate_labs_bulk($selectedcourses, $customprompt);

    if ($result['success'] > 0) {
        $url = new moodle_url('/my');
        $message = get_string('bulk_generated_success', 'local_autocurriculum', $result['success']);
        redirect($url, $message, null, \core\output\notification::NOTIFY_SUCCESS);
    } else {
        $url = new moodle_url('/my');
        $message = get_string('bulk_generated_none', 'local_autocurriculum');
        redirect($url, $message, null, \core\output\notification::NOTIFY_WARNING);
    }
}

echo $OUTPUT->header();
echo $OUTPUT->heading(get_string('bulk_generatelabs', 'local_autocurriculum'));

$form->display();

echo $OUTPUT->footer();