<?php
declare(strict_types=1);

namespace AdminPanel\Api;

use AdminPanel\Service\RuntimeEventsService;

final class RuntimeEventsEndpoint
{
    private RuntimeEventsService $service;

    public function __construct(?RuntimeEventsService $service = null)
    {
        $this->service = $service ?? new RuntimeEventsService();
    }

    /**
     * @param array<string,mixed> $query
     */
    public function handle(array $query = []): void
    {
        $restartRaw = isset($query['restart_threshold']) ? (string)$query['restart_threshold'] : '3';
        $restartThreshold = (int)$restartRaw;
        if ($restartThreshold <= 0) {
            $restartThreshold = 3;
        }

        $eventLimitRaw = isset($query['event_limit']) ? (string)$query['event_limit'] : '80';
        $eventLimit = (int)$eventLimitRaw;
        if ($eventLimit < 0) {
            $eventLimit = 80;
        }

        $payload = $this->service->collect(
            (string)($query['since'] ?? '60m'),
            $restartThreshold,
            $eventLimit
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
