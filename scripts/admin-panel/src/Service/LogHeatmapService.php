<?php
declare(strict_types=1);

namespace AdminPanel\Service;

use AdminPanel\Support\ProcessRunner;

final class LogHeatmapService
{
    private const COMMAND_TIMEOUT_SECONDS = 20;

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
        return ProcessRunner::run($command, self::COMMAND_TIMEOUT_SECONDS);
    }
}
