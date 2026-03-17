<?php
declare(strict_types=1);

namespace AdminPanel\Service;

use AdminPanel\Support\ProcessRunner;

final class DbHealthService
{
    private const COMMAND_TIMEOUT_SECONDS = 20;

    /**
     * @return array<string,mixed>
     */
    public function collect(string $engine = 'all'): array
    {
        $engine = strtolower(trim($engine));
        if (!in_array($engine, ['all', 'mysql', 'mariadb', 'postgres', 'redis', 'mongodb', 'elasticsearch', 'db-client'], true)) {
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
                    'mariadb' => 0,
                    'postgres' => 0,
                    'mongodb' => 0,
                    'elasticsearch' => 0,
                    'db_client' => 0,
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
                    'mariadb' => 0,
                    'postgres' => 0,
                    'mongodb' => 0,
                    'elasticsearch' => 0,
                    'db_client' => 0,
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
