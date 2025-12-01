<?php
// File: tests/block_test.php

defined('MOODLE_INTERNAL') || die();

global $CFG;
require_once($CFG->dirroot . '/blocks/autocurriculum/block_autocurriculum.php');

class block_autocurriculum_testcase extends advanced_testcase {

    public function test_block_content() {
        $this->resetAfterTest();

        $block = new block_autocurriculum();
        $content = $block->get_content();

        $this->assertNotEmpty($content->text);
    }
}