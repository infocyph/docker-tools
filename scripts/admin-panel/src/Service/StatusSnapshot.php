<?php
declare(strict_types=1);

namespace AdminPanel\Service;

use AdminPanel\Support\ProcessRunner;

final class StatusSnapshot
{
    /** @return array<string,mixed> */
    public function collect(): array
    {
        $result = ProcessRunner::run(['status', '--json'], 30, null, 1048576);
        if (!(bool)($result['ok'] ?? false)) {
            return [
                'ok' => false,
                'error' => 'status_command_failed',
                'message' => trim((string)($result['stderr'] ?? 'status --json failed.')) ?: 'status --json failed.',
            ];
        }

        $raw = (string)($result['stdout'] ?? '');
        if (trim($raw) === '') {
            return [
                'ok' => false,
                'error' => 'status_command_failed',
                'message' => 'status --json returned empty output.',
            ];
        }

        $decoded = json_decode($raw, true);
        if (!is_array($decoded)) {
            return [
                'ok' => false,
                'error' => 'invalid_json',
                'message' => 'status --json returned malformed JSON.',
            ];
        }

        return [
            'ok' => true,
            'generated_at' => (string)($decoded['generated_at'] ?? ''),
            'summary' => $this->buildSummary($decoded),
            'data' => $decoded,
        ];
    }

    /** @param array<string,mixed> $payload @return array<string,mixed> */
    private function buildSummary(array $payload): array
    {
        $containers = (array)($payload['sections']['containers']['core']['items'] ?? []);
        $healthy = 0;
        $unhealthy = 0;
        $noHealth = 0;

        foreach ($containers as $container) {
            if (!is_array($container)) {
                continue;
            }
            $health = strtolower((string)($container['health'] ?? ''));
            if ($health === 'healthy') {
                ++$healthy;
            } elseif ($health === '-' || $health === '') {
                ++$noHealth;
            } else {
                ++$unhealthy;
            }
        }

        return [
            'running' => (int)($payload['core']['summary']['running'] ?? 0),
            'total' => (int)($payload['core']['summary']['total'] ?? 0),
            'healthy' => $healthy,
            'unhealthy' => $unhealthy,
            'no_health' => $noHealth,
            'problem_count' => (int)($payload['sections']['problems']['count'] ?? 0),
            'url_count' => count((array)($payload['core']['urls'] ?? [])),
            'port_count' => count((array)($payload['core']['ports'] ?? [])),
            'system_checks' => (array)($payload['sections']['checks']['system']['summary'] ?? []),
            'project_checks' => (array)($payload['sections']['checks']['project']['summary'] ?? []),
            'build_cache_reclaimable' => (string)($payload['sections']['drift']['build_cache_reclaimable'] ?? ''),
            'egress_ip' => (string)($payload['sections']['checks']['system']['tests']['egress_ip']['value'] ?? ''),
        ];
    }
}
