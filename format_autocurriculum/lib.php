<?php
defined('MOODLE_INTERNAL') || die();

require_once($CFG->dirroot . '/course/format/lib.php');

class format_autocurriculum extends format_base {

    public function get_format_name() {
        return get_string('pluginname', 'format_autocurriculum');
    }

    public function uses_sections() {
        return true;
    }

    public function uses_indentation() {
        return true;
    }

    public function uses_course_index() {
        return true;
    }

    public function get_default_section_name() {
        return get_string('sectionname', 'format_autocurriculum');
    }

    public function get_view_url($section, $options = array()) {
        $course = $this->get_course();
        $url = new moodle_url('/course/view.php', array('id' => $course->id));
        if ($section !== null) {
            $url->param('section', $section);
        }
        return $url;
    }

    public function extend_course_navigation($navigation, navigation_node $node) {
        // Add navigation if needed.
    }

    public function get_section_name($section) {
        $course = $this->get_course();
        $sectioninfo = $this->get_modinfo()->get_section_info($section->section);
        if (!empty($sectioninfo->name)) {
            return $sectioninfo->name;
        }
        return $this->get_default_section_name() . ' ' . $section->section;
    }
}