<?php
declare(strict_types=1);

namespace AdminPanel\Api;

use AdminPanel\Service\DockerLogsService;

final class DockerLogsEndpoint
{
    private DockerLogsService $service;

    public function __construct(?DockerLogsService $service = null)
    {
        $this->service = $service ?? new DockerLogsService();
    }

    /**
     * @param array<string,mixed> $query
     */
    public function handle(array $query = []): void
    {
        $tailRaw = isset($query['tail']) ? (string)$query['tail'] : '80';
        $tail = (int)$tailRaw;
        if ($tail <= 0) {
            $tail = 80;
        }

        $payload = $this->service->collect(
            (string)($query['service'] ?? ''),
            (string)($query['since'] ?? ''),
            (string)($query['grep'] ?? ''),
            $tail
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

