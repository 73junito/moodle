<?php
// db/install.php - Installation hooks for the AutoCurriculum local plugin.

defined('MOODLE_INTERNAL') || die();

/**
 * Code run after the plugin is installed.
 */
function xmldb_local_autocurriculum_install()
{
    // Placeholder for post-install tasks (e.g., create default config, cron tasks).
    return true;
}

/**
 * Code run after the plugin is uninstalled.
 */
function xmldb_local_autocurriculum_uninstall()
{
    // Clean up any plugin-specific data if necessary.
    return true;
}
