<?php
declare(strict_types=1);

namespace LogViewer\Controllers\Api;

use LogViewer\Core\Request;
use LogViewer\Services\LogScanner;
use LogViewer\Services\TailReader;

final class TailController
{
    public function __construct(
        private readonly LogScanner $scanner,
        private readonly TailReader $tail,
    ) {}

    public function handle(Request $r): never
    {
        $file = $this->scanner->resolve($r->get('file'));
        $lines = $r->int('lines', 300, 50, 5000);
        $intervalMs = $r->int('intervalMs', 900, 250, 3000);

        if ($this->tail->isGz($file)) {
            http_response_code(400);
            header('Content-Type: text/event-stream; charset=utf-8');
            header('Cache-Control: no-store');
            header('X-Accel-Buffering: no');
            echo "event: error\n";
            echo "data: " . json_encode(['ok' => false, 'error' => 'live not supported for .gz logs']) . "\n\n";
            exit;
        }

        @set_time_limit(0);
        @ini_set('output_buffering', 'off');
        @ini_set('zlib.output_compression', '0');

        header('Content-Type: text/event-stream; charset=utf-8');
        header('Cache-Control: no-store');
        header('X-Accel-Buffering: no');

        $lastSig = '';
        $maxIterations = 60 * 60; // ~1 hour if client stays
        for ($i=0; $i<$maxIterations; $i++) {
            if (connection_aborted()) break;

            clearstatcache(true, $file);
            $st = @stat($file) ?: null;
            $mtime = (int)($st['mtime'] ?? 0);
            $size = (int)($st['size'] ?? 0);
            $sig = $mtime . ':' . $size;

            if ($sig !== $lastSig) {
                $lastSig = $sig;
                [$code, $out, $err] = $this->tail->tailText($file, $lines);
                if ($code !== 0) {
                    echo "event: error\n";
                    echo "data: " . json_encode(['ok'=>false,'error'=>trim($err)?:'read failed']) . "\n\n";
                    @ob_flush(); @flush();
                    usleep($intervalMs * 1000);
                    continue;
                }

                $hash = hash('sha256', $out);
                echo "event: tail\n";
                echo "data: " . json_encode(['ok'=>true,'hash'=>$hash,'text'=>$out,'ts'=>$mtime], JSON_UNESCAPED_SLASHES|JSON_UNESCAPED_UNICODE) . "\n\n";
                @ob_flush(); @flush();
            }

            usleep($intervalMs * 1000);
        }

        exit;
    }
}

