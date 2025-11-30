<?php
// File: classes/api/scenario_manager.php

namespace local_virtualgarage_steps\api;

defined('MOODLE_INTERNAL') || die();

class scenario_manager {

    /**
     * Load a scenario by ID.
     *
     * @param string $scenarioid
     * @return \stdClass|null
     */
    public static function load_scenario($scenarioid) {
        global $DB;
        return $DB->get_record('virtualgarage_scenarios', ['scenarioid' => $scenarioid]);
    }

    /**
     * Save a new scenario.
     *
     * @param string $scenarioid
     * @param string $title
     * @param string $json
     * @return int New record ID
     */
    public static function save_scenario($scenarioid, $title, $json) {
        global $DB;

        $record = (object)[
            'scenarioid'  => $scenarioid,
            'title'       => $title,
            'json'        => $json,
            'timecreated' => time(),
        ];

        return $DB->insert_record('virtualgarage_scenarios', $record);
    }
}