<?php

declare(strict_types=1);

/*
 * Single configuration point for "Photo Drop".
 *
 * In the container the uploads directory is /var/www/storage (outside the
 * docroot). P2S_STORAGE exists only to run the application locally (php -S)
 * during development, without needing /var/www.
 */

function p2s_storage(): string
{
    $env = getenv('P2S_STORAGE');

    if (is_string($env) && $env !== '') {
        return rtrim($env, '/\\');
    }

    return '/var/www/storage';
}
