<?php
// Admin-only utility to probe Ghostscript from the webserver context.
// Place under local/autocurriculum/admin and visit as a site admin.

require_once __DIR__ . '/../../../config.php';
require_login();
if (!is_siteadmin()) {
    http_response_code(403);
    echo 'Access denied: site admin only.';
    exit;
}

echo '<pre>';
echo "Configured \$CFG->pathtoghostscript\n\n";
$path = isset($CFG->pathtoghostscript) ? $CFG->pathtoghostscript : '';
echo 'Configured path: ' . ($path ? htmlspecialchars($path) : '(not set)') . "\n\n";

if ($path) {
    echo 'file_exists: ' . (file_exists($path) ? 'yes' : 'no') . "\n";
    echo 'is_executable: ' . (is_executable($path) ? 'yes' : 'no') . "\n\n";

    $cmd = escapeshellcmd($path) . ' -version 2>&1';
    echo "Running: $cmd\n\n";
    $out = array();
    $ret = 0;
    @exec($cmd, $out, $ret);
    echo "Return code: $ret\n";
    echo "Output:\n";
    echo implode("\n", $out);
    echo "\n\n";
} else {
    echo "No configured Ghostscript path to test.\n\n";
}

echo "Trying generic 'gs -version' from PATH (if available):\n";
$out2 = array();
$ret2 = 0;
@exec('gs -version 2>&1', $out2, $ret2);
echo "Return code: $ret2\n";
echo implode("\n", $out2);
echo '</pre>';

// End of file
