<?php

define('MOODLE_TEST', true);

// File: tests/generatelabs_test.php

defined('MOODLE_INTERNAL') || die();

global $CFG;
require_once $CFG->dirroot . '/local/autocurriculum/lib.php';

class generatelabs_test extends advanced_testcase
{
    public function test_generate_labs()
    {
        $this->resetAfterTest();

        // Mock course and sections.
        $course = $this->getDataGenerator()->create_course();
        $section = $this->getDataGenerator()->create_course_section(array('course' => $course->id, 'section' => 1));

        // Mock Ollama config.
        set_config('ollima_url', 'http://example.com', 'local_autocurriculum');
        set_config('default_model', 'testmodel', 'local_autocurriculum');

        $result = local_autocurriculum_generate_labs($course->id, array($section->id));

        // Assert success or check DB.
        $this->assertGreaterThan(0, $result['success']);
    }

    public function test_bulk_generate_labs()
    {
        $this->resetAfterTest();

        $course1 = $this->getDataGenerator()->create_course();
        $course2 = $this->getDataGenerator()->create_course();
        $this->getDataGenerator()->create_course_section(array('course' => $course1->id, 'section' => 1));
        $this->getDataGenerator()->create_course_section(array('course' => $course2->id, 'section' => 1));

        set_config('ollima_url', 'http://example.com', 'local_autocurriculum');
        set_config('default_model', 'testmodel', 'local_autocurriculum');

        $result = local_autocurriculum_generate_labs_bulk(array($course1->id, $course2->id));

        $this->assertGreaterThan(0, $result['success']);
    }
}
