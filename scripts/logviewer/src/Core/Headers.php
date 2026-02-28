<?php
declare(strict_types=1);

namespace LogViewer\Core;

final class Headers
{
    public static function common(bool $isAsset = false): void
    {
        header('X-Content-Type-Options: nosniff');
        header('Referrer-Policy: same-origin');
        header('X-Frame-Options: SAMEORIGIN');
        header('Permissions-Policy: geolocation=(), microphone=(), camera=()');
        header('X-Robots-Tag: noindex, nofollow');

        if (!$isAsset) {
            header('Cache-Control: no-store');
        }
    }
}

