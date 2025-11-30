<?php
defined('MOODLE_INTERNAL') || die();

$capabilities = [
    'local/ase_builder:view' => [
        'captype'      => 'read',
        'contextlevel' => CONTEXT_SYSTEM,
        'archetypes'   => [
            'manager'        => CAP_ALLOW,
            'coursecreator'  => CAP_ALLOW,
        ]
    ],
    'local/ase_builder:build' => [
        'captype'      => 'write',
        'contextlevel' => CONTEXT_SYSTEM,
        'archetypes'   => [
            'manager'        => CAP_ALLOW,
        ]
    ],
];
