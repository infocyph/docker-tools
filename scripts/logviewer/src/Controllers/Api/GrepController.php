<?php
declare(strict_types=1);

namespace LogViewer\Controllers\Api;

use LogViewer\Core\JsonResponse;
use LogViewer\Core\Request;
use LogViewer\Core\Response;
use LogViewer\Services\GrepRunner;
use LogViewer\Services\LogScanner;
use LogViewer\Services\RateLimiter;

final class GrepController
{
    public function __construct(
        private readonly LogScanner $scanner,
        private readonly GrepRunner $grep,
        private readonly RateLimiter $rl,
    ) {}

    public function handle(Request $r): Response
    {
        $file = $this->scanner->resolve($r->get('file'));
        $q = trim($r->get('q'));
        $limit = $r->int('limit', 500, 50, 5000);

        if ($q === '') return new JsonResponse(['ok' => false, 'error' => 'missing q'], 400);
        if (mb_strlen($q) > 200) return new JsonResponse(['ok' => false, 'error' => 'query too long'], 400);

        if (!$this->rl->allow('grep', $r->ip(), 12, 10)) {
            return new JsonResponse(['ok' => false, 'error' => 'rate limited'], 429);
        }

        [$code, $out, $err] = $this->grep->grep($file, $q, $limit);

        if ($code !== 0 && trim($err) !== '') {
            return new JsonResponse(['ok' => false, 'error' => trim($err)], 500);
        }

        $lines = preg_split("/\r\n|\n|\r/", $out) ?: [];
        $hits = [];
        foreach ($lines as $line) {
            if ($line === '') continue;
            // rg output: <line>:<match>
            if (preg_match('~^(\d+):(.*)$~', $line, $m)) {
                $hits[] = ['line' => (int)$m[1], 'text' => $m[2]];
            } else {
                $hits[] = ['line' => 0, 'text' => $line];
            }
        }

        return new JsonResponse([
            'ok' => true,
            'file' => $file,
            'q' => $q,
            'hits' => $hits,
            'count' => count($hits),
        ]);
    }
}

