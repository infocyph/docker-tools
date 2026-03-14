<?php
declare(strict_types=1);

namespace AdminPanel\Api;

use AdminPanel\Service\VolumeMonitorService;

final class VolumeMonitorEndpoint
{
    private VolumeMonitorService $service;

    public function __construct(?VolumeMonitorService $service = null)
    {
        $this->service = $service ?? new VolumeMonitorService();
    }

    /**
     * @param array<string,mixed> $query
     */
    public function handle(array $query = []): void
    {
        $topRaw = isset($query['top']) ? (string)$query['top'] : '20';
        $top = (int)$topRaw;
        if ($top <= 0) {
            $top = 20;
        }

        $inodeTopRaw = isset($query['inode_top']) ? (string)$query['inode_top'] : '8';
        $inodeTop = (int)$inodeTopRaw;
        if ($inodeTop < 0) {
            $inodeTop = 8;
        }

        $payload = $this->service->collect($top, $inodeTop);

        $status = (bool)($payload['ok'] ?? false) ? 200 : 500;
        if (!headers_sent()) {
            http_response_code($status);
            header('Content-Type: application/json; charset=UTF-8');
            header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');
        }

        echo json_encode($payload, JSON_UNESCAPED_SLASHES);
    }
}
