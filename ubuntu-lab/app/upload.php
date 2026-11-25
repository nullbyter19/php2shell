<?php

declare(strict_types=1);

/*
 * Upload handler.
 *
 * Files are written OUTSIDE the docroot, with a random name and a forced ".bin"
 * extension. This is on purpose: the demo has to show exactly one vulnerability
 * (the engine's). If the upload landed in the docroot with the original name,
 * "uploading a .php" would be a second, unrelated bug, and the audience would be
 * right to point it out.
 */

require __DIR__ . '/config.php';

if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') {
    header('Location: /', true, 303);
    exit;
}

$storage = p2s_storage();

if (!is_dir($storage) && !mkdir($storage, 0775, true) && !is_dir($storage)) {
    http_response_code(500);
    header('Content-Type: text/plain');
    echo "storage unavailable\n";
    exit;
}

$count = 0;

foreach ($_FILES as $file) {
    if (!is_array($file) || !isset($file['error'], $file['tmp_name'])) {
        continue;
    }
    if ($file['error'] !== UPLOAD_ERR_OK) {
        continue;
    }
    if (!is_uploaded_file($file['tmp_name'])) {
        continue;
    }

    $name = bin2hex(random_bytes(8)) . '.bin';

    if (move_uploaded_file($file['tmp_name'], $storage . '/' . $name)) {
        $count++;
    }
}

header('Location: /?uploaded=' . $count, true, 303);
