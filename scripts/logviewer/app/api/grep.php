<?php

declare(strict_types=1);
require_once __DIR__ . '/../bootstrap.php';

$file = resolve_file((string)($_GET['file'] ?? ''), $LOGVIEW_ROOTS);
$q = (string)($_GET['q'] ?? '');
$limit = (int)($_GET['limit'] ?? 500);

[$code, $out, $err] = grep_text($file, $q, $limit);

// rg returns 1 for no matches
if ($code !== 0 && $code !== 1) {
    json_out(['ok' => false, 'error' => trim($err) ?: 'rg failed'], 500);
}

json_out(['ok' => true, 'file' => $file, 'q' => trim($q), 'text' => $out]);
