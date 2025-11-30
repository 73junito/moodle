<?php
defined('MOODLE_INTERNAL') || die();

$plugin->version   = 2025112700;
$plugin->requires  = 2020110900;
$plugin->component = 'format_autocurriculum';
$plugin->maturity  = MATURITY_STABLE;
$plugin->release   = '1.0';

$plugin->dependencies = array(
    'local_autocurriculum' => 2025112700,
);