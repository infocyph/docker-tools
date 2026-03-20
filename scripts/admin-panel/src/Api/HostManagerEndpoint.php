<?php
declare(strict_types=1);

namespace AdminPanel\Api;

use AdminPanel\Service\HostManagerService;

final class HostManagerEndpoint
{
    private HostManagerService $service;

    public function __construct(?HostManagerService $service = null)
    {
        $this->service = $service ?? new HostManagerService();
    }

    /**
     * @param array<string,mixed> $query
     * @param array<string,mixed> $server
     */
    public function handle(array $query = [], array $server = []): void
    {
        $method = strtoupper((string)($server['REQUEST_METHOD'] ?? $_SERVER['REQUEST_METHOD'] ?? 'GET'));
        $payload = [];

        if ($method === 'GET') {
            $action = strtolower(trim((string)($query['action'] ?? '')));
            if ($action === 'options') {
                $payload = [
                    'ok' => true,
                    'generated_at' => gmdate('Y-m-d\TH:i:s\Z'),
                    'options' => $this->service->formOptions(),
                ];
            } else {
                $payload = $this->service->listHosts();
            }
        } elseif ($method === 'POST') {
            $body = $this->readJsonBody();
            $payload = $this->service->addHost($body);
        } elseif ($method === 'PUT' || $method === 'PATCH') {
            $body = $this->readJsonBody();
            $payload = $this->service->editHost($body);
        } elseif ($method === 'DELETE') {
            $body = $this->readJsonBody();
            $domain = trim((string)($query['domain'] ?? $body['domain'] ?? ''));
            $payload = $this->service->deleteHost($domain);
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
            $status = str_starts_with($error, 'validation_') || $error === 'unknown_method' ? 400 : 500;
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
