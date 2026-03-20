<?php
declare(strict_types=1);

namespace AdminPanel\Service;

use AdminPanel\Support\ProcessRunner;

final class VolumeMonitorService
{
    private const COMMAND_TIMEOUT_SECONDS = 20;

    /**
     * @return array<string,mixed>
     */
    public function collect(): array
    {
        $cmd = [
            'monitor-volumes',
            '--json',
        ];

        $res = $this->runCommand($cmd);
        if (!$res['ok']) {
            return [
                'ok' => false,
                'error' => 'volume_monitor_command_failed',
                'message' => $res['stderr'] !== '' ? $res['stderr'] : 'monitor-volumes --json failed',
                'generated_at' => gmdate('Y-m-d\TH:i:s\Z'),
                'project' => '',
                'filters' => [],
                'summary' => [
                    'volumes' => 0,
                    'pass' => 0,
                    'warn' => 0,
                    'fail' => 0,
                    'inode_scanned' => 0,
                    'docker_root_free_bytes' => -1,
                ],
                'items' => [],
            ];
        }

        $decoded = json_decode($res['stdout'], true);
        if (!is_array($decoded)) {
            return [
                'ok' => false,
                'error' => 'invalid_volume_monitor_json',
                'message' => 'monitor-volumes --json returned malformed JSON.',
                'generated_at' => gmdate('Y-m-d\TH:i:s\Z'),
                'project' => '',
                'filters' => [],
                'summary' => [
                    'volumes' => 0,
                    'pass' => 0,
                    'warn' => 0,
                    'fail' => 0,
                    'inode_scanned' => 0,
                    'docker_root_free_bytes' => -1,
                ],
                'items' => [],
            ];
        }

        return $this->normalizePayload($decoded);
    }

    /**
     * @param array<string,mixed> $payload
     * @return array<string,mixed>
     */
    private function normalizePayload(array $payload): array
    {
        $itemsRaw = $payload['items'] ?? [];
        $items = [];
        if (is_array($itemsRaw)) {
            foreach ($itemsRaw as $item) {
                if (is_array($item)) {
                    $items[] = $item;
                }
            }
        }

        $summary = is_array($payload['summary'] ?? null) ? $payload['summary'] : [];
        $dockerFreeBytes = $this->toInt($summary['docker_root_free_bytes'] ?? -1, -1);

        $pass = 0;
        $warn = 0;
        $fail = 0;
        $inodeScanned = 0;

        foreach ($items as &$item) {
            $level = strtolower(trim((string)($item['level'] ?? '')));
            if ($level !== 'pass' && $level !== 'warn' && $level !== 'fail') {
                $level = $this->inferLevelFromNote((string)($item['note'] ?? ''));
                $item['level'] = $level;
            }

            if ($level === 'pass') {
                $pass++;
            } elseif ($level === 'warn') {
                $warn++;
            } else {
                $fail++;
            }

            $inodePct = $this->toInt($item['inode_pct'] ?? -1, -1);
            if ($inodePct >= 0) {
                $inodeScanned++;
            }
            $item['inode_pct'] = $inodePct;

            $item['eta_hours'] = $this->toInt($item['eta_hours'] ?? -1, -1);
            $item['file_count'] = $this->toInt($item['file_count'] ?? -1, -1);

            $item['pressure_pct'] = $this->toInt($item['pressure_pct'] ?? -1, -1);
        }
        unset($item);

        $summary['volumes'] = count($items);
        $summary['pass'] = $pass;
        $summary['warn'] = $warn;
        $summary['fail'] = $fail;
        $summary['inode_scanned'] = $inodeScanned;
        $summary['docker_root_free_bytes'] = $dockerFreeBytes;

        if (!is_array($payload['filters'] ?? null)) {
            $payload['filters'] = [];
        }
        $payload['summary'] = $summary;
        $payload['items'] = $items;

        if (!isset($payload['generated_at']) || !is_string($payload['generated_at']) || trim($payload['generated_at']) === '') {
            $payload['generated_at'] = gmdate('Y-m-d\TH:i:s\Z');
        }
        if (!isset($payload['project']) || !is_string($payload['project'])) {
            $payload['project'] = '';
        }
        $payload['ok'] = (bool)($payload['ok'] ?? true);

        return $payload;
    }

    private function toInt(mixed $value, int $default): int
    {
        if (is_int($value)) {
            return $value;
        }
        if (is_string($value) && preg_match('/^-?\d+$/', $value) === 1) {
            return (int)$value;
        }

        return $default;
    }

    private function inferLevelFromNote(string $note): string
    {
        $code = strtolower(trim($note));
        if ($code === 'growth_critical' || $code === 'capacity_critical' || $code === 'inode_critical') {
            return 'fail';
        }
        if ($code === 'growth_fast' || $code === 'capacity_high' || $code === 'inode_high') {
            return 'warn';
        }

        return 'pass';
    }

    /**
     * @param list<string> $command
     * @return array{ok:bool,stdout:string,stderr:string,exit_code:int}
     */
    private function runCommand(array $command): array
    {
        return ProcessRunner::run($command, self::COMMAND_TIMEOUT_SECONDS);
    }
}
