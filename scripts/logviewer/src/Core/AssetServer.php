<?php
declare(strict_types=1);

namespace LogViewer\Core;

final class AssetServer
{
    public function __construct(private readonly string $publicDir) {}

    public function serve(string $relPath): never
    {
        $base = realpath($this->publicDir);
        $full = realpath($this->publicDir . '/' . ltrim($relPath, '/'));

        if ($base === false || $full === false || !str_starts_with($full, $base) || !is_file($full)) {
            http_response_code(404);
            exit;
        }

        $ext = strtolower(pathinfo($full, PATHINFO_EXTENSION));
        $map = [
            'css'  => 'text/css; charset=utf-8',
            'js'   => 'application/javascript; charset=utf-8',
            'png'  => 'image/png',
            'jpg'  => 'image/jpeg',
            'jpeg' => 'image/jpeg',
            'svg'  => 'image/svg+xml',
            'ico'  => 'image/x-icon',
        ];

        $st = @stat($full) ?: null;
        $mtime = (int)($st['mtime'] ?? 0);
        $size  = (int)($st['size'] ?? 0);

        $etag = '"' . hash('sha256', $full . '|' . $mtime . '|' . $size) . '"';
        header('ETag: ' . $etag);

        if (isset($_SERVER['HTTP_IF_NONE_MATCH']) && trim((string)$_SERVER['HTTP_IF_NONE_MATCH']) === $etag) {
            http_response_code(304);
            exit;
        }

        Headers::common(true);
        header('Content-Type: ' . ($map[$ext] ?? 'application/octet-stream'));
        header('Cache-Control: public, max-age=3600');

        readfile($full);
        exit;
    }
}

