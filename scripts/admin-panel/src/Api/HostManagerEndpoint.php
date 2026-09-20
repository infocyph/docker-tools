<?php
declare(strict_types=1);

namespace AdminPanel\Api;

use AdminPanel\Service\HostManagerService;
use AdminPanel\Service\HostTransactionService;

final class HostManagerEndpoint
{
    private const RESERVED_HOSTS = [
        'admin.localhost',
        'webmail.localhost',
        'db.localhost',
        'ri.localhost',
        'me.localhost',
        'llm.localhost',
        'llm-ollama.localhost',
        'llm-fastflow.localhost',
    ];

    private HostManagerService $service;
    private HostTransactionService $transactions;

    public function __construct(?HostManagerService $service = null, ?HostTransactionService $transactions = null)
    {
        $this->service = $service ?? new HostManagerService();
        $this->transactions = $transactions ?? new HostTransactionService($this->service);
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
            $payload = $this->reservedHostError((string)($body['domain'] ?? '')) ?? $this->transactions->addHost($body);
        } elseif ($method === 'PUT' || $method === 'PATCH') {
            $body = $this->readJsonBody();
            $payload = $this->reservedHostError((string)($body['domain'] ?? '')) ?? $this->transactions->editHost($body);
        } elseif ($method === 'DELETE') {
            $body = $this->readJsonBody();
            $domain = trim((string)($query['domain'] ?? $body['domain'] ?? ''));
            $reserved = $this->reservedHostError($domain);
            $payload = $reserved ?? $this->transactions->deleteHost($domain);
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
            if (str_starts_with($error, 'validation_') || $error === 'unknown_method' || $error === 'reserved_host') {
                $status = 400;
            } elseif ($error === 'host_mutation_busy') {
                $status = 409;
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

    /** @return array<string,mixed>|null */
    private function reservedHostError(string $domain): ?array
    {
        $domain = strtolower(rtrim(trim($domain), '.'));
        if (!in_array($domain, self::RESERVED_HOSTS, true)) {
            return null;
        }
        return [
            'ok' => false,
            'error' => 'reserved_host',
            'message' => $domain . ' is reserved by LocalDevStack and cannot be managed as an application host.',
        ];
    }

    /** @return array<string,mixed> */
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
        return is_array($decoded) ? $decoded : [];
    }
}
