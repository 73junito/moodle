<?php
// File: settings.php

defined('MOODLE_INTERNAL') || die();

if ($hassiteconfig) {
    $settings = new admin_settingpage('local_autocurriculum', get_string('pluginname', 'local_autocurriculum'));

    $settings->add(new admin_setting_configtext(
        'local_autocurriculum/ollama_url',
        get_string('ollama_url', 'local_autocurriculum'),
        get_string('ollama_url_desc', 'local_autocurriculum'),
        'http://localhost:11434',
        PARAM_URL
    ));

    $settings->add(new admin_setting_configtext(
        'local_autocurriculum/default_model',
        get_string('default_model', 'local_autocurriculum'),
        get_string('default_model_desc', 'local_autocurriculum'),
        'llama3',
        PARAM_ALPHANUMEXT
    ));

    $settings->add(new admin_setting_configcheckbox(
        'local_autocurriculum/auto_generate_labs',
        get_string('auto_generate_labs', 'local_autocurriculum'),
        get_string('auto_generate_labs_desc', 'local_autocurriculum'),
        0
    ));

    $ADMIN->add('localplugins', $settings);
}