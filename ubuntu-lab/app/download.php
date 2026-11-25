<?php

declare(strict_types=1);

/*
 * Serves a file from storage. basename() + is_file() keep the path inside the
 * directory: there is no traversal here.
 */

require __DIR__ . '/config.php';

$requested = (string) ($_GET['f'] ?? '');
$path = p2s_storage() . '/' . basename($requested);

if ($requested === '' || !is_file($path)) {
    http_response_code(404);
    header('Content-Type: text/plain');
    echo "not found\n";
    exit;
}

header('Content-Type: application/octet-stream');
header('Content-Length: ' . (string) filesize($path));
header('Content-Disposition: attachment; filename="' . basename($path) . '"');

readfile($path);
