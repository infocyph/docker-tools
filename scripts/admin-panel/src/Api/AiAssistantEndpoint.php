<?php
declare(strict_types=1);

namespace AdminPanel\Api;

use AdminPanel\Service\AiAssistantService;

final class AiAssistantEndpoint
{
    private AiAssistantService $service;

    public function __construct(?AiAssistantService $service = null)
    {
        $this->service = $service ?? new AiAssistantService();
    }

    /**
     * @param array<string,mixed> $query
     * @param array<string,mixed> $server
     */
    public function handle(array $query = [], array $server = []): void
    {
        $method = strtoupper((string)($server['REQUEST_METHOD'] ?? $_SERVER['REQUEST_METHOD'] ?? 'GET'));

        if ($method === 'GET') {
            $payload = $this->service->status();
            $payload['sources'] = $this->service->sources();
        } elseif ($method === 'POST') {
            $payload = $this->service->analyze($this->readJsonBody());
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
            } elseif ($error === 'ai_timeout') {
                $status = 504;
            } elseif (in_array($error, ['ai_analysis_failed', 'invalid_ai_response'], true)) {
                $status = 503;
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

    /** @return array<string,mixed> */
    private function readJsonBody(): array
    {
        $raw = file_get_contents('php://input');
        if (!is_string($raw) || trim($raw) === '') {
            return [];
        }
        $decoded = json_decode($raw, true);
        return is_array($decoded) ? $decoded : [];
    }
}
