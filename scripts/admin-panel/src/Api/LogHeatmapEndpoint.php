<?php
declare(strict_types=1);

namespace AdminPanel\Api;

use AdminPanel\Service\LogHeatmapService;

final class LogHeatmapEndpoint
{
    private LogHeatmapService $service;

    public function __construct(?LogHeatmapService $service = null)
    {
        $this->service = $service ?? new LogHeatmapService();
    }

    /**
     * @param array<string,mixed> $query
     */
    public function handle(array $query = []): void
    {
        $bucketMinRaw = isset($query['bucket_min']) ? (string)$query['bucket_min'] : '15';
        $bucketMin = (int)$bucketMinRaw;
        if ($bucketMin <= 0) {
            $bucketMin = 15;
        }

        $topRaw = isset($query['top']) ? (string)$query['top'] : '12';
        $top = (int)$topRaw;
        if ($top <= 0) {
            $top = 12;
        }

        $lineLimitRaw = isset($query['line_limit']) ? (string)$query['line_limit'] : '1000';
        $lineLimit = (int)$lineLimitRaw;
        if ($lineLimit <= 0) {
            $lineLimit = 1000;
        }

        $source = strtolower(trim((string)($query['source'] ?? 'both')));
        if (!in_array($source, ['both', 'docker', 'file'], true)) {
            $source = 'both';
        }

        $payload = $this->service->collect(
            $source,
            (string)($query['since'] ?? '24h'),
            $bucketMin,
            $top,
            $lineLimit
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
