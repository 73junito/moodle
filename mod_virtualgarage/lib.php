<?php

defined('MOODLE_INTERNAL') || die();

function virtualgarage_add_instance($data)
{

    global $DB;
    $data->timemodified = time();
    $data->id = $DB->insert_record('virtualgarage', $data);
    return $data->id;
}

function virtualgarage_update_instance($data)
{

    global $DB;
    $data->timemodified = time();
    $data->id = $data->instance;
    $DB->update_record('virtualgarage', $data);
    return true;
}

function virtualgarage_delete_instance($id)
{

    global $DB;
    if (!$virtualgarage = $DB->get_record('virtualgarage', array('id' => $id))) {
        return false;
    }

    $DB->delete_records('virtualgarage', array('id' => $id));
    return true;
}

function virtualgarage_get_completion_state($course, $cm, $userid, $type)
{

    global $DB;
    if ($type == COMPLETION_COMPLETE || $type == COMPLETION_INCOMPLETE) {
        // Simple completion: mark as complete if viewed.
        $completion = $DB->get_record('course_modules_completion', array('coursemoduleid' => $cm->id, 'userid' => $userid));
        return $completion ? COMPLETION_COMPLETE : COMPLETION_INCOMPLETE;
    }

    return COMPLETION_UNKNOWN;
}
