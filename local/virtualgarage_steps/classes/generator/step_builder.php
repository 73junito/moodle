<?php
// File: classes/generator/step_builder.php

namespace local_virtualgarage_steps\generator;

defined('MOODLE_INTERNAL') || die();

class step_builder {

    /**
     * Build and save steps for a scenario.
     *
     * @param string $scenarioid
     * @param array $steps Array of step data
     */
    public static function build_steps($scenarioid, $steps) {
        global $DB;

        foreach ($steps as $step) {
            $record = (object)[
                'scenarioid'  => $scenarioid,
                'stepid'      => $step['id'],
                'description' => $step['description'],
                'weight'      => $step['weight'] ?? 0,
                'required'    => $step['required'] ?? 1,
            ];

            $DB->insert_record('virtualgarage_steps', $record);
        }
    }
}