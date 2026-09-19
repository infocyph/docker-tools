<?php
declare(strict_types=1);

namespace AdminPanel\Service;

use AdminPanel\Support\ProcessRunner;

final class TlsMonitorService
{
    private const MIN_COMMAND_TIMEOUT_SECONDS = 30;
    private const MAX_COMMAND_TIMEOUT_SECONDS = 600;
    private const PROBES_PER_HOST = 5;
    private const COMMAND_OVERHEAD_SECONDS = 10;

    /**
     * @return array<string,mixed>
     */
    public function collect(string $domain = '', int $timeout = 4, int $retries = 2): array
    {
        $domain = strtolower(trim($domain));
        $timeout = max(1, min(20, $timeout));
        $retries = max(1, min(5, $retries));

        $binary = is_executable('/usr/local/bin/monitor-tls') ? '/usr/local/bin/monitor-tls' : 'monitor-tls';
        $cmd = [$binary, '--json', '--timeout', (string)$timeout, '--retries', (string)$retries];
        if ($domain !== '') {
            $cmd[] = '--domain';
            $cmd[] = $domain;
        }

        $commandTimeout = $this->commandTimeoutSeconds($domain, $timeout, $retries);
        $res = $this->runCommand($cmd, $commandTimeout);
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
                    'retries' => $retries,
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
                    'chain_unverified' => 0,
                    'policy_checked' => 0,
                    'policy_drift' => 0,
                    'tls_legacy' => 0,
                    'ocsp_missing' => 0,
                    'no_intermediate' => 0,
                    'alerts' => 0,
                    'state_changes' => 0,
                    'expiring_crossed' => 0,
                    'mtls_broken_crossed' => 0,
                ],
                'alerts' => [],
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
                    'retries' => $retries,
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
                    'chain_unverified' => 0,
                    'policy_checked' => 0,
                    'policy_drift' => 0,
                    'tls_legacy' => 0,
                    'ocsp_missing' => 0,
                    'no_intermediate' => 0,
                    'alerts' => 0,
                    'state_changes' => 0,
                    'expiring_crossed' => 0,
                    'mtls_broken_crossed' => 0,
                ],
                'alerts' => [],
                'items' => [],
            ];
        }

        return $decoded;
    }

    private function commandTimeoutSeconds(string $domain, int $timeout, int $retries): int
    {
        $hostCount = $this->estimatedHostCount($domain);
        $budget = self::COMMAND_OVERHEAD_SECONDS
            + ($hostCount * self::PROBES_PER_HOST * $timeout * $retries);

        return max(
            self::MIN_COMMAND_TIMEOUT_SECONDS,
            min(self::MAX_COMMAND_TIMEOUT_SECONDS, $budget)
        );
    }

    private function estimatedHostCount(string $domain): int
    {
        $nginxDir = trim((string)(getenv('TLS_MONITOR_NGINX_DIR') ?: '/etc/share/vhosts/nginx'));
        if ($nginxDir === '' || !is_dir($nginxDir)) {
            return 1;
        }

        $filter = strtolower(trim($domain));
        $files = glob(rtrim($nginxDir, DIRECTORY_SEPARATOR) . DIRECTORY_SEPARATOR . '*.conf') ?: [];
        $count = 0;
        foreach ($files as $file) {
            $candidate = strtolower((string)pathinfo($file, PATHINFO_FILENAME));
            if ($candidate === '') {
                continue;
            }
            if ($filter === '') {
                ++$count;
                continue;
            }
            if (str_contains($filter, '*') || str_contains($filter, '?')) {
                if (fnmatch($filter, $candidate)) {
                    ++$count;
                }
                continue;
            }
            if (str_contains($candidate, $filter)) {
                ++$count;
            }
        }

        return max(1, $count);
    }

    /**
     * @param list<string> $command
     * @return array{ok:bool,stdout:string,stderr:string,exit_code:int}
     */
    private function runCommand(array $command, int $timeoutSeconds): array
    {
        return ProcessRunner::run($command, $timeoutSeconds);
    }
}
