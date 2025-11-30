<?php
defined('MOODLE_INTERNAL') || die();

if ($hassiteconfig) {
    $settings = new admin_settingpage('local_ase_builder', get_string('pluginname', 'local_ase_builder'));

    $settings->add(new admin_setting_heading(
        'local_ase_builder/heading',
        get_string('heading', 'local_ase_builder'),
        get_string('heading_desc', 'local_ase_builder')
    ));

    $settings->add(new admin_setting_configtext(
        'local_ase_builder/targetcategory',
        get_string('targetcategory', 'local_ase_builder'),
        get_string('targetcategory_desc', 'local_ase_builder'),
        'Automotive & Diesel Technology',
        PARAM_TEXT
    ));

    $settings->add(new admin_setting_configcheckbox(
        'local_ase_builder/autobuildoninstall',
        get_string('autobuildoninstall', 'local_ase_builder'),
        get_string('autobuildoninstall_desc', 'local_ase_builder'),
        1
    ));

    $ADMIN->add('localplugins', $settings);
}
