<?php
// File: db/access.php

defined('MOODLE_INTERNAL') || die();

$capabilities = array(

    'local/autocurriculum:generatelabs' => array(
        'captype' => 'write',
        'contextlevel' => CONTEXT_COURSE,
        'archetypes' => array(
            'editingteacher' => CAP_ALLOW,
            'manager' => CAP_ALLOW,
        ),
        'clonepermissionsfrom' => 'moodle/course:update',
    ),

    'local/autocurriculum:bulkgeneratelabs' => array(
        'captype' => 'write',
        'contextlevel' => CONTEXT_SYSTEM,
        'archetypes' => array(
            'manager' => CAP_ALLOW,
        ),
        'clonepermissionsfrom' => 'moodle/site:config',
    ),

);