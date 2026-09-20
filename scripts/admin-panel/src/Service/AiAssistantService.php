<?php
declare(strict_types=1);

namespace AdminPanel\Service;

use AdminPanel\Support\ProcessRunner;

final class AiAssistantService
{
    private const DEFAULT_ANALYSIS_TIMEOUT_SECONDS = 1800;
    private const MAX_ANALYSIS_TIMEOUT_SECONDS = 3600;
    private const STATUS_TIMEOUT_SECONDS = 6;
    private const MAX_OUTPUT_BYTES = 4194304;
    private const SOURCES = [
        'status',
        'alerts',
        'slo',
        'db',
        'queue',
        'tls',
        'volume',
        'drift',
        'logs',
        'troubleshoot',
    ];

    /** @return array<string,mixed> */
    public function status(): array
    {
        $binary = trim((string)getenv('ADMIN_PANEL_ASKAI_BIN'));
        if ($binary === '') {
            $binary = 'askai';
        }

        $res = ProcessRunner::run([$binary, '--status'], self::STATUS_TIMEOUT_SECONDS, null, 65536);
        $fields = [];
        foreach (preg_split('/\r?\n/', (string)$res['stdout']) ?: [] as $line) {
            if (!str_contains($line, '=')) {
                continue;
            }
            [$key, $value] = explode('=', $line, 2);
            $key = trim($key);
            if ($key !== '') {
                $fields[$key] = trim($value);
            }
        }

        return [
            'ok' => true,
            'available' => (($fields['available'] ?? '0') === '1'),
            'enabled' => (string)($fields['enabled'] ?? ''),
            'provider' => (string)($fields['provider'] ?? 'ollama'),
            'url' => (string)($fields['url'] ?? ''),
            'model' => (string)($fields['model'] ?? ''),
            'think' => (string)($fields['think'] ?? 'auto'),
            'status_exit_code' => (int)$res['exit_code'],
            'analysis_timeout_seconds' => self::analysisTimeoutSeconds(),
            'generated_at' => gmdate('Y-m-d\TH:i:s\Z'),
        ];
    }

    /**
     * @param array<string,mixed> $input
     * @return array<string,mixed>
     */
    public function analyze(array $input): array
    {
        $source = strtolower(trim((string)($input['source'] ?? 'status')));
        if (!in_array($source, self::SOURCES, true)) {
            return $this->error('validation_source', 'Unsupported AI assistant source.');
        }

        $request = trim((string)($input['request'] ?? ''));
        if (strlen($request) > 2000) {
            return $this->error('validation_request', 'AI request must be 2000 bytes or less.');
        }

        $think = $this->normalizeThinkRequest($input['think'] ?? 'inherit');
        if ($think === null) {
            return $this->error('validation_think', 'AI thinking must be inherit, on, off, or auto.');
        }

        $binary = trim((string)getenv('ADMIN_PANEL_AIOPS_BIN'));
        if ($binary === '') {
            $binary = 'aiops';
        }

        $cmd = $source === 'troubleshoot'
            ? [$binary, 'troubleshoot', '--json']
            : [$binary, 'explain', $source, '--json'];

        if ($request !== '') {
            $cmd[] = '--request';
            $cmd[] = $request;
        }

        if ($think === 'on') {
            $cmd[] = '--think';
        } elseif ($think === 'off') {
            $cmd[] = '--no-think';
        } elseif ($think === 'auto') {
            $cmd[] = '--think-auto';
        }

        $analysisTimeout = self::analysisTimeoutSeconds();
        $res = ProcessRunner::run($cmd, $analysisTimeout, null, self::MAX_OUTPUT_BYTES);
        if (!(bool)$res['ok']) {
            $timedOut = !empty($res['timed_out']);
            $outputLimited = !empty($res['output_limited']);
            $message = trim((string)$res['stderr']);
            if ($message === '') {
                if ($timedOut) {
                    $message = sprintf('AI analysis exceeded the configured %d-second generation timeout.', $analysisTimeout);
                } elseif ($outputLimited) {
                    $message = 'AI analysis exceeded the configured output limit.';
                } else {
                    $message = 'AI analysis failed.';
                }
            }

            return [
                'ok' => false,
                'error' => $timedOut ? 'ai_timeout' : ($outputLimited ? 'ai_output_limited' : 'ai_analysis_failed'),
                'message' => $message,
                'exit_code' => (int)$res['exit_code'],
                'generated_at' => gmdate('Y-m-d\TH:i:s\Z'),
            ];
        }

        $decoded = json_decode((string)$res['stdout'], true);
        if (!is_array($decoded) || !isset($decoded['context'], $decoded['answer'])) {
            return $this->error('invalid_ai_response', 'AI assistant returned malformed JSON.');
        }

        return [
            'ok' => true,
            'source' => (string)($decoded['source'] ?? $source),
            'context' => (string)$decoded['context'],
            'answer' => (string)$decoded['answer'],
            'generated_at' => gmdate('Y-m-d\TH:i:s\Z'),
        ];
    }

    /** @return list<string> */
    public function sources(): array
    {
        return self::SOURCES;
    }

    private function normalizeThinkRequest(mixed $value): ?string
    {
        if (is_bool($value)) {
            return $value ? 'on' : 'off';
        }

        $normalized = strtolower(trim((string)$value));
        return match ($normalized) {
            '', 'inherit' => 'inherit',
            '1', 'true', 'yes', 'on' => 'on',
            '0', 'false', 'no', 'off' => 'off',
            'auto', 'default' => 'auto',
            default => null,
        };
    }

    private static function analysisTimeoutSeconds(): int
    {
        $raw = trim((string)getenv('LDS_AI_TIMEOUT'));
        if ($raw === '' || preg_match('/^[0-9]+$/D', $raw) !== 1) {
            return self::DEFAULT_ANALYSIS_TIMEOUT_SECONDS;
        }

        $timeout = (int)$raw;
        if ($timeout < 1 || $timeout > self::MAX_ANALYSIS_TIMEOUT_SECONDS) {
            return self::DEFAULT_ANALYSIS_TIMEOUT_SECONDS;
        }

        return $timeout;
    }

    /** @return array<string,mixed> */
    private function error(string $error, string $message): array
    {
        return [
            'ok' => false,
            'error' => $error,
            'message' => $message,
            'generated_at' => gmdate('Y-m-d\TH:i:s\Z'),
        ];
    }
}
