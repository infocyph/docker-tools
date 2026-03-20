<?php
declare(strict_types=1);

namespace AdminPanel\Service;

use AdminPanel\Support\ProcessRunner;

final class DriftMonitorService
{
    private const COMMAND_TIMEOUT_SECONDS = 20;

    /**
     * @return array<string,mixed>
     */
    public function collect(): array
    {
        $cmd = ['monitor-drift', '--json'];

        $res = $this->runCommand($cmd);
        if (!$res['ok']) {
            return [
                'ok' => false,
                'error' => 'drift_monitor_command_failed',
                'message' => $res['stderr'] !== '' ? $res['stderr'] : 'monitor-drift --json failed',
                'generated_at' => gmdate('Y-m-d\TH:i:s\Z'),
                'project' => '',
                'summary' => [
                    'components' => 0,
                    'pass' => 0,
                    'warn' => 0,
                    'fail' => 0,
                ],
                'items' => [],
            ];
        }

        $decoded = json_decode($res['stdout'], true);
        if (!is_array($decoded)) {
            return [
                'ok' => false,
                'error' => 'invalid_drift_monitor_json',
                'message' => 'monitor-drift --json returned malformed JSON.',
                'generated_at' => gmdate('Y-m-d\TH:i:s\Z'),
                'project' => '',
                'summary' => [
                    'components' => 0,
                    'pass' => 0,
                    'warn' => 0,
                    'fail' => 0,
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
