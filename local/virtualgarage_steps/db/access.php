<?php
// File: db/access.php

defined('MOODLE_INTERNAL') || die();

$capabilities = $capabilities ?? [];

// Capabilities for managing scenarios and steps
$capabilities['local/virtualgarage_steps:managescenarios'] = [
    'captype'      => 'write',
    'contextlevel' => CONTEXT_SYSTEM,
    'archetypes'   => [
        'manager' => CAP_ALLOW,
    ],
];

$capabilities['local/virtualgarage_steps:viewscenarios'] = [
    'captype'      => 'read',
    'contextlevel' => CONTEXT_SYSTEM,
    'archetypes'   => [
        'teacher' => CAP_ALLOW,
        'manager' => CAP_ALLOW,
    ],
];