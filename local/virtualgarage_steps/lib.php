<?php
// File: lib.php

defined('MOODLE_INTERNAL') || die();

/**
 * Load a scenario by ID.
 *
 * @param string $scenarioid
 * @return stdClass|null Scenario record
 */
function local_virtualgarage_steps_load_scenario($scenarioid) {
    global $DB;
    return $DB->get_record('virtualgarage_scenarios', ['scenarioid' => $scenarioid]);
}

/**
 * Validate a step completion.
 *
 * @param string $scenarioid
 * @param string $stepid
 * @param mixed $user_action
 * @return bool True if valid
 */
function local_virtualgarage_steps_validate_step($scenarioid, $stepid, $user_action) {
    // Placeholder: Implement logic to check if the step is valid based on rules
    // For example, check prerequisites, action correctness, etc.
    return true; // Stub
}

/**
 * Calculate total score for a scenario.
 *
 * @param string $scenarioid
 * @param array $completed_steps Array of completed step IDs
 * @return int Total score
 */
function local_virtualgarage_steps_calculate_score($scenarioid, $completed_steps) {
    global $DB;

    $steps = $DB->get_records('virtualgarage_steps', ['scenarioid' => $scenarioid]);
    $score = 0;

    foreach ($steps as $step) {
        if (in_array($step->stepid, $completed_steps)) {
            $score += $step->weight;
        }
    }

    return $score;
}