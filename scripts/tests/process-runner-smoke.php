<?php
declare(strict_types=1);

require __DIR__ . '/../admin-panel/app/bootstrap.php';

use AdminPanel\Support\ProcessRunner;

function fail(string $message): never
{
    fwrite(STDERR, "process-runner-smoke: {$message}\n");
    exit(1);
}

$ok = ProcessRunner::run([PHP_BINARY, '-r', 'fwrite(STDOUT, "ok");'], 5, null, 4096);
if (!($ok['ok'] ?? false) || ($ok['stdout'] ?? '') !== 'ok') {
    fail('basic command execution failed');
}

$limited = ProcessRunner::run([PHP_BINARY, '-r', 'fwrite(STDOUT, str_repeat("x", 16384));'], 5, null, 4096);
if (($limited['ok'] ?? true) || !($limited['output_limited'] ?? false) || ($limited['exit_code'] ?? 0) !== 125) {
    fail('output limit was not enforced');
}
if (strlen((string)($limited['stdout'] ?? '')) > 4096) {
    fail('captured stdout exceeded configured bound');
}

$timed = ProcessRunner::run([PHP_BINARY, '-r', 'sleep(3);'], 1, null, 4096);
if (($timed['ok'] ?? true) || !($timed['timed_out'] ?? false) || ($timed['exit_code'] ?? 0) !== 124) {
    fail('timeout was not enforced');
}

fwrite(STDOUT, "process-runner-smoke: ok\n");
