<?php
declare(strict_types=1);

namespace AdminPanel\Service;

final class DbHealthService
{
    /**
     * @return array<string,mixed>
     */
    public function collect(string $engine = 'all'): array
    {
        $engine = strtolower(trim($engine));
        if (!in_array($engine, ['all', 'mysql', 'postgres', 'redis'], true)) {
            $engine = 'all';
        }

        $cmd = ['monitor-db', '--json'];
        if ($engine !== 'all') {
            $cmd[] = '--engine';
            $cmd[] = $engine;
        }

        $res = $this->runCommand($cmd);
        if (!$res['ok']) {
            return [
                'ok' => false,
                'error' => 'db_health_command_failed',
                'message' => $res['stderr'] !== '' ? $res['stderr'] : 'monitor-db --json failed',
                'generated_at' => gmdate('Y-m-d\TH:i:s\Z'),
                'project' => '',
                'filters' => [
                    'engine' => $engine,
                ],
                'summary' => [
                    'targets' => 0,
                    'pass' => 0,
                    'warn' => 0,
                    'fail' => 0,
                    'running' => 0,
                    'not_running' => 0,
                    'redis' => 0,
                    'mysql' => 0,
                    'postgres' => 0,
                ],
                'items' => [],
            ];
        }

        $decoded = json_decode($res['stdout'], true);
        if (!is_array($decoded)) {
            return [
                'ok' => false,
                'error' => 'invalid_db_health_json',
                'message' => 'monitor-db --json returned malformed JSON.',
                'generated_at' => gmdate('Y-m-d\TH:i:s\Z'),
                'project' => '',
                'filters' => [
                    'engine' => $engine,
                ],
                'summary' => [
                    'targets' => 0,
                    'pass' => 0,
                    'warn' => 0,
                    'fail' => 0,
                    'running' => 0,
                    'not_running' => 0,
                    'redis' => 0,
                    'mysql' => 0,
                    'postgres' => 0,
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
