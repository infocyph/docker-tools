<?php
declare(strict_types=1);

namespace AdminPanel\Api;

use AdminPanel\Service\LogsDataService;

final class LogsEntriesEndpoint
{
    private LogsDataService $logsData;

    public function __construct(?LogsDataService $logsData = null)
    {
        $this->logsData = $logsData ?? new LogsDataService();
    }

    /**
     * @param array<string,mixed> $query
     */
    public function handle(array $query = []): void
    {
        $token = strtolower(trim((string)($query['file'] ?? '')));
        if ($token === '') {
            $this->send(
                400,
                [
                    'ok' => false,
                    'error' => 'missing_file_token',
                ]
            );
            return;
        }

        $payload = $this->logsData->entriesPayload($token);
        if (!$payload['found']) {
            $this->send(
                404,
                [
                    'ok' => false,
                    'error' => 'file_not_found',
                ]
            );
            return;
        }

        $this->send(
            200,
            [
                'ok' => true,
                'file' => $payload['file'],
                'rows' => $payload['rows'],
                'levelCounts' => $payload['levelCounts'],
            ]
        );
    }

    /**
     * @param array<string,mixed> $payload
     */
    private function send(int $status, array $payload): void
    {
        if (!headers_sent()) {
            http_response_code($status);
            header('Content-Type: application/json; charset=UTF-8');
            header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');
        }
        echo json_encode($payload, JSON_UNESCAPED_SLASHES);
    }
}

