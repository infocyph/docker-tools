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
        $payload = $this->service->collect();

        $status = (bool)($payload['ok'] ?? false) ? 200 : 500;
        if (!headers_sent()) {
            http_response_code($status);
            header('Content-Type: application/json; charset=UTF-8');
            header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');
        }

        echo json_encode($payload, JSON_UNESCAPED_SLASHES);
    }
}
