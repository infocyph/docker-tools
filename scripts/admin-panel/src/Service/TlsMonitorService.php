<?php
declare(strict_types=1);

namespace AdminPanel\Service;

final class TlsMonitorService
{
    /**
     * @return array<string,mixed>
     */
    public function collect(string $domain = '', int $timeout = 4): array
    {
        $domain = strtolower(trim($domain));
        $timeout = max(1, min(20, $timeout));

        $binary = is_executable('/usr/local/bin/monitor-tls') ? '/usr/local/bin/monitor-tls' : 'monitor-tls';
        $cmd = [$binary, '--json', '--timeout', (string)$timeout];
        if ($domain !== '') {
            $cmd[] = '--domain';
            $cmd[] = $domain;
        }

        $res = $this->runCommand($cmd);
        if (!$res['ok']) {
            if ($res['stdout'] !== '') {
                $decodedOnError = json_decode($res['stdout'], true);
                if (is_array($decodedOnError)) {
                    return $decodedOnError;
                }
            }
            return [
                'ok' => false,
                'error' => 'tls_monitor_command_failed',
                'message' => $res['stderr'] !== '' ? $res['stderr'] : 'monitor-tls --json failed',
                'generated_at' => gmdate('Y-m-d\TH:i:s\Z'),
                'project' => '',
                'filters' => [
                    'domain' => $domain,
                    'timeout' => $timeout,
                ],
                'summary' => [
                    'hosts' => 0,
                    'pass' => 0,
                    'warn' => 0,
                    'fail' => 0,
                    'mtls_required' => 0,
                    'mtls_broken' => 0,
                    'expiring_14d' => 0,
                    'expired' => 0,
                ],
                'items' => [],
            ];
        }

        $decoded = json_decode($res['stdout'], true);
        if (!is_array($decoded)) {
            return [
                'ok' => false,
                'error' => 'invalid_tls_monitor_json',
                'message' => 'monitor-tls --json returned malformed JSON.',
                'generated_at' => gmdate('Y-m-d\TH:i:s\Z'),
                'project' => '',
                'filters' => [
                    'domain' => $domain,
                    'timeout' => $timeout,
                ],
                'summary' => [
                    'hosts' => 0,
                    'pass' => 0,
                    'warn' => 0,
                    'fail' => 0,
                    'mtls_required' => 0,
                    'mtls_broken' => 0,
                    'expiring_14d' => 0,
                    'expired' => 0,
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
