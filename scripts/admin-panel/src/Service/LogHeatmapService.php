<?php
declare(strict_types=1);

namespace AdminPanel\Service;

final class LogHeatmapService
{
    /**
     * @return array<string,mixed>
     */
    public function collect(string $source = 'both', string $since = '24h', int $bucketMin = 15, int $top = 12, int $lineLimit = 1000): array
    {
        $source = strtolower(trim($source));
        if (!in_array($source, ['both', 'docker', 'file'], true)) {
            $source = 'both';
        }
        $since = trim($since);
        if ($since === '') {
            $since = '24h';
        }
        $bucketMin = max(1, min(120, $bucketMin));
        $top = max(1, min(100, $top));
        $lineLimit = max(100, min(5000, $lineLimit));

        $cmd = [
            'monitor-log-heatmap',
            '--json',
            '--source',
            $source,
            '--since',
            $since,
            '--bucket-min',
            (string)$bucketMin,
            '--top',
            (string)$top,
            '--line-limit',
            (string)$lineLimit,
        ];

        $res = $this->runCommand($cmd);
        if (!$res['ok']) {
            return [
                'ok' => false,
                'error' => 'log_heatmap_command_failed',
                'message' => $res['stderr'] !== '' ? $res['stderr'] : 'monitor-log-heatmap --json failed',
                'generated_at' => gmdate('Y-m-d\TH:i:s\Z'),
                'project' => '',
                'filters' => [
                    'source' => $source,
                    'since' => $since,
                    'bucket_min' => $bucketMin,
                    'top' => $top,
                    'line_limit' => $lineLimit,
                ],
                'summary' => [
                    'errors' => 0,
                    'services' => 0,
                    'buckets' => 0,
                    'top_signatures' => 0,
                ],
                'buckets' => [],
                'top_signatures' => [],
                'services' => [],
            ];
        }

        $decoded = json_decode($res['stdout'], true);
        if (!is_array($decoded)) {
            return [
                'ok' => false,
                'error' => 'invalid_log_heatmap_json',
                'message' => 'monitor-log-heatmap --json returned malformed JSON.',
                'generated_at' => gmdate('Y-m-d\TH:i:s\Z'),
                'project' => '',
                'filters' => [
                    'source' => $source,
                    'since' => $since,
                    'bucket_min' => $bucketMin,
                    'top' => $top,
                    'line_limit' => $lineLimit,
                ],
                'summary' => [
                    'errors' => 0,
                    'services' => 0,
                    'buckets' => 0,
                    'top_signatures' => 0,
                ],
                'buckets' => [],
                'top_signatures' => [],
                'services' => [],
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
