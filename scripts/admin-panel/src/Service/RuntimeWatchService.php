<?php
declare(strict_types=1);

namespace AdminPanel\Service;

final class RuntimeWatchService
{
    /**
     * @return array<string,mixed>
     */
    public function collect(string $since = '60m', int $restartThreshold = 3, int $eventLimit = 80): array
    {
        $since = trim($since);
        if ($since === '') {
            $since = '60m';
        }
        $restartThreshold = max(1, min(50, $restartThreshold));
        $eventLimit = max(0, min(500, $eventLimit));

        $cmd = [
            'monitor-runtime',
            '--json',
            '--since',
            $since,
            '--restart-threshold',
            (string)$restartThreshold,
            '--event-limit',
            (string)$eventLimit,
        ];

        $res = $this->runCommand($cmd);
        if (!$res['ok']) {
            return [
                'ok' => false,
                'error' => 'runtime_watch_command_failed',
                'message' => $res['stderr'] !== '' ? $res['stderr'] : 'monitor-runtime --json failed',
                'generated_at' => gmdate('Y-m-d\TH:i:s\Z'),
                'project' => '',
                'filters' => [
                    'since' => $since,
                    'restart_threshold' => $restartThreshold,
                    'event_limit' => $eventLimit,
                ],
                'summary' => [
                    'containers' => 0,
                    'pass' => 0,
                    'warn' => 0,
                    'fail' => 0,
                    'with_issues' => 0,
                    'flapping' => 0,
                    'oom_killed' => 0,
                    'events_total' => 0,
                ],
                'items' => [],
                'events' => [],
            ];
        }

        $decoded = json_decode($res['stdout'], true);
        if (!is_array($decoded)) {
            return [
                'ok' => false,
                'error' => 'invalid_runtime_watch_json',
                'message' => 'monitor-runtime --json returned malformed JSON.',
                'generated_at' => gmdate('Y-m-d\TH:i:s\Z'),
                'project' => '',
                'filters' => [
                    'since' => $since,
                    'restart_threshold' => $restartThreshold,
                    'event_limit' => $eventLimit,
                ],
                'summary' => [
                    'containers' => 0,
                    'pass' => 0,
                    'warn' => 0,
                    'fail' => 0,
                    'with_issues' => 0,
                    'flapping' => 0,
                    'oom_killed' => 0,
                    'events_total' => 0,
                ],
                'items' => [],
                'events' => [],
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
