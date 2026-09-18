<?php
declare(strict_types=1);

namespace AdminPanel\Support;

final class ProcessRunner
{
    private const DEFAULT_MAX_OUTPUT_BYTES = 1048576;

    /**
     * @param list<string> $command
     * @return array{ok:bool,stdout:string,stderr:string,exit_code:int,timed_out?:bool,output_limited?:bool}
     */
    public static function run(array $command, int $timeoutSeconds = 20, ?string $stdin = null, int $maxOutputBytes = self::DEFAULT_MAX_OUTPUT_BYTES): array
    {
        if (!function_exists('proc_open')) {
            return [
                'ok' => false,
                'stdout' => '',
                'stderr' => 'proc_open unavailable',
                'exit_code' => 127,
            ];
        }

        if ($command === [] || array_filter($command, static fn(mixed $part): bool => !is_string($part)) !== []) {
            return [
                'ok' => false,
                'stdout' => '',
                'stderr' => 'invalid command',
                'exit_code' => 127,
            ];
        }

        $timeoutSeconds = max(1, $timeoutSeconds);
        $maxOutputBytes = max(4096, min(16777216, $maxOutputBytes));
        $descriptors = [
            0 => ['pipe', 'r'],
            1 => ['pipe', 'w'],
            2 => ['pipe', 'w'],
        ];

        $proc = @proc_open($command, $descriptors, $pipes, null, null, ['bypass_shell' => true]);
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
        $outputLimited = false;
        $observedExitCode = null;
        $deadline = microtime(true) + $timeoutSeconds;

        @stream_set_blocking($pipes[1], false);
        @stream_set_blocking($pipes[2], false);

        $append = static function (string &$buffer, string $chunk, int $limit, bool &$limited): void {
            if ($chunk === '' || $limited) {
                return;
            }
            $remaining = $limit - strlen($buffer);
            if ($remaining <= 0) {
                $limited = true;
                return;
            }
            if (strlen($chunk) > $remaining) {
                $buffer .= substr($chunk, 0, $remaining);
                $limited = true;
                return;
            }
            $buffer .= $chunk;
        };

        while (true) {
            $outChunk = stream_get_contents($pipes[1]);
            if (is_string($outChunk)) {
                $append($stdout, $outChunk, $maxOutputBytes, $outputLimited);
            }

            $errChunk = stream_get_contents($pipes[2]);
            if (is_string($errChunk)) {
                $append($stderr, $errChunk, $maxOutputBytes, $outputLimited);
            }

            $status = proc_get_status($proc);
            $running = is_array($status) && (bool)($status['running'] ?? false);
            if (!$running) {
                if (is_array($status)) {
                    $reported = $status['exitcode'] ?? null;
                    if (is_int($reported) && $reported >= 0) {
                        $observedExitCode = $reported;
                    }
                }
                break;
            }

            if ($outputLimited) {
                @proc_terminate($proc);
                usleep(150000);
                $status = proc_get_status($proc);
                if (is_array($status) && (bool)($status['running'] ?? false)) {
                    @proc_terminate($proc, 9);
                }
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
        if (is_string($outChunk)) {
            $append($stdout, $outChunk, $maxOutputBytes, $outputLimited);
        }

        $errChunk = stream_get_contents($pipes[2]);
        if (is_string($errChunk)) {
            $append($stderr, $errChunk, $maxOutputBytes, $outputLimited);
        }

        fclose($pipes[1]);
        fclose($pipes[2]);
        $closedExitCode = (int)@proc_close($proc);
        $exitCode = $closedExitCode >= 0 ? $closedExitCode : ($observedExitCode ?? $closedExitCode);
        $stderr = trim($stderr);

        if ($outputLimited) {
            $message = 'command output exceeded ' . $maxOutputBytes . ' bytes';
            if ($stderr !== '') {
                $message .= '; ' . $stderr;
            }
            return [
                'ok' => false,
                'stdout' => $stdout,
                'stderr' => $message,
                'exit_code' => 125,
                'output_limited' => true,
            ];
        }

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
