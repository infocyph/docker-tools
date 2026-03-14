<?php
declare(strict_types=1);

namespace AdminPanel\Service;

final class QueueHealthService
{
    /**
     * @return array<string,mixed>
     */
    public function collect(string $since = '60m', int $pendingThreshold = 500, int $heartbeatStaleSec = 900): array
    {
        $since = trim($since);
        if ($since === '') {
            $since = '60m';
        }
        $pendingThreshold = max(1, min(50000, $pendingThreshold));
        $heartbeatStaleSec = max(60, min(86400, $heartbeatStaleSec));

        $cmd = [
            'monitor-queue',
            '--json',
            '--since',
            $since,
            '--pending-threshold',
            (string)$pendingThreshold,
            '--heartbeat-stale-sec',
            (string)$heartbeatStaleSec,
        ];

        $res = $this->runCommand($cmd);
        if (!$res['ok']) {
            return [
                'ok' => false,
                'error' => 'queue_health_command_failed',
                'message' => $res['stderr'] !== '' ? $res['stderr'] : 'monitor-queue --json failed',
                'generated_at' => gmdate('Y-m-d\TH:i:s\Z'),
                'project' => '',
                'filters' => [
                    'since' => $since,
                    'pending_threshold' => $pendingThreshold,
                    'heartbeat_stale_sec' => $heartbeatStaleSec,
                ],
                'summary' => [
                    'workers' => 0,
                    'pass' => 0,
                    'warn' => 0,
                    'fail' => 0,
                    'stale_workers' => 0,
                    'failed_jobs_total' => 0,
                ],
                'queue_backend' => [],
                'items' => [],
            ];
        }

        $decoded = json_decode($res['stdout'], true);
        if (!is_array($decoded)) {
            return [
                'ok' => false,
                'error' => 'invalid_queue_health_json',
                'message' => 'monitor-queue --json returned malformed JSON.',
                'generated_at' => gmdate('Y-m-d\TH:i:s\Z'),
                'project' => '',
                'filters' => [
                    'since' => $since,
                    'pending_threshold' => $pendingThreshold,
                    'heartbeat_stale_sec' => $heartbeatStaleSec,
                ],
                'summary' => [
                    'workers' => 0,
                    'pass' => 0,
                    'warn' => 0,
                    'fail' => 0,
                    'stale_workers' => 0,
                    'failed_jobs_total' => 0,
                ],
                'queue_backend' => [],
                'items' => [],
            ];
        }

        return $decoded;
    }

    /**
     * @param list<string> $command
     * @return array{ok:bool,stdout:string,stderr:string,exit_code:int}
     */
    private function runCommand(array $command): array
    {
        if (!function_exists('proc_open')) {
            return [
                'ok' => false,
                'stdout' => '',
                'stderr' => 'proc_open unavailable',
                'exit_code' => 127,
            ];
        }

        $descriptors = [
            1 => ['pipe', 'w'],
            2 => ['pipe', 'w'],
        ];

        $proc = @proc_open($command, $descriptors, $pipes);
        if (!is_resource($proc)) {
            return [
                'ok' => false,
                'stdout' => '',
                'stderr' => 'failed to start process',
                'exit_code' => 127,
            ];
        }

        $stdout = stream_get_contents($pipes[1]) ?: '';
        fclose($pipes[1]);
        $stderr = stream_get_contents($pipes[2]) ?: '';
        fclose($pipes[2]);

        $exitCode = (int)@proc_close($proc);

        return [
            'ok' => ($exitCode === 0),
            'stdout' => $stdout,
            'stderr' => trim($stderr),
            'exit_code' => $exitCode,
        ];
    }
}
