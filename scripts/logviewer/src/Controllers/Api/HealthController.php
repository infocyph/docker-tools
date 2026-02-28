<?php
declare(strict_types=1);

namespace LogViewer\Controllers\Api;

use LogViewer\Core\JsonResponse;
use LogViewer\Core\Request;
use LogViewer\Core\Response;

final class HealthController
{
    public function handle(Request $r): Response
    {
        $tools = [
            'find' => $this->hasCmd('find'),
            'rg'   => $this->hasCmd('rg'),
            'gzip' => $this->hasCmd('gzip'),
        ];

        $tmpOk = $this->tmpWritable('/tmp');
        $ok = $tmpOk && !in_array(false, $tools, true);

        return new JsonResponse([
            'ok' => $ok,
            'tools' => $tools,
            'tmp_writable' => $tmpOk,
        ], $ok ? 200 : 200);
    }

    private function hasCmd(string $cmd): bool
    {
        $p = trim((string)shell_exec('command -v ' . escapeshellarg($cmd) . ' 2>/dev/null'));
        return $p !== '';
    }

    private function tmpWritable(string $dir): bool
    {
        $dir = rtrim($dir, '/');
        if ($dir === '' || !is_dir($dir)) return false;
        $f = $dir . '/.logviewer_probe_' . bin2hex(random_bytes(6));
        $ok = @file_put_contents($f, "ok", LOCK_EX) !== false;
        if ($ok) @unlink($f);
        return $ok;
    }
}

