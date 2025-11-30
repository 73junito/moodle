<?php
// File: db/events.php

defined('MOODLE_INTERNAL') || die();

$observers = array(
    array(
        'eventname' => '\core\event\course_created',
        'callback' => 'local_autocurriculum_course_created',
        'includefile' => '/local/autocurriculum/lib.php',
    ),
);