<?php
defined('MOODLE_INTERNAL') || die();

$plugin->version   = 2025112700;        // The current plugin version (YYYYMMDDXX).
$plugin->requires  = 2020110900;        // Requires this Moodle version (example: 3.9+).
$plugin->component = 'block_autocurriculum'; // Full name of the plugin (type_name).
$plugin->maturity  = MATURITY_STABLE;
$plugin->release   = '1.0';

$plugin->dependencies = array(
    'local_autocurriculum' => 2025112700,
);