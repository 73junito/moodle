<?php
// File: lib.php

defined('MOODLE_INTERNAL') || die();

/**
 * Extend the course navigation to add "Generate Virtual Labs" link.
 *
 * Called by core when building the course navigation tree.
 *
 * @param navigation_node $navigation The course navigation node
 * @param stdClass        $course
 * @param context_course  $context
 */
function local_autocurriculum_extend_navigation_course(\navigation_node $navigation,
                                                       \stdClass $course,
                                                       \context_course $context) {
    global $CFG;

    // Only show to users who can generate labs.
    if (!has_capability('local/autocurriculum:generatelabs', $context)) {
        return;
    }

    // Build URL to the AutoCurriculum labs page.
    $url = new \moodle_url('/local/autocurriculum/labs.php', [
        'courseid' => $course->id,
    ]);

    // Choose where to attach: directly under course, or under "More".
    // Simplest: attach as a direct child of the course node.
    $node = \navigation_node::create(
        get_string('nav_generatelabs', 'local_autocurriculum'),
        $url,
        \navigation_node::TYPE_CUSTOM,
        null,
        'local_autocurriculum_generatelabs',
        new \pix_icon('i/settings', '')
    );

    $navigation->add_node($node);
}