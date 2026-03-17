<?php
declare(strict_types=1);

namespace AdminPanel\Service;

use AdminPanel\Support\ProcessRunner;

final class QueueHealthService
{
    private const COMMAND_TIMEOUT_SECONDS = 20;

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
                    'runner_issues' => 0,
                ],
                'queue_backend' => [
                    'type' => 'redis',
                    'container' => '',
                    'state' => '',
                    'pending' => 0,
                    'delayed' => 0,
                    'reserved' => 0,
                    'oldest_pending_age_s' => -1,
                    'level' => 'warn',
                    'note' => 'backend_not_detected',
                    'runner' => [
                        'container' => '',
                        'state' => '',
                        'supervisor' => 'unknown',
                        'cron' => 'missing',
                        'logrotate' => 'missing',
                        'programs_total' => 0,
                        'programs_not_running' => 0,
                        'level' => 'warn',
                        'note' => 'runner_not_detected',
                    ],
                ],
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
                    'runner_issues' => 0,
                ],
                'queue_backend' => [
                    'type' => 'redis',
                    'container' => '',
                    'state' => '',
                    'pending' => 0,
                    'delayed' => 0,
                    'reserved' => 0,
                    'oldest_pending_age_s' => -1,
                    'level' => 'warn',
                    'note' => 'backend_not_detected',
                    'runner' => [
                        'container' => '',
                        'state' => '',
                        'supervisor' => 'unknown',
                        'cron' => 'missing',
                        'logrotate' => 'missing',
                        'programs_total' => 0,
                        'programs_not_running' => 0,
                        'level' => 'warn',
                        'note' => 'runner_not_detected',
                    ],
                ],
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
        return ProcessRunner::run($command, self::COMMAND_TIMEOUT_SECONDS);
    }
}
