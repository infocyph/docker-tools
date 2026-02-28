<?php
declare(strict_types=1);

namespace LogViewer\Controllers\Api;

use LogViewer\Core\Request;
use LogViewer\Services\EntriesService;
use LogViewer\Services\LogScanner;
use LogViewer\Services\StreamService;

final class ExportController
{
    public function __construct(
        private readonly LogScanner $scanner,
        private readonly EntriesService $entries,
        private readonly StreamService $stream,
    ) {}

    public function handle(Request $r): never
    {
        $file = trim($r->get('file'));
        $service = trim($r->get('service'));

        $sinceMin = $r->int('since_minutes', 0, 0, 60*24*30);
        $limit = $r->int('limit', 500, 50, 5000);

        $meta = [];
        $items = [];

        if ($file !== '') {
            $path = $this->scanner->resolve($file);
            $payload = $this->entries->loadCached($path, 2);
            $items = array_reverse((array)($payload['entries'] ?? []));
            $meta = (array)($payload['meta'] ?? []);
            $meta['display_path'] = $this->scanner->displayPath($path);
            $meta['export_kind'] = 'file';
        } elseif ($service !== '') {
            $payload = $this->stream->stream($service, $limit, $sinceMin);
            $items = (array)($payload['items'] ?? []);
            $meta = (array)($payload['meta'] ?? []);
            $meta['export_kind'] = 'service_stream';
        } else {
            http_response_code(400);
            header('Content-Type: text/plain; charset=utf-8');
            echo "missing file or service";
            exit;
        }

        // Apply since filter on export too (best-effort)
        if ($sinceMin > 0) {
            $cut = time() - ($sinceMin * 60);
            $items = array_values(array_filter($items, static function ($e) use ($cut) {
                $ts = (string)($e['ts'] ?? '');
                if ($ts === '') return true;
                $t = strtotime($ts);
                if ($t === false) return true;
                return $t >= $cut;
            }));
        }

        // Create text export
        $txt = '';
        foreach ($items as $e) {
            $src = '';
            if (isset($e['source']) && is_array($e['source'])) {
                $src = '[' . ($e['source']['display_path'] ?? $e['source']['path'] ?? '') . '] ';
            }
            $txt .= $src;
            if (!empty($e['ts'])) $txt .= $e['ts'] . ' ';
            $txt .= strtoupper((string)($e['level'] ?? 'info')) . ' ';
            $txt .= (string)($e['summary'] ?? '') . "\n";
            $b = trim((string)($e['body'] ?? ''));
            if ($b !== '') $txt .= $b . "\n";
            $txt .= str_repeat('-', 80) . "\n";
        }

        $stamp = date('Ymd_His');
        $base = ($file !== '') ? basename($file) : ('service_' . preg_replace('~[^a-zA-Z0-9_-]+~', '_', $service));
        $zipName = 'logviewer_export_' . $base . '_' . $stamp . '.zip';

        $tmp = tempnam(sys_get_temp_dir(), 'lvexp_');
        if ($tmp === false) {
            http_response_code(500);
            header('Content-Type: text/plain; charset=utf-8');
            echo "tempnam failed";
            exit;
        }
        $zipPath = $tmp . '.zip';

        $z = new \ZipArchive();
        if ($z->open($zipPath, \ZipArchive::CREATE | \ZipArchive::OVERWRITE) !== true) {
            http_response_code(500);
            header('Content-Type: text/plain; charset=utf-8');
            echo "zip open failed";
            exit;
        }

        $z->addFromString('metadata.json', json_encode($meta, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE));
        $z->addFromString('entries.json', json_encode($items, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE));
        $z->addFromString('entries.txt', $txt);
        $z->close();

        http_response_code(200);
        header('Content-Type: application/zip');
        header('Content-Disposition: attachment; filename="' . addslashes($zipName) . '"');
        header('Cache-Control: no-store');

        readfile($zipPath);
        @unlink($zipPath);
        @unlink($tmp);
        exit;
    }
}
