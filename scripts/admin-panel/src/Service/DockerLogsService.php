<?php
declare(strict_types=1);

namespace AdminPanel\Service;

final class DockerLogsService
{
    /**
     * @return array{
     *   ok:bool,
     *   error?:string,
     *   message?:string,
     *   generated_at:string,
     *   project:string,
     *   filters:array{service:string,since:string,grep:string,tail:int},
     *   services_available:list<string>,
     *   groups:list<array{
     *     service:string,
     *     containers:list<array{name:string,state:string,health:string}>,
     *     lines:list<string>,
     *     line_count:int
     *   }>
     * }
     */
    public function collect(string $service = '', string $since = '', string $grep = '', int $tail = 80): array
    {
        $service = strtolower(trim($service));
        $since = trim($since);
        $grep = trim($grep);
        $tail = max(1, min(500, $tail));

        $cmd = ['status', '--docker-logs-json', '--tail', (string)$tail];
        if ($service !== '' && $service !== 'all') {
            $cmd[] = '--service';
            $cmd[] = $service;
        }
        if ($since !== '') {
            $cmd[] = '--since';
            $cmd[] = $since;
        }
        if ($grep !== '') {
            $cmd[] = '--grep';
            $cmd[] = $grep;
        }

        $res = $this->runCommand($cmd);
        if (!$res['ok']) {
            return [
                'ok' => false,
                'error' => 'docker_logs_command_failed',
                'message' => $res['stderr'] !== '' ? $res['stderr'] : 'status --docker-logs-json failed',
                'generated_at' => gmdate('Y-m-d\TH:i:s\Z'),
                'project' => '',
                'filters' => [
                    'service' => $service,
                    'since' => $since,
                    'grep' => $grep,
                    'tail' => $tail,
                ],
                'services_available' => [],
                'groups' => [],
            ];
        }

        $decoded = json_decode($res['stdout'], true);
        if (!is_array($decoded)) {
            return [
                'ok' => false,
                'error' => 'invalid_docker_logs_json',
                'message' => 'status --docker-logs-json returned malformed JSON.',
                'generated_at' => gmdate('Y-m-d\TH:i:s\Z'),
                'project' => '',
                'filters' => [
                    'service' => $service,
                    'since' => $since,
                    'grep' => $grep,
                    'tail' => $tail,
                ],
                'services_available' => [],
                'groups' => [],
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

