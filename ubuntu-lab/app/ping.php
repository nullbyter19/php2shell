<?php

declare(strict_types=1);

/*
 * Lab instrumentation (not part of the application).
 *
 * It lets the demo prove two things on screen, without an exploit:
 *   1. the PHP version is 8.5.11 (the vulnerable one);
 *   2. two consecutive requests land in the SAME process (pid) — the condition
 *      that apache-lab.conf (1 worker) guarantees.
 *
 * Off by default (P2S_DEBUG != 1 returns 404), so it does not look like the
 * exploit depends on this file.
 */

if (getenv('P2S_DEBUG') !== '1') {
    http_response_code(404);
    exit;
}

$machine = php_uname('m');
$arch = match (strtolower($machine)) {
    'x86_64', 'amd64' => 'amd64',
    'aarch64', 'arm64' => 'aarch64',
    default           => strtolower($machine),
};

header('Content-Type: text/plain; charset=utf-8');
header('Cache-Control: no-store');

echo 'pid=' . getmypid() . "\n";
echo 'sapi=' . PHP_SAPI . "\n";
echo 'version=' . PHP_VERSION . "\n";
echo 'arch=' . $arch . "\n";
echo 'machine=' . $machine . "\n";
echo 'storage=' . (getenv('P2S_STORAGE') ?: '/var/www/storage') . "\n";
