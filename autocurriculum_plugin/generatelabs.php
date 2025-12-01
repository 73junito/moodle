<?php
// File: generatelabs.php

require(__DIR__ . '/../../config.php');
require_once($CFG->libdir . '/formslib.php');

require_login();

$courseid = required_param('courseid', PARAM_INT);
$course = $DB->get_record('course', array('id' => $courseid), '*', MUST_EXIST);
$context = context_course::instance($course->id);
require_capability('local/autocurriculum:generatelabs', $context);

$PAGE->set_url('/local/autocurriculum/generatelabs.php', array('courseid' => $courseid));
$PAGE->set_context($context);
$PAGE->set_title(get_string('generatelabs', 'local_autocurriculum'));
$PAGE->set_heading($course->fullname);

class generatelabs_form extends moodleform {
    public function definition() {
        $mform = $this->_form;

        $courseid = $this->_customdata['courseid'];

        // Get course sections.
        $sections = $DB->get_records('course_sections', array('course' => $courseid), 'section', 'id, section, name');
        $sectionoptions = array();
        foreach ($sections as $section) {
            $sectionname = !empty($section->name) ? $section->name : get_string('section') . ' ' . $section->section;
            $sectionoptions[$section->id] = $sectionname;
        }

        $mform->addElement(
            'select',
            'sections',
            get_string('select_sections', 'local_autocurriculum'),
            $sectionoptions,
            array('multiple' => true)
        );
        $mform->addRule('sections', get_string('required'), 'required', null, 'client');

        $mform->addElement(
            'textarea',
            'customprompt',
            get_string('custom_prompt', 'local_autocurriculum'),
            'rows="5" cols="50"'
        );
        $mform->setType('customprompt', PARAM_TEXT);

        $this->add_action_buttons(true, get_string('generate', 'local_autocurriculum'));
    }
}

$form = new generatelabs_form(null, array('courseid' => $courseid));

if ($form->is_cancelled()) {
    redirect(new moodle_url('/course/view.php', array('id' => $courseid)));
} else if ($data = $form->get_data()) {
    // Process form submission.
    $sections = $data->sections;
    $customprompt = $data->customprompt;

    $result = local_autocurriculum_generate_labs($courseid, $sections);

    if ($result['success'] > 0) {
        $url = new moodle_url('/course/view.php', array('id' => $courseid));
        $message = get_string('generatedlabs_success', 'local_autocurriculum', $result['success']);
        redirect($url, $message, null, \core\output\notification::NOTIFY_SUCCESS);
    } else {
        $url = new moodle_url('/course/view.php', array('id' => $courseid));
        $message = get_string('generatedlabs_none', 'local_autocurriculum');
        redirect($url, $message, null, \core\output\notification::NOTIFY_WARNING);
    }
}

echo $OUTPUT->header();
echo $OUTPUT->heading(get_string('generatelabs', 'local_autocurriculum'));

$form->display();

echo $OUTPUT->footer();