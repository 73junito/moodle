<?php
// File: tests/format_test.php

defined('MOODLE_INTERNAL') || die();

global $CFG;
require_once($CFG->dirroot . '/course/format/autocurriculum/lib.php');

class format_autocurriculum_testcase extends advanced_testcase {

    public function test_format_name() {
        $this->resetAfterTest();

        $course = $this->getDataGenerator()->create_course();
        $format = course_get_format($course);

        $this->assertEquals('AutoCurriculum format', $format->get_format_name());
    }
}