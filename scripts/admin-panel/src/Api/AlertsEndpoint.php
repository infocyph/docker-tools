<?php
declare(strict_types=1);

namespace AdminPanel\Api;

use AdminPanel\Service\AlertsService;

final class AlertsEndpoint
{
    private AlertsService $service;

    public function __construct(?AlertsService $service = null)
    {
        $this->service = $service ?? new AlertsService();
    }

    /**
     * @param array<string,mixed> $query
     */
    public function handle(array $query = []): void
    {
        $runRaw = isset($query['run']) ? (string)$query['run'] : '';
        $run = in_array(strtolower($runRaw), ['1', 'true', 'yes', 'on'], true);

        $payload = $this->service->collect(
            $run,
            (string)($query['ack_rule'] ?? ''),
            (string)($query['ack_fingerprint'] ?? '')
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
