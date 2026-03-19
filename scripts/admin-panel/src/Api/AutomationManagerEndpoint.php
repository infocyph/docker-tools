<?php
declare(strict_types=1);

namespace AdminPanel\Api;

use AdminPanel\Service\AutomationManagerService;

final class AutomationManagerEndpoint
{
    private AutomationManagerService $service;

    public function __construct(?AutomationManagerService $service = null)
    {
        $this->service = $service ?? new AutomationManagerService();
    }

    /**
     * @param array<string,mixed> $query
     * @param array<string,mixed> $server
     */
    public function handle(array $query = [], array $server = []): void
    {
        $method = strtoupper((string)($server['REQUEST_METHOD'] ?? $_SERVER['REQUEST_METHOD'] ?? 'GET'));

        if ($method === 'GET') {
            $action = strtolower(trim((string)($query['action'] ?? '')));
            if ($action === 'options') {
                $payload = [
                    'ok' => true,
                    'generated_at' => gmdate('Y-m-d\TH:i:s\Z'),
                    'options' => $this->service->formOptions(),
                ];
            } else {
                $payload = $this->service->listConfigs();
            }
        } elseif ($method === 'POST' || $method === 'PUT' || $method === 'PATCH') {
            $body = $this->readJsonBody();
            $payload = $this->service->saveConfig($body);
        } elseif ($method === 'DELETE') {
            $body = $this->readJsonBody();
            $kind = trim((string)($query['kind'] ?? $body['kind'] ?? ''));
            $name = trim((string)($query['name'] ?? $body['name'] ?? ''));
            $payload = $this->service->deleteConfig($kind, $name);
        } else {
            $payload = [
                'ok' => false,
                'error' => 'unknown_method',
                'message' => 'Unsupported method: ' . $method,
            ];
        }

        $status = 200;
        if (!(bool)($payload['ok'] ?? false)) {
            $error = (string)($payload['error'] ?? '');
            if (str_starts_with($error, 'validation_') || $error === 'unknown_method') {
                $status = 400;
            } elseif ($error === 'not_found') {
                $status = 404;
            } else {
                $status = 500;
            }
        }

        if (!headers_sent()) {
            http_response_code($status);
            header('Content-Type: application/json; charset=UTF-8');
            header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');
        }

        echo json_encode($payload, JSON_UNESCAPED_SLASHES);
    }

    /**
     * @return array<string,mixed>
     */
    private function readJsonBody(): array
    {
        $raw = file_get_contents('php://input');
        if (!is_string($raw)) {
            return [];
        }

        $raw = trim($raw);
        if ($raw === '') {
            return [];
        }

        $decoded = json_decode($raw, true);
        if (!is_array($decoded)) {
            return [];
        }

        return $decoded;
    }
}
