<?php
declare(strict_types=1);

namespace LogViewer\Controllers\Api;

use LogViewer\Core\Config;
use LogViewer\Core\JsonResponse;
use LogViewer\Core\Request;
use LogViewer\Core\Response;
use LogViewer\Services\EntriesService;
use LogViewer\Services\LogScanner;

final class EntriesController
{
    public function __construct(
        private readonly LogScanner $scanner,
        private readonly EntriesService $entries,
        private readonly Config $cfg,
    ) {}

    public function handle(Request $r): Response
    {
        $file = $this->scanner->resolve($r->get('file'));
        $page = max(1, $r->int('page', 1, 1, 1_000_000));
        $per = $r->int('per', 25, 10, 200);

        $level = strtolower(trim($r->get('level')));
        $q = trim($r->get('q'));
        $sinceMin = $r->int('since_minutes', 0, 0, 60*24*30);
        $sinceTs = $r->int('since_ts', 0, 0, 2147483647);

        $data = $this->entries->loadCached($file, $this->cfg->cacheTtl);
        $tFilter0 = hrtime(true);
        $entries = array_reverse((array)($data['entries'] ?? []));

        if ($level !== '' && in_array($level, ['debug','info','warn','error'], true)) {
            $entries = array_values(array_filter($entries, static function ($e) use ($level) {
                $l = strtolower((string)($e['level'] ?? 'info'));
                if ($l === 'warning') $l = 'warn';
                return $l === $level;
            }));
        }

        if ($q !== '') {
            $qq = mb_strtolower($q);
            $entries = array_values(array_filter($entries, static function ($e) use ($qq) {
                return str_contains(mb_strtolower((string)($e['summary'] ?? '')), $qq)
                    || str_contains(mb_strtolower((string)($e['body'] ?? '')), $qq);
            }));
        }

        
        // since filter (best-effort parse; entries without ts are kept)
        $cut = 0;
        if ($sinceTs > 0) $cut = $sinceTs;
        elseif ($sinceMin > 0) $cut = time() - ($sinceMin * 60);

        if ($cut > 0) {
            $entries = array_values(array_filter($entries, static function ($e) use ($cut) {
                $ts = (string)($e['ts'] ?? '');
                if ($ts === '') return true;
                $t = strtotime($ts);
                if ($t === false) return true;
                return $t >= $cut;
            }));
        }

$filterMs = (int)((hrtime(true)-$tFilter0)/1_000_000);
        if (isset($data['meta']) && is_array($data['meta'])) {
            $data['meta']['timing']['filter_ms'] = $filterMs;
        }

        $total = count($entries);
        $pages = max(1, (int)ceil($total / $per));
        $page = min($page, $pages);

        $slice = array_slice($entries, ($page - 1) * $per, $per);

        return new JsonResponse([
            'ok' => true,
            'meta' => $data['meta'] ?? [],
            'page' => $page,
            'per' => $per,
            'pages' => $pages,
            'total' => $total,
            'items' => $slice,
        ]);
    }
}

