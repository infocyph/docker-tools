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

if (filesize($file) > 512 * 1024 * 1024) {
    json_out(['ok' => false, 'error' => 'file too large for grep'], 400);
}

[$code, $out, $err] = grep_text($file, $q, $limit);

if ($code !== 0 && $code !== 1) {
    json_out(['ok' => false, 'error' => trim($err) ?: 'rg failed'], 500);
}

json_out([
  'ok'   => true,
  'file' => $file,
  'q'    => $q,
  'text' => $out,
]);