<?php
declare(strict_types=1);

function fail(string $message): never
{
    fwrite(STDERR, "admin-monitoring-smoke: {$message}\n");
    exit(1);
}

function removeTree(string $path): void
{
    if (!is_dir($path)) {
        return;
    }
    $items = scandir($path);
    if (!is_array($items)) {
        return;
    }
    foreach ($items as $item) {
        if ($item === '.' || $item === '..') {
            continue;
        }
        $candidate = $path . DIRECTORY_SEPARATOR . $item;
        if (is_dir($candidate)) {
            removeTree($candidate);
        } else {
            @unlink($candidate);
        }
    }
    @rmdir($path);
}

putenv('TZ=Asia/Dhaka');
require dirname(__DIR__) . '/admin-panel/app/bootstrap.php';

if (date_default_timezone_get() !== 'Asia/Dhaka') {
    fail('bootstrap did not apply TZ=Asia/Dhaka');
}

$tmp = sys_get_temp_dir() . '/docker-tools-admin-monitor-' . bin2hex(random_bytes(6));
$logRoot = $tmp . '/logs';
$vhostRoot = $tmp . '/vhosts';
@mkdir($logRoot . '/nginx', 0777, true);
@mkdir($vhostRoot, 0777, true);

try {
    $logPath = $logRoot . '/nginx/project.error.log';
    file_put_contents(
        $logPath,
        "2026-09-19 12:00:00 ERROR timezone-check\n"
        . "19/Sep/2026:12:30:00 +0600 ERROR access-timezone-check\n"
        . "2026-09-19T06:45:00Z ERROR iso-timezone-check\n"
    );

    $logs = new \AdminPanel\Service\LogsDataService([$logRoot]);
    $list = $logs->listFilesPayload();
    $token = (string)($list['activeToken'] ?? '');
    if ($token === '') {
        fail('log file token was not discovered');
    }

    $entries = $logs->entriesPayload($token);
    $rows = is_array($entries['rows'] ?? null) ? $entries['rows'] : [];
    if (count($rows) !== 3) {
        fail('expected three parsed log rows');
    }

    $epochsByMessage = [];
    foreach ($rows as $row) {
        if (!is_array($row)) {
            continue;
        }
        $epochsByMessage[(string)($row['description'] ?? '')] = (int)($row['timeTs'] ?? 0);
    }

    $expectedNaive = (new DateTimeImmutable(
        '2026-09-19 12:00:00',
        new DateTimeZone('Asia/Dhaka')
    ))->getTimestamp();
    if (($epochsByMessage['ERROR timezone-check'] ?? 0) !== $expectedNaive) {
        fail('timezone-naive file log timestamp was not interpreted in configured TZ');
    }

    $expectedAccess = (new DateTimeImmutable('2026-09-19T12:30:00+06:00'))->getTimestamp();
    if (($epochsByMessage['ERROR access-timezone-check'] ?? 0) !== $expectedAccess) {
        fail('offset-bearing access-log timestamp was not parsed correctly');
    }

    $expectedIso = (new DateTimeImmutable('2026-09-19T06:45:00Z'))->getTimestamp();
    if (($epochsByMessage['ERROR iso-timezone-check'] ?? 0) !== $expectedIso) {
        fail('offset-bearing ISO timestamp was not parsed correctly');
    }

    foreach (['one.localhost', 'two.localhost', 'three.localhost'] as $domain) {
        file_put_contents($vhostRoot . '/' . $domain . '.conf', "# test\n");
    }
    putenv('TLS_MONITOR_NGINX_DIR=' . $vhostRoot);

    $tls = new \AdminPanel\Service\TlsMonitorService();
    $method = new ReflectionMethod($tls, 'commandTimeoutSeconds');
    $method->setAccessible(true);

    $allBudget = (int)$method->invoke($tls, '', 4, 2);
    if ($allBudget !== 130) {
        fail('TLS timeout budget did not scale to three hosts (expected 130s)');
    }

    $singleBudget = (int)$method->invoke($tls, 'one.localhost', 4, 2);
    if ($singleBudget !== 50) {
        fail('TLS timeout budget did not narrow with a domain filter (expected 50s)');
    }
} finally {
    removeTree($tmp);
    putenv('TLS_MONITOR_NGINX_DIR');
}

fwrite(STDOUT, "admin-monitoring-smoke: ok\n");
