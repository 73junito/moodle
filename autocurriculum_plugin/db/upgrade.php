<?php

// db/upgrade.php - Upgrade script for the AutoCurriculum local plugin.

defined('MOODLE_INTERNAL') || die();

require_once $CFG->libdir . '/db/upgradelib.php'; // Include upgradelib for upgrade functions.

/**
 * Upgrade code for the local_autocurriculum plugin.
 *
 * @param  int $oldversion The version we are upgrading from.
 * @return bool
 */
function xmldb_local_autocurriculum_upgrade($oldversion)
{
    global $DB;

    $dbman = $DB->get_manager();

    // Example upgrade step placeholder. Use real version numbers when making DB changes.
    if ($oldversion < 2025112700) {
        // Create the local_autocurriculum_labs table.
        $table = new xmldb_table('local_autocurriculum_labs');

        // Add fields.
        $table->add_field('id', XMLDB_TYPE_INTEGER, '10', null, XMLDB_NOTNULL, XMLDB_SEQUENCE, null);
        $table->add_field('courseid', XMLDB_TYPE_INTEGER, '10', null, XMLDB_NOTNULL, null, null);
        $table->add_field('sectionid', XMLDB_TYPE_INTEGER, '10', null, XMLDB_NOTNULL, null, null);
        $table->add_field('content', XMLDB_TYPE_TEXT, null, null, XMLDB_NOTNULL, null, null);
        $table->add_field('timecreated', XMLDB_TYPE_INTEGER, '10', null, XMLDB_NOTNULL, null, null);
        $table->add_field('timemodified', XMLDB_TYPE_INTEGER, '10', null, XMLDB_NOTNULL, null, null);

        // Add keys.
        $table->add_key('primary', XMLDB_KEY_PRIMARY, array('id'));
        $table->add_key('course_section', XMLDB_KEY_UNIQUE, array('courseid', 'sectionid'));

        // Create the table.
        if (!$dbman->table_exists($table)) {
            $dbman->create_table($table);
        }

        // Savepoint: mark upgrade as complete for this version.
        upgrade_plugin_savepoint(true, 2025112700, 'local', 'autocurriculum');
    }

    return true;
}
