<?php
declare(strict_types=1);
require_once __DIR__ . '/../bootstrap.php';

$file = resolve_file((string)($_GET['file'] ?? ''), $LOGVIEW_ROOTS);
$lines = max(50, min(5000, (int)($_GET['lines'] ?? 400)));
$intervalMs = max(250, min(3000, (int)($_GET['intervalMs'] ?? 900)));

@set_time_limit(0);
@ini_set('output_buffering', 'off');
@ini_set('zlib.output_compression', '0');

header('Content-Type: text/event-stream; charset=utf-8');
header('Cache-Control: no-store');
header('X-Accel-Buffering: no'); // nginx proxy safety
header('X-Content-Type-Options: nosniff');

$lastHash = '';

while (true) {
    if (connection_aborted()) break;

    [$code, $out, $err] = tail_text($file, $lines);
    if ($code !== 0) {
        echo "event: error\n";
        echo "data: " . json_encode(['ok'=>false,'error'=>trim($err) ?: 'read failed'], JSON_UNESCAPED_SLASHES|JSON_UNESCAPED_UNICODE) . "\n\n";
        @ob_flush(); @flush();
        usleep($intervalMs * 1000);
        continue;
    }

    $h = hash('sha256', $out);
    if ($h !== $lastHash) {
        $lastHash = $h;
        echo "event: tail\n";
        echo "data: " . json_encode(['ok'=>true,'text'=>$out,'hash'=>$h,'ts'=>time()], JSON_UNESCAPED_SLASHES|JSON_UNESCAPED_UNICODE) . "\n\n";
        @ob_flush(); @flush();
    }

    usleep($intervalMs * 1000);
}
exit;
