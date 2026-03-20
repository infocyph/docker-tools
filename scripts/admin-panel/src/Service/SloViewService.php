<?php
declare(strict_types=1);

namespace AdminPanel\Service;

use AdminPanel\Support\ProcessRunner;

final class SloViewService
{
    private const COMMAND_TIMEOUT_SECONDS = 20;

    /**
     * @return array<string,mixed>
     */
    public function collect(int $timeout = 4, string $paths = ''): array
    {
        $timeout = max(1, min(20, $timeout));
        $paths = trim($paths);

        $cmd = ['monitor-slo', '--json', '--timeout', (string)$timeout];
        if ($paths !== '') {
            $cmd[] = '--paths';
            $cmd[] = $paths;
        }

        $res = $this->runCommand($cmd);
        if (!$res['ok']) {
            return [
                'ok' => false,
                'error' => 'slo_view_command_failed',
                'message' => $res['stderr'] !== '' ? $res['stderr'] : 'monitor-slo --json failed',
                'generated_at' => gmdate('Y-m-d\TH:i:s\Z'),
                'project' => '',
                'filters' => [
                    'timeout' => $timeout,
                    'paths' => $paths,
                ],
                'summary' => ['windows' => []],
                'items' => [],
            ];
        }

        $decoded = json_decode($res['stdout'], true);
        if (!is_array($decoded)) {
            return [
                'ok' => false,
                'error' => 'invalid_slo_view_json',
                'message' => 'monitor-slo --json returned malformed JSON.',
                'generated_at' => gmdate('Y-m-d\TH:i:s\Z'),
                'project' => '',
                'filters' => [
                    'timeout' => $timeout,
                    'paths' => $paths,
                ],
                'summary' => ['windows' => []],
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
