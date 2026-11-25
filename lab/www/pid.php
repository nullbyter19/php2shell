<?php
// Lab instrumentation only: confirms which worker served the request. The
// exploit never depends on this file; it exists to prove, during the talk, that
// producer and consumer ran in the same PID.
//
// Disabled by default (P2S_DEBUG=0) so it cannot be mistaken for a dependency.

if (getenv('P2S_DEBUG') !== '1') {
    http_response_code(404);
    exit;
}

header('Content-Type: text/plain');
echo 'pid=', getmypid(), "\n";
echo 'sapi=', PHP_SAPI, "\n";
echo 'version=', PHP_VERSION, "\n";
