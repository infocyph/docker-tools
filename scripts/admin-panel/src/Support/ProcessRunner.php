<?php
declare(strict_types=1);

namespace AdminPanel\Support;

final class ProcessRunner
{
    /**
     * @param list<string> $command
     * @return array{ok:bool,stdout:string,stderr:string,exit_code:int,timed_out?:bool}
     */
    public static function run(array $command, int $timeoutSeconds = 20, ?string $stdin = null): array
    {
        if (!function_exists('proc_open')) {
            return [
                'ok' => false,
                'stdout' => '',
                'stderr' => 'proc_open unavailable',
                'exit_code' => 127,
            ];
        }

        $timeoutSeconds = max(1, $timeoutSeconds);
        $descriptors = [
            0 => ['pipe', 'r'],
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

        if ($stdin !== null) {
            fwrite($pipes[0], $stdin);
        }
        fclose($pipes[0]);

        $stdout = '';
        $stderr = '';
        $timedOut = false;
        $deadline = microtime(true) + $timeoutSeconds;

        @stream_set_blocking($pipes[1], false);
        @stream_set_blocking($pipes[2], false);

        while (true) {
            $outChunk = stream_get_contents($pipes[1]);
            if (is_string($outChunk) && $outChunk !== '') {
                $stdout .= $outChunk;
            }

            $errChunk = stream_get_contents($pipes[2]);
            if (is_string($errChunk) && $errChunk !== '') {
                $stderr .= $errChunk;
            }

            $status = proc_get_status($proc);
            $running = is_array($status) && (bool)($status['running'] ?? false);
            if (!$running) {
                break;
            }

            if (microtime(true) >= $deadline) {
                $timedOut = true;
                @proc_terminate($proc);
                usleep(150000);

                $status = proc_get_status($proc);
                if (is_array($status) && (bool)($status['running'] ?? false)) {
                    @proc_terminate($proc, 9);
                }
                break;
            }

            usleep(50000);
        }

        $outChunk = stream_get_contents($pipes[1]);
        if (is_string($outChunk) && $outChunk !== '') {
            $stdout .= $outChunk;
        }

        $errChunk = stream_get_contents($pipes[2]);
        if (is_string($errChunk) && $errChunk !== '') {
            $stderr .= $errChunk;
        }

        fclose($pipes[1]);
        fclose($pipes[2]);
        $exitCode = (int)@proc_close($proc);
        $stderr = trim($stderr);

        if ($timedOut) {
            $message = 'command timed out after ' . $timeoutSeconds . 's';
            if ($stderr !== '') {
                $message .= '; ' . $stderr;
            }
            return [
                'ok' => false,
                'stdout' => $stdout,
                'stderr' => $message,
                'exit_code' => 124,
                'timed_out' => true,
            ];
        }

        return [
            'ok' => ($exitCode === 0),
            'stdout' => $stdout,
            'stderr' => $stderr,
            'exit_code' => $exitCode,
        ];
    }
}
