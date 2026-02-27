<?php
declare(strict_types=1);

require_once __DIR__ . '/../bootstrap.php';

$file  = resolve_file((string)($_GET['file'] ?? ''), $LOGVIEW_ROOTS);
$q     = trim((string)($_GET['q'] ?? ''));
$limit = max(50, min(5000, (int)($_GET['limit'] ?? 500)));

if ($q === '') {
    json_out(['ok' => false, 'error' => 'missing q'], 400);
}

if (mb_strlen($q) > 200) {
    json_out(['ok' => false, 'error' => 'query too long'], 400);
}

/**
 * Simple per-IP rate limit: max 12 requests / 10 seconds
 */
$ip = (string)($_SERVER['REMOTE_ADDR'] ?? 'unknown');
$rk = '/tmp/logviewer_rl_' . hash('sha256', 'grep|' . $ip) . '.json';
$now = time();
$win = 10;
$max = 12;

$rl = ['t' => $now, 'n' => 0];
if (is_file($rk)) {
    $raw = @file_get_contents($rk);
    $j = is_string($raw) ? json_decode($raw, true) : null;
    if (is_array($j) && isset($j['t'], $j['n'])) {
        $rl['t'] = (int)$j['t'];
        $rl['n'] = (int)$j['n'];
    }
}
if (($now - $rl['t']) >= $win) {
    $rl = ['t' => $now, 'n' => 0];
}
$rl['n']++;
@file_put_contents($rk, json_encode($rl), LOCK_EX);

if ($rl['n'] > $max) {
    json_out(['ok' => false, 'error' => 'rate limited'], 429);
}

if (filesize($file) > 512 * 1024 * 1024) {
    json_out(['ok' => false, 'error' => 'file too large for grep'], 400);
}

[$code, $out, $err] = grep_text($file, $q, $limit);

if ($code !== 0 && $code !== 1) {
    json_out(['ok' => false, 'error' => trim($err) ?: 'rg failed'], 500);
}

// ✅ cap returned bytes (avoid browser freeze)
$capBytes = 1_500_000; // ~1.5MB
if (strlen($out) > $capBytes) {
    $out = substr($out, 0, $capBytes) . "\n\n[...output truncated...]\n";
}

json_out([
  'ok'   => true,
  'file' => $file,
  'q'    => $q,
  'text' => $out,
]);
