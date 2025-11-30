<?php

// File: tests/generatelabs_test.php

defined('MOODLE_INTERNAL') || die();

global $CFG;
require_once $CFG->dirroot . '/local/autocurriculum/lib.php';

class LocalAutocurriculumGeneratelabsTestcase extends advanced_testcase
{
    public function testGenerateLabs()
    {
        $this->resetAfterTest();

        // Mock course and sections.
        $course = $this->getDataGenerator()->create_course();
        $section = $this->getDataGenerator()->create_course_section(array('course' => $course->id));

        // Mock Ollama config.
        set_config('ollama_url', 'http://example.com', 'local_autocurriculum');
        set_config('default_model', 'testmodel', 'local_autocurriculum');

        // Mock the API call.
        $mockresponse = 'Mock generated lab content';
        // Note: In real test, use a mock for curl or the function.

        $result = local_autocurriculum_generate_labs($course->id, array($section->id));

        // Assert success or check DB.
        $this->assertGreaterThan(0, $result['success']);
    }

    public function testBulkGenerateLabs()
    {
        $this->resetAfterTest();

        $course1 = $this->getDataGenerator()->create_course();
        $course2 = $this->getDataGenerator()->create_course();

        set_config('ollama_url', 'http://example.com', 'local_autocurriculum');
        set_config('default_model', 'testmodel', 'local_autocurriculum');

        $result = local_autocurriculum_generate_labs_bulk(array($course1->id, $course2->id));

        $this->assertGreaterThan(0, $result['success']);
    }
}
