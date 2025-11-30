<?php
defined('MOODLE_INTERNAL') || die();

/**
 * Installation hook for local_ase_builder.
 */
function xmldb_local_ase_builder_install()
{
    global $CFG;

    include_once $CFG->dirroot . '/local/ase_builder/classes/builder/course_builder.php';

    $config = get_config('local_ase_builder');
    $autobuild = isset($config->autobuildoninstall) ? (bool)$config->autobuildoninstall : true;

    if ($autobuild) {
        try {
            $builder = new \local_ase_builder\builder\course_builder();
            $builder->build_all_programs();
        } catch (\moodle_exception $e) {
            // Skip auto-build during upgrade if operations are not allowed.
            debugging('Auto-build skipped during upgrade: ' . $e->getMessage());
        }
    }

    return true;
}
