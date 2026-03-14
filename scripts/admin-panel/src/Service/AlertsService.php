<?php
declare(strict_types=1);

namespace AdminPanel\Service;

final class AlertsService
{
    /**
     * @return array<string,mixed>
     */
    public function collect(bool $run = false, string $ackRule = '', string $ackFingerprint = ''): array
    {
        $ackRule = trim($ackRule);
        $ackFingerprint = trim($ackFingerprint);

        $cmd = ['monitor-alerts', '--json'];
        if ($run) {
            $cmd[] = '--run';
        }
        if ($ackRule !== '') {
            $cmd[] = '--ack';
            $cmd[] = $ackRule;
            if ($ackFingerprint !== '') {
                $cmd[] = '--fingerprint';
                $cmd[] = $ackFingerprint;
            }
        }

        $res = $this->runCommand($cmd);
        if (!$res['ok']) {
            return [
                'ok' => false,
                'error' => 'alerts_command_failed',
                'message' => $res['stderr'] !== '' ? $res['stderr'] : 'monitor-alerts --json failed',
                'generated_at' => gmdate('Y-m-d\TH:i:s\Z'),
                'mode' => ['json' => true, 'run' => $run],
                'summary' => [
                    'rules' => 0,
                    'firing' => 0,
                    'sent' => 0,
                    'suppressed' => 0,
                    'acked' => 0,
                ],
                'incidents' => [],
            ];
        }

        $decoded = json_decode($res['stdout'], true);
        if (!is_array($decoded)) {
            return [
                'ok' => false,
                'error' => 'invalid_alerts_json',
                'message' => 'monitor-alerts --json returned malformed JSON.',
                'generated_at' => gmdate('Y-m-d\TH:i:s\Z'),
                'mode' => ['json' => true, 'run' => $run],
                'summary' => [
                    'rules' => 0,
                    'firing' => 0,
                    'sent' => 0,
                    'suppressed' => 0,
                    'acked' => 0,
                ],
                'incidents' => [],
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
