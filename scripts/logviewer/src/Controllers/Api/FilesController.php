<?php
declare(strict_types=1);

namespace LogViewer\Controllers\Api;

use LogViewer\Core\JsonResponse;
use LogViewer\Core\Request;
use LogViewer\Core\Response;
use LogViewer\Services\LogScanner;

final class FilesController
{
    public function __construct(private readonly LogScanner $scanner) {}

    public function handle(Request $r): Response
    {
        $svc = trim($r->get('service'));
        $q = trim($r->get('q'));

        $files = $this->scanner->listFiles();

        if ($svc !== '') {
            $svcLower = strtolower($svc);
            $files = array_values(array_filter($files, static function ($f) use ($svcLower) {
                $s = strtolower((string)($f['service'] ?? ''));
                return $s === $svcLower;
            }));
        }

        if ($q !== '') {
            $qLower = strtolower($q);
            $files = array_values(array_filter($files, static function ($f) use ($qLower) {
                $name = strtolower((string)($f['name'] ?? ''));
                $path = strtolower((string)($f['path'] ?? ''));
                $svc = strtolower((string)($f['service'] ?? ''));
                return str_contains($name, $qLower) || str_contains($path, $qLower) || str_contains($svc, $qLower);
            }));
        }

        $services = [];
        foreach ($this->scanner->listServices() as $svc) {
            if ($svc !== '') $services[$svc] = true;
        }
        $serviceList = array_keys($services);
        sort($serviceList, SORT_NATURAL | SORT_FLAG_CASE);

        return new JsonResponse([
            'ok' => true,
            'services' => $serviceList,
            'files' => $files,
        ]);
    }
}
