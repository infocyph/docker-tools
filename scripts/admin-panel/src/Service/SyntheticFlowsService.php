<?php
declare(strict_types=1);

namespace AdminPanel\Service;

final class SyntheticFlowsService
{
    /**
     * @return array<string,mixed>
     */
    public function collect(string $domain = '', string $paths = '', int $timeout = 4): array
    {
        $domain = strtolower(trim($domain));
        $paths = trim($paths);
        $timeout = max(1, min(20, $timeout));

        $cmd = ['monitor-flows', '--json', '--timeout', (string)$timeout];
        if ($domain !== '') {
            $cmd[] = '--domain';
            $cmd[] = $domain;
        }
        if ($paths !== '') {
            $cmd[] = '--paths';
            $cmd[] = $paths;
        }

        $res = $this->runCommand($cmd);
        if (!$res['ok']) {
            return [
                'ok' => false,
                'error' => 'synthetic_flows_command_failed',
                'message' => $res['stderr'] !== '' ? $res['stderr'] : 'monitor-flows --json failed',
                'generated_at' => gmdate('Y-m-d\TH:i:s\Z'),
                'project' => '',
                'filters' => [
                    'domain' => $domain,
                    'paths' => $paths,
                    'timeout' => $timeout,
                ],
                'summary' => [
                    'domains' => 0,
                    'checks' => 0,
                    'pass' => 0,
                    'warn' => 0,
                    'fail' => 0,
                    'skip' => 0,
                    'avg_ms' => 0,
                    'p95_ms' => 0,
                ],
                'items' => [],
            ];
        }

        $decoded = json_decode($res['stdout'], true);
        if (!is_array($decoded)) {
            return [
                'ok' => false,
                'error' => 'invalid_synthetic_flows_json',
                'message' => 'monitor-flows --json returned malformed JSON.',
                'generated_at' => gmdate('Y-m-d\TH:i:s\Z'),
                'project' => '',
                'filters' => [
                    'domain' => $domain,
                    'paths' => $paths,
                    'timeout' => $timeout,
                ],
                'summary' => [
                    'domains' => 0,
                    'checks' => 0,
                    'pass' => 0,
                    'warn' => 0,
                    'fail' => 0,
                    'skip' => 0,
                    'avg_ms' => 0,
                    'p95_ms' => 0,
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
