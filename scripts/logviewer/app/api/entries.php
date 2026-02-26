<?php
declare(strict_types=1);

require_once __DIR__ . '/../bootstrap.php';

$file = resolve_file((string)($_GET['file'] ?? ''), $LOGVIEW_ROOTS);
$page = max(1, (int)($_GET['page'] ?? 1));
$per  = max(10, min(200, (int)($_GET['per'] ?? 25)));

$level = strtolower(trim((string)($_GET['level'] ?? '')));
$q     = trim((string)($_GET['q'] ?? ''));

$data = load_cached_entries($file, $LOGVIEW_MAX_TAIL_LINES, $LOGVIEW_CACHE_TTL);
$entries = array_reverse($data['entries']); // newest first

// Level filter
if ($level !== '' && in_array($level, ['debug','info','warn','error'], true)) {
    $entries = array_values(array_filter($entries, function ($e) use ($level) {
        $l = strtolower((string)($e['level'] ?? 'info'));
        if ($l === 'warning') $l = 'warn';
        return $l === $level;
    }));
}

// Text search
if ($q !== '') {
    $qq = mb_strtolower($q);
    $entries = array_values(array_filter($entries, function ($e) use ($qq) {
        return str_contains(mb_strtolower((string)($e['summary'] ?? '')), $qq)
          || str_contains(mb_strtolower((string)($e['body'] ?? '')), $qq);
    }));
}

$total = count($entries);
$pages = max(1, (int)ceil($total / $per));
$page  = min($page, $pages);

$offset = ($page - 1) * $per;
$slice  = array_slice($entries, $offset, $per);

json_out([
  'ok'    => true,
  'meta'  => $data['meta'],
  'page'  => $page,
  'per'   => $per,
  'pages' => $pages,
  'total' => $total,
  'items' => $slice,
]);