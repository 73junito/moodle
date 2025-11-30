<?php
// Admin-only: reset PHP OPcache if available. Visit this URL as site admin.
require_once(__DIR__ . '/../../../config.php');
require_login();
if (!is_siteadmin()) {
    http_response_code(403);
    echo 'Access denied: site admin only.';
    exit;
}

echo '<pre>';
if (function_exists('opcache_reset')) {
    $ok = @opcache_reset();
    echo 'opcache_reset() available. Result: ' . ($ok ? 'OK' : 'FAILED') . "\n";
} else {
    echo 'opcache_reset() not available on this PHP build.' . "\n";
}
echo "If opcache_reset is not available, please restart your web server (Apache/IIS) to clear PHP opcode cache.\n";
echo '</pre>';
