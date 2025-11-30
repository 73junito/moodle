<?php
// File: mod/virtualgarage/lib.php

defined('MOODLE_INTERNAL') || die();

/**
 * List of features supported by Virtual Garage module.
 */
function virtualgarage_supports($feature) {
    switch ($feature) {
        case FEATURE_MOD_INTRO:
            return true;
        case FEATURE_COMPLETION_TRACKS_VIEWS:
            return true;
        case FEATURE_GRADE_HAS_GRADE:
            return true;
        case FEATURE_BACKUP_MOODLE2:
            return true;
        default:
            return null;
    }
}

/**
 * Add a new virtualgarage instance.
 *
 * @param stdClass $data
 * @param mod_virtualgarage_mod_form $mform
 * @return int new instance ID
 */
function virtualgarage_add_instance(stdClass $data, mod_virtualgarage_mod_form $mform = null) {
    global $DB;

    $data->timecreated = time();
    $data->timemodified = $data->timecreated;

    // Ensure numeric fields are sane.
    $data->maxgrade     = isset($data->maxgrade) ? (float)$data->maxgrade : 100.0;
    $data->passinggrade = isset($data->passinggrade) ? (float)$data->passinggrade : 70.0;
    $data->attemptlimit = isset($data->attemptlimit) ? (int)$data->attemptlimit : 0;

    $id = $DB->insert_record('virtualgarage', $data);

    // Create grade item.
    $data->id = $id;
    virtualgarage_grade_item_update($data);

    return $id;
}

/**
 * Update an existing virtualgarage instance.
 *
 * @param stdClass $data
 * @param mod_virtualgarage_mod_form $mform
 * @return bool
 */
function virtualgarage_update_instance(stdClass $data, mod_virtualgarage_mod_form $mform = null) {
    global $DB;

    $data->id = $data->instance;
    $data->timemodified = time();

    $data->maxgrade     = isset($data->maxgrade) ? (float)$data->maxgrade : 100.0;
    $data->passinggrade = isset($data->passinggrade) ? (float)$data->passinggrade : 70.0;
    $data->attemptlimit = isset($data->attemptlimit) ? (int)$data->attemptlimit : 0;

    $DB->update_record('virtualgarage', $data);

    virtualgarage_grade_item_update($data);

    return true;
}

/**
 * Delete a virtualgarage instance.
 *
 * @param int $id
 * @return bool
 */
function virtualgarage_delete_instance($id) {
    global $DB;

    if (!$record = $DB->get_record('virtualgarage', ['id' => $id])) {
        return false;
    }

    // Delete attempts.
    $DB->delete_records('virtualgarage_attempts', ['cmid' => $record->id]);

    // Delete main record.
    $DB->delete_records('virtualgarage', ['id' => $id]);

    // Remove grade items.
    virtualgarage_grade_item_update($record, 'delete');

    return true;
}

/**
 * Create/update grade item for a virtualgarage instance.
 *
 * @param stdClass $virtualgarage
 * @param string $action 'update' or 'delete'
 * @return int
 */
function virtualgarage_grade_item_update(stdClass $virtualgarage, string $action = 'update') {
    global $CFG;
    require_once($CFG->libdir . '/gradelib.php');

    $params = [
        'itemname' => clean_param($virtualgarage->name ?? get_string('pluginname', 'virtualgarage'), PARAM_NOTAGS),
        'gradetype' => GRADE_TYPE_VALUE,
    ];

    if ($action === 'delete') {
        return grade_update('mod/virtualgarage', $virtualgarage->course, 'mod',
            'virtualgarage', $virtualgarage->id, 0, null, ['deleted' => 1]);
    }

    $maxgrade = isset($virtualgarage->maxgrade) ? (float)$virtualgarage->maxgrade : 100.0;
    $params['grademax'] = $maxgrade;
    $params['grademin'] = 0;

    return grade_update('mod/virtualgarage', $virtualgarage->course, 'mod',
        'virtualgarage', $virtualgarage->id, 0, null, $params);
}

/**
 * Update grades for a Virtual Garage activity.
 *
 * @param stdClass $virtualgarage
 * @param int|null $userid
 */
function virtualgarage_update_grades(stdClass $virtualgarage, $userid = 0) {
    global $DB, $CFG;
    require_once($CFG->libdir . '/gradelib.php');

    $grades = [];

    // If a specific user is requested, filter by userid.
    $params = ['courseid' => $virtualgarage->course];
    if ($userid) {
        $params['userid'] = $userid;
    }

    // Example: derive final grade as highest score attempt scaled to maxgrade.
    $sql = "SELECT userid, MAX(score) AS bestscore
              FROM {virtualgarage_attempts}
             WHERE courseid = :courseid" . ($userid ? " AND userid = :userid" : "") . "
          GROUP BY userid";

    $records = $DB->get_records_sql($sql, $params);

    $maxgrade = isset($virtualgarage->maxgrade) ? (float)$virtualgarage->maxgrade : 100.0;

    foreach ($records as $r) {
        $gradevalue = $r->bestscore; // Already 0–maxscore from Unity; you can rescale if needed.
        // If your attempts use a different maxscore, you could normalize here.

        $grades[$r->userid] = (object)[
            'userid' => $r->userid,
            'rawgrade' => $gradevalue,
        ];
    }

    grade_update('mod/virtualgarage', $virtualgarage->course, 'mod',
        'virtualgarage', $virtualgarage->id, 0, $grades);
}

/**
 * Save a single grade (used by external WS when Unity posts result).
 *
 * @param stdClass $cm
 * @param int $userid
 * @param float $grade raw grade (0–100 or scaled)
 */
function virtualgarage_save_grade(stdClass $cm, int $userid, float $grade): void {
    global $DB, $CFG;
    require_once($CFG->libdir . '/gradelib.php');

    $virtualgarage = $DB->get_record('virtualgarage', ['id' => $cm->instance], '*', MUST_EXIST);
    $maxgrade = isset($virtualgarage->maxgrade) ? (float)$virtualgarage->maxgrade : 100.0;

    // Clamp grade.
    $grade = max(0, min($grade, $maxgrade));

    $grades = [
        $userid => (object)[
            'userid'   => $userid,
            'rawgrade' => $grade,
        ],
    ];

    grade_update('mod/virtualgarage', $virtualgarage->course, 'mod',
        'virtualgarage', $virtualgarage->id, 0, $grades);
}