<?php

declare(strict_types=1);

/*
 * Photo Drop — the "target" of the PHP2Shell demo.
 *
 * This file has no vulnerability at all: no eval(), no include($user), no
 * shell_exec, no unserialize, no session_start(). The bug being demonstrated
 * lives in the PHP engine (CVE-2026-109618 / CVE-2026-109619) and reaches the
 * vulnerable code before this script is compiled.
 */

require __DIR__ . '/config.php';

$storage = p2s_storage();

$files = [];
foreach (glob($storage . '/*') ?: [] as $path) {
    if (is_file($path)) {
        $files[] = [
            'name'  => basename($path),
            'size'  => (int) filesize($path),
            'mtime' => (int) filemtime($path),
        ];
    }
}
usort($files, static fn (array $a, array $b): int => $b['mtime'] <=> $a['mtime']);

$uploaded = isset($_GET['uploaded']) ? max(0, (int) $_GET['uploaded']) : null;

?>
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Photo Drop</title>
<link rel="stylesheet" href="/assets/app.css">
</head>
<body>
<main>
    <header>
        <h1>Photo Drop</h1>
        <p class="tag">Share a photo with the room. No account, no sign-up.</p>
    </header>

    <?php if ($uploaded !== null): ?>
        <p class="flash"><?= $uploaded ?> file(s) received.</p>
    <?php endif; ?>

    <form action="/upload.php" method="post" enctype="multipart/form-data">
        <label for="photo">Choose a photo</label>
        <input id="photo" type="file" name="photo" accept="image/*" required>
        <button type="submit">Upload</button>
    </form>

    <h2>Latest uploads</h2>

    <?php if ($files === []): ?>
        <p class="empty">Nothing here yet.</p>
    <?php else: ?>
        <ul class="list">
            <?php foreach (array_slice($files, 0, 6) as $file): ?>
                <li>
                    <a href="/download.php?f=<?= urlencode($file['name']) ?>">
                        <?= htmlspecialchars($file['name'], ENT_QUOTES) ?>
                    </a>
                    <span><?= number_format($file['size'] / 1024, 1) ?> KB</span>
                </li>
            <?php endforeach; ?>
        </ul>
    <?php endif; ?>

    <footer>
        <span>PHP <?= htmlspecialchars(PHP_VERSION, ENT_QUOTES) ?></span>
        <span><?= htmlspecialchars(PHP_SAPI, ENT_QUOTES) ?></span>
    </footer>
</main>
</body>
</html>
