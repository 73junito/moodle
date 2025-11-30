<?php

define('CLI_SCRIPT', true);

require_once __DIR__ . '/../../../config.php';
require_once $CFG->libdir . '/clilib.php';
require_once $CFG->dirroot . '/local/autocurriculum/lib.php';

// Get CLI options.
$longoptions = array(
    'courses' => '',
    'help' => false,
);

$options = cli_get_options($longoptions);

if ($options['help'] || empty($options['courses'])) {
    echo "Bulk generate labs for courses.\n";
    echo "Usage: php bulk_generate.php --courses=1,2,3\n";
    exit(0);
}

$courses = explode(',', $options['courses']);
$result = local_autocurriculum_generate_labs_bulk($courses);

echo "Generated labs for {$result['success']} sections.\n";
if (!empty($result['messages'])) {
    echo implode("\n", $result['messages']) . "\n";
}
