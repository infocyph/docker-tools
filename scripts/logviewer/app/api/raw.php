<?php
declare(strict_types=1);

require_once __DIR__ . '/../bootstrap.php';

$file  = resolve_file((string)($_GET['file'] ?? ''), $LOGVIEW_ROOTS);
$lines = max(100, min(50000, (int)($_GET['lines'] ?? 2000)));

[$gzCap, $rgCap, $tailCap] = lv_caps();

$maxBytes = max(1024 * 1024, min(128 * 1024 * 1024, (int)($_GET['maxBytes'] ?? $tailCap)));

[$code, $out, $err] = tail_text($file, $lines);

if ($code !== 0) {
    json_out(['ok' => false, 'error' => trim($err) ?: 'read failed'], 500);
}

if (strlen($out) > $maxBytes) {
    $out = substr($out, -$maxBytes);
}

header('Content-Type: text/plain; charset=utf-8');
header('Cache-Control: no-store');
header('X-Content-Type-Options: nosniff');
header('X-Log-File-Size: ' . filesize($file));

echo $out;
exit;