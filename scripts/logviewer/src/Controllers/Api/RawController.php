<?php
declare(strict_types=1);

namespace LogViewer\Controllers\Api;

use LogViewer\Core\Config;
use LogViewer\Core\Headers;
use LogViewer\Core\Request;
use LogViewer\Core\Response;
use LogViewer\Services\LogScanner;
use LogViewer\Services\TailReader;

final class RawController
{
    public function __construct(
        private readonly LogScanner $scanner,
        private readonly TailReader $tail,
        private readonly Config $cfg,
    ) {}

    public function handle(Request $r): Response
    {
        $file = $this->scanner->resolve($r->get('file'));
        $lines = $r->int('lines', 2000, 100, 50000);
        $maxBytes = $r->int('maxBytes', $this->cfg->rawDefaultMaxBytes, 1024*1024, 128*1024*1024);

        [$code, $out, $err] = $this->tail->tailText($file, $lines);
        if ($code !== 0) {
            return new Response(500, trim($err) ?: 'read failed', 'text/plain; charset=utf-8');
        }

        if (strlen($out) > $maxBytes) $out = substr($out, -$maxBytes);

        // Raw response: override common headers rules a bit
        http_response_code(200);
        Headers::common(false);
        header('Content-Type: text/plain; charset=utf-8');
        header('Cache-Control: no-store');
        header('X-Content-Type-Options: nosniff');
        $st = @stat($file);
        header('X-Log-File-Size: ' . (int)($st['size'] ?? 0));

        echo $out;
        exit;
    }
}
