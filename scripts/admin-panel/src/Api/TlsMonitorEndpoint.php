<?php
declare(strict_types=1);

namespace AdminPanel\Api;

use AdminPanel\Service\TlsMonitorService;

final class TlsMonitorEndpoint
{
    private TlsMonitorService $service;

    public function __construct(?TlsMonitorService $service = null)
    {
        $this->service = $service ?? new TlsMonitorService();
    }

    /**
     * @param array<string,mixed> $query
     */
    public function handle(array $query = []): void
    {
        $timeoutRaw = isset($query['timeout']) ? (string)$query['timeout'] : '4';
        $timeout = (int)$timeoutRaw;
        if ($timeout <= 0) {
            $timeout = 4;
        }
        $timeout = max(1, min(20, $timeout));

        $retriesRaw = isset($query['retries']) ? (string)$query['retries'] : '2';
        $retries = (int)$retriesRaw;
        if ($retries <= 0) {
            $retries = 2;
        }
        $retries = max(1, min(5, $retries));

        $payload = $this->service->collect(
            (string)($query['domain'] ?? ''),
            $timeout,
            $retries
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
