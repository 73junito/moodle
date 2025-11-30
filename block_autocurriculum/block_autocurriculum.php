<?php
// File: block_autocurriculum.php

class block_autocurriculum extends block_base {

    public function init() {
        $this->title = get_string('pluginname', 'block_autocurriculum');
    }

    public function get_content() {
        global $DB, $USER, $OUTPUT;

        if ($this->content !== null) {
            return $this->content;
        }

        $this->content = new stdClass;
        $this->content->text = '';
        $this->content->footer = '';

        // Get courses where user has generatelabs capability.
        $courses = enrol_get_my_courses();
        $labscourses = array();
        foreach ($courses as $course) {
            $context = context_course::instance($course->id);
            if (has_capability('local/autocurriculum:generatelabs', $context)) {
                $labscourses[] = $course->id;
            }
        }

        if (empty($labscourses)) {
            $this->content->text = get_string('nocontent', 'block_autocurriculum');
            return $this->content;
        }

        // Get recent labs.
        list($insql, $inparams) = $DB->get_in_or_equal($labscourses);
        $sql = "SELECT l.*, c.fullname as coursename, cs.name as sectionname
                FROM {local_autocurriculum_labs} l
                JOIN {course} c ON l.courseid = c.id
                LEFT JOIN {course_sections} cs ON l.sectionid = cs.id
                WHERE l.courseid $insql
                ORDER BY l.timemodified DESC
                LIMIT 5";
        $labs = $DB->get_records_sql($sql, $inparams);

        if (empty($labs)) {
            $this->content->text = get_string('nocontent', 'block_autocurriculum');
            return $this->content;
        }

        $text = html_writer::tag('ul', '', array('class' => 'list'));
        foreach ($labs as $lab) {
            $sectionname = !empty($lab->sectionname) ? $lab->sectionname : get_string('section') . ' ' . $lab->sectionid;
            $link = html_writer::link(
                new moodle_url('/course/view.php', array('id' => $lab->courseid, 'section' => $lab->sectionid)),
                $lab->coursename . ' - ' . $sectionname
            );
            $text .= html_writer::tag('li', $link);
        }
        $text .= html_writer::end_tag('ul');

        $generatelink = html_writer::link(
            new moodle_url('/local/autocurriculum/bulkgeneratelabs.php'),
            get_string('bulk_generatelabs', 'local_autocurriculum')
        );
        $this->content->footer = $generatelink;

        $this->content->text = $text;
        return $this->content;
    }

    public function applicable_formats() {
        return array('my' => true, 'course' => true);
    }
}