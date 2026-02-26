<?php

declare(strict_types=1);
require_once __DIR__ . '/../bootstrap.php';

$file = resolve_file((string)($_GET['file'] ?? ''), $LOGVIEW_ROOTS);
$lines = max(100, min(50000, (int)($_GET['lines'] ?? 2000)));

[$code, $out, $err] = tail_text($file, $lines);
if ($code !== 0) {
    json_out(['ok' => false, 'error' => trim($err) ?: 'read failed'], 500);
}

header('Content-Type: text/plain; charset=utf-8');
header('Cache-Control: no-store');
echo $out;
exit;