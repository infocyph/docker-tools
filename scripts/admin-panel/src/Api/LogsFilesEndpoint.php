<?php
declare(strict_types=1);

namespace AdminPanel\Api;

use AdminPanel\Service\LogsDataService;

final class LogsFilesEndpoint
{
    private const JSON_FLAGS = JSON_UNESCAPED_SLASHES | JSON_INVALID_UTF8_SUBSTITUTE;

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
        $selectedToken = (string)($query['file'] ?? '');
        $payload = $this->logsData->listFilesPayload($selectedToken);
        $files = array_map(
            static fn(array $f): array => [
                'token' => (string)($f['token'] ?? ''),
                'name' => (string)($f['name'] ?? ''),
                'size' => (string)($f['size'] ?? '0 B'),
                'sizeBytes' => (int)($f['sizeBytes'] ?? 0),
                'mtime' => (string)($f['mtime'] ?? 'Unknown'),
                'mtimeTs' => (int)($f['mtimeTs'] ?? 0),
                'service' => (string)($f['service'] ?? ''),
                'serviceKey' => (string)($f['serviceKey'] ?? ''),
                'domain' => (string)($f['domain'] ?? ''),
                'isEmpty' => (bool)($f['isEmpty'] ?? false),
            ],
            $payload['files']
        );

        $this->send(
            200,
            [
                'ok' => true,
                'rootsText' => $payload['rootsText'],
                'services' => $payload['services'],
                'domains' => $payload['domains'],
                'files' => $files,
                'activeToken' => $payload['activeToken'],
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

        $json = json_encode($payload, self::JSON_FLAGS);
        if ($json === false) {
            if (!headers_sent()) {
                http_response_code(500);
            }
            echo '{"ok":false,"error":"json_encode_failed"}';
            return;
        }

        echo $json;
    }
}
