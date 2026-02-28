<?php
declare(strict_types=1);

namespace LogViewer\Controllers\Api;

use LogViewer\Core\Request;
use LogViewer\Core\Response;
use LogViewer\Services\LogScanner;
use LogViewer\Services\TailReader;

final class DownloadController
{
    public function __construct(
        private readonly LogScanner $scanner,
        private readonly TailReader $tail,
    ) {}

    public function handle(Request $r): Response
    {
        $file = $this->scanner->resolve($r->get('file'));
        $lines = $r->int('lines', 2000, 50, 200000);

        [$code, $out, $err] = $this->tail->tailText($file, $lines);
        if ($code !== 0) {
            return new Response(500, trim($err) ?: 'read failed', 'text/plain; charset=utf-8');
        }

        $name = basename($file);
        http_response_code(200);
        header('Content-Type: text/plain; charset=utf-8');
        header('Content-Disposition: attachment; filename="' . addslashes($name) . '.tail.txt"');
        header('Cache-Control: no-store');
        echo $out;
        exit;
    }
}

