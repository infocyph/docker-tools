<?php
declare(strict_types=1);

namespace AdminPanel\Service;

final class VolumeMonitorService
{
    /**
     * @return array<string,mixed>
     */
    public function collect(int $top = 20, int $inodeTop = 8): array
    {
        $top = max(1, min(200, $top));
        $inodeTop = max(0, min(30, $inodeTop));

        $cmd = [
            'monitor-volumes',
            '--json',
            '--top',
            (string)$top,
            '--inode-top',
            (string)$inodeTop,
        ];

        $res = $this->runCommand($cmd);
        if (!$res['ok']) {
            return [
                'ok' => false,
                'error' => 'volume_monitor_command_failed',
                'message' => $res['stderr'] !== '' ? $res['stderr'] : 'monitor-volumes --json failed',
                'generated_at' => gmdate('Y-m-d\TH:i:s\Z'),
                'project' => '',
                'filters' => [
                    'top' => $top,
                    'inode_top' => $inodeTop,
                ],
                'summary' => [
                    'volumes' => 0,
                    'pass' => 0,
                    'warn' => 0,
                    'fail' => 0,
                    'inode_scanned' => 0,
                    'docker_root_free_bytes' => -1,
                ],
                'items' => [],
            ];
        }

        $decoded = json_decode($res['stdout'], true);
        if (!is_array($decoded)) {
            return [
                'ok' => false,
                'error' => 'invalid_volume_monitor_json',
                'message' => 'monitor-volumes --json returned malformed JSON.',
                'generated_at' => gmdate('Y-m-d\TH:i:s\Z'),
                'project' => '',
                'filters' => [
                    'top' => $top,
                    'inode_top' => $inodeTop,
                ],
                'summary' => [
                    'volumes' => 0,
                    'pass' => 0,
                    'warn' => 0,
                    'fail' => 0,
                    'inode_scanned' => 0,
                    'docker_root_free_bytes' => -1,
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
