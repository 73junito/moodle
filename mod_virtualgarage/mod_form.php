<?php

defined('MOODLE_INTERNAL') || die();
require_once($CFG->dirroot . '/course/moodleform_mod.php');

class mod_virtualgarage_mod_form extends moodleform_mod
{
    public function definition()
    {
        $mform = $this->_form;
        $mform->addElement(
            'text',
            'name',
            get_string('name'),
            array('size' => '64')
        );
        $mform->setType('name', PARAM_TEXT);
        $mform->addRule('name', null, 'required', null, 'client');
        $mform->addElement(
            'url',
            'unityurl',
            get_string('unityurl', 'mod_virtualgarage'),
            array('size' => '64')
        );
        $mform->setType('unityurl', PARAM_URL);
        $mform->addElement(
            'textarea',
            'labcontent',
            get_string('labcontent', 'mod_virtualgarage'),
            'rows="10" cols="50"'
        );
        $mform->setType('labcontent', PARAM_TEXT);
// Question bank category.
        $categories = $DB->get_records_menu('question_categories', null, 'name', 'id,name');
        $mform->addElement(
            'select',
            'questioncategory',
            get_string('questioncategory', 'mod_virtualgarage'),
            $categories
        );
        $mform->setType('questioncategory', PARAM_INT);
        $this->standard_coursemodule_elements();
        $this->add_action_buttons();
    }
}
