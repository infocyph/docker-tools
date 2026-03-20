<?php
declare(strict_types=1);

namespace AdminPanel\Api;

use AdminPanel\Service\QueueHealthService;

final class QueueHealthEndpoint
{
    private QueueHealthService $service;

    public function __construct(?QueueHealthService $service = null)
    {
        $this->service = $service ?? new QueueHealthService();
    }

    /**
     * @param array<string,mixed> $query
     */
    public function handle(array $query = []): void
    {
        $pendingThresholdRaw = isset($query['pending_threshold']) ? (string)$query['pending_threshold'] : '500';
        $pendingThreshold = (int)$pendingThresholdRaw;
        if ($pendingThreshold <= 0) {
            $pendingThreshold = 500;
        }

        $heartbeatStaleSecRaw = isset($query['heartbeat_stale_sec']) ? (string)$query['heartbeat_stale_sec'] : '900';
        $heartbeatStaleSec = (int)$heartbeatStaleSecRaw;
        if ($heartbeatStaleSec <= 0) {
            $heartbeatStaleSec = 900;
        }

        $payload = $this->service->collect(
            (string)($query['since'] ?? '60m'),
            $pendingThreshold,
            $heartbeatStaleSec
        );

        $status = (bool)($payload['ok'] ?? false) ? 200 : 500;
        if (!headers_sent()) {
            http_response_code($status);
            header('Content-Type: application/json; charset=UTF-8');
            header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');
        }

        echo json_encode($payload, JSON_UNESCAPED_SLASHES);
    }
}
