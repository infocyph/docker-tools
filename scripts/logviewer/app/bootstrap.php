<?php

declare(strict_types=1);

ini_set('display_errors', '0');
error_reporting(E_ALL);

$LOGVIEW_DEBUG = (bool)(getenv('LOGVIEW_DEBUG') ?: false);

$LOGVIEW_ROOTS = array_values(
  array_filter(
    array_map('trim', explode(':', getenv('LOGVIEW_ROOTS') ?: '/global/log')),
  ),
);

$LOGVIEW_MAX_TAIL_LINES = max(
  2000,
  (int)(getenv('LOGVIEW_MAX_TAIL_LINES') ?: 25000),
);

$LOGVIEW_CACHE_TTL = max(1, (int)(getenv('LOGVIEW_CACHE_TTL') ?: 2));
$NGINX_VHOST_DIR = getenv('NGINX_VHOST_DIR') ?: '/etc/share/vhosts/nginx';

function json_out(array $data, int $code = 200): never
{
    http_response_code($code);
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store');
    echo json_encode($data, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
    exit;
}

function serve_asset(string $relPath): never
{
    $base = realpath(__DIR__ . '/../public');
    $full = realpath(__DIR__ . '/../public/' . ltrim($relPath, '/'));

    if (
      $base === false
      || $full === false
      || !str_starts_with($full, $base)
      || !is_file($full)
    ) {
        http_response_code(404);
        exit;
    }

    $ext = strtolower(pathinfo($full, PATHINFO_EXTENSION));
    $map = [
      'css'  => 'text/css; charset=utf-8',
      'js'   => 'application/javascript; charset=utf-8',
      'png'  => 'image/png',
      'jpg'  => 'image/jpeg',
      'jpeg' => 'image/jpeg',
      'svg'  => 'image/svg+xml',
      'ico'  => 'image/x-icon',
    ];

    header('Content-Type: ' . ($map[$ext] ?? 'application/octet-stream'));
    header('Cache-Control: public, max-age=3600');
    readfile($full);
    exit;
}

function is_under_roots(string $real, array $roots): bool
{
    foreach ($roots as $r) {
        $rr = realpath($r);
        if ($rr === false) {
            continue;
        }
        $rr = rtrim($rr, DIRECTORY_SEPARATOR) . DIRECTORY_SEPARATOR;
        if (str_starts_with($real, $rr)) {
            return true;
        }
    }
    return false;
}

function resolve_file(string $input, array $roots): string
{
    $input = trim($input);
    if ($input === '') {
        json_out(['ok' => false, 'error' => 'missing file'], 400);
    }

    $candidate = $input;
    if (!str_starts_with($candidate, '/')) {
        $base = $roots[0] ?? '/global/log';
        $candidate = rtrim($base, '/') . '/' . ltrim($candidate, '/');
    }

    $real = realpath($candidate);
    if ($real === false || !is_file($real)) {
        json_out(['ok' => false, 'error' => 'file not found'], 404);
    }
    if (!is_under_roots($real, $roots)) {
        json_out(['ok' => false, 'error' => 'not allowed'], 403);
    }
    return $real;
}

function sh(array $cmd, int $timeout = 8): array
{
    $des = [1 => ['pipe', 'w'], 2 => ['pipe', 'w']];
    $p = @proc_open($cmd, $des, $pipes, null, null);

    if (!is_resource($p)) {
        return [1, '', 'proc_open failed'];
    }

    stream_set_blocking($pipes[1], true);
    stream_set_blocking($pipes[2], true);

    $start = time();
    while (true) {
        $st = proc_get_status($p);
        if (!$st['running']) {
            break;
        }
        if ((time() - $start) > $timeout) {
            @proc_terminate($p);
            break;
        }
        usleep(50_000);
    }

    $out = stream_get_contents($pipes[1]) ?: '';
    $err = stream_get_contents($pipes[2]) ?: '';
    fclose($pipes[1]);
    fclose($pipes[2]);

    $code = proc_close($p);
    return [$code, $out, $err];
}

function sh_pipe(string $cmd, int $timeout = 10): array
{
    return sh(['/bin/sh', '-lc', $cmd], $timeout);
}

function is_gz(string $file): bool
{
    return str_ends_with(strtolower($file), '.gz');
}

function tail_text(string $file, int $lines): array
{
    $lines = max(10, $lines);

    if (is_gz($file)) {
        $cmd = 'gzip -dc -- ' . escapeshellarg($file) . ' | tail -n ' . (int)$lines;
        return sh_pipe($cmd, 12);
    }

    return sh(['tail', '-n', (string)$lines, $file], 8);
}

/**
 * Deep search across full file (works for .gz too).
 * Uses rg for consistent output. Exit code 1 = no matches.
 */
function grep_text(string $file, string $q, int $limit = 500): array
{
    $q = trim($q);
    if ($q === '') {
        return [0, '', 'missing q'];
    }

    $limit = max(50, min(5000, $limit));
    $rg = 'rg --no-heading --line-number --max-count ' . (int)$limit . ' -S -- ' . escapeshellarg($q);

    if (is_gz($file)) {
        $cmd = 'gzip -dc -- ' . escapeshellarg($file) . ' | ' . $rg;
        return sh_pipe($cmd, 15);
    }

    return sh_pipe($rg . ' ' . escapeshellarg($file), 12);
}

function list_files(array $roots): array
{
    $out = [];

    foreach ($roots as $root) {
        $rr = realpath($root);
        if ($rr === false || !is_dir($rr)) {
            continue;
        }

        $it = new RecursiveIteratorIterator(
          new RecursiveDirectoryIterator($rr, FilesystemIterator::SKIP_DOTS),
          RecursiveIteratorIterator::SELF_FIRST,
        );

        foreach ($it as $f) {
            if (!$f->isFile()) {
                continue;
            }

            $name = $f->getFilename();
            $path = $f->getPathname();

            $isLogLike =
              preg_match('~\.(log|out|err|txt)(\.gz)?$~i', $name) ||
              preg_match('~\.(access|error)(\.log)?(\.gz)?$~i', $name) ||
              (str_contains($name, 'access') || str_contains($name, 'error'));

            if (!$isLogLike) {
                continue;
            }

            $rel = ltrim(str_replace($rr, '', $path), DIRECTORY_SEPARATOR);
            $service = explode(DIRECTORY_SEPARATOR, $rel)[0] ?? 'logs';

            $out[] = [
              'service' => $service,
              'name'    => $name,
              'path'    => $path,
              'size'    => $f->getSize(),
              'mtime'   => $f->getMTime(),
              'gz'      => is_gz($path),
            ];
        }
    }

    usort(
      $out,
      static fn ($a, $b) => ($b['mtime'] <=> $a['mtime']) ?: ($b['size'] <=> $a['size']),
    );

    return $out;
}

function cache_key(string $file): string
{
    return '/tmp/logviewer_' . hash('sha256', $file) . '.json';
}

function parse_entries(string $text): array
{
    $lines = preg_split("/\r\n|\n|\r/", $text) ?: [];
    $entries = [];
    $cur = null;

    $flush = function () use (&$entries, &$cur): void {
        if (!$cur) {
            return;
        }
        $cur['body'] = rtrim($cur['body']);
        $entries[] = $cur;
        $cur = null;
    };

    foreach ($lines as $line) {
        if ($line === '') {
            continue;
        }

        // Laravel: [YYYY-MM-DD HH:MM:SS] env.LEVEL: message...
        if (preg_match(
          '~^\[(\d{4}-\d{2}-\d{2}) (\d{2}:\d{2}:\d{2})\]\s+([^.]+)\.([A-Z]+):\s*(.*)$~',
          $line,
          $m,
        )) {
            $flush();
            $lvl = strtolower($m[4]);
            $cur = [
              'ts'      => $m[1] . ' ' . $m[2],
              'level'   => $lvl,
              'summary' => $m[5] !== '' ? $m[5] : '(no message)',
              'body'    => $line . "\n",
            ];
            continue;
        }

        // Generic heuristics
        $isNew = false;
        $lvl = 'info';
        $ts = '';

        if (preg_match('~^\[(\d{2}-[A-Za-z]{3}-\d{4} \d{2}:\d{2}:\d{2})\]\s+([A-Z]+)\b~', $line, $m)) {
            $isNew = true;
            $ts = $m[1];
            $lvl = strtolower($m[2]);
        } elseif (preg_match('~^(\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2}).*\b(ERROR|WARN|WARNING|INFO|DEBUG)\b~i', $line, $m)) {
            $isNew = true;
            $ts = $m[1];
            $lvl = strtolower($m[2]);
            if ($lvl === 'warning') {
                $lvl = 'warn';
            }
        } elseif (preg_match('~\s(\d{3})\s~', $line, $m)) {
            $code = (int)$m[1];
            $isNew = true;
            if ($code >= 500) {
                $lvl = 'error';
            } elseif ($code >= 400) {
                $lvl = 'warn';
            } else {
                $lvl = 'info';
            }
        } elseif (preg_match('~\b(FATAL|CRITICAL)\b~i', $line)) {
            $isNew = true;
            $lvl = 'error';
        } elseif (preg_match('~\b(WARN|WARNING)\b~i', $line)) {
            $isNew = true;
            $lvl = 'warn';
        }

        if ($isNew) {
            $flush();
            $cur = [
              'ts'      => $ts,
              'level'   => $lvl,
              'summary' => mb_substr($line, 0, 220),
              'body'    => $line . "\n",
            ];
        } else {
            if (!$cur) {
                $cur = [
                  'ts'      => '',
                  'level'   => 'info',
                  'summary' => mb_substr($line, 0, 220),
                  'body'    => $line . "\n",
                ];
            } else {
                $cur['body'] .= $line . "\n";
            }
        }
    }

    $flush();

    // Fallback: never return empty when file has text (e.g., plain access logs)
    if (!$entries) {
        foreach ($lines as $line) {
            if ($line === '') {
                continue;
            }
            $entries[] = [
              'ts'      => '',
              'level'   => 'info',
              'summary' => mb_substr($line, 0, 220),
              'body'    => $line,
            ];
        }
    }

    return $entries;
}

function load_cached_entries(string $file, int $maxTail, int $ttl): array
{
    $ck = cache_key($file);

    if (is_file($ck)) {
        $st = @stat($ck);
        if ($st && (time() - (int)$st['mtime']) <= $ttl) {
            $raw = @file_get_contents($ck);
            if ($raw !== false) {
                $j = json_decode($raw, true);
                if (is_array($j) && isset($j['entries'], $j['meta'])) {
                    return $j;
                }
            }
        }
    }

    [$code, $out, $err] = tail_text($file, $maxTail);
    if ($code !== 0) {
        json_out(['ok' => false, 'error' => trim($err) ?: 'read failed'], 500);
    }

    $entries = parse_entries($out);

    $counts = ['debug' => 0, 'info' => 0, 'warn' => 0, 'error' => 0];
    foreach ($entries as $e) {
        $l = $e['level'] ?? 'info';
        if (!isset($counts[$l])) {
            $l = 'info';
        }
        $counts[$l]++;
    }

    $payload = [
      'meta' => [
        'file'         => $file,
        'gz'           => is_gz($file),
        'generated_at' => time(),
        'counts'       => $counts,
        'total'        => count($entries),
      ],
      'entries' => $entries,
    ];

    @file_put_contents(
      $ck,
      json_encode($payload, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE),
      LOCK_EX,
    );

    return $payload;
}

function nginx_domains_list(string $dir): array
{
    $d = realpath($dir);
    if ($d === false || !is_dir($d)) {
        return [];
    }

    $out = [];
    foreach (new DirectoryIterator($d) as $f) {
        if (!$f->isFile()) {
            continue;
        }
        $name = $f->getFilename();
        if (!preg_match('~\.conf$~i', $name)) {
            continue;
        }
        $out[] = preg_replace('~\.conf$~i', '', $name);
    }

    sort($out, SORT_NATURAL | SORT_FLAG_CASE);
    return $out;
}

function dashboard_log_stats(array $roots, int $ttl, int $maxFiles = 20): array
{
    // Lightweight: only sample most-recent files (maxFiles)
    $files = list_files($roots);
    $files = array_slice($files, 0, max(1, $maxFiles));

    $sum = ['debug' => 0, 'info' => 0, 'warn' => 0, 'error' => 0];
    $sampled = 0;
    $last = 0;

    $dashTail = max(2000, (int)(getenv('LOGVIEW_DASH_TAIL') ?: 5000));

    foreach ($files as $f) {
        $payload = load_cached_entries($f['path'], $dashTail, $ttl);
        $c = $payload['meta']['counts'] ?? [];
        foreach ($sum as $k => $_) {
            $sum[$k] += (int)($c[$k] ?? 0);
        }
        $last = max($last, (int)($payload['meta']['generated_at'] ?? 0));
        $sampled++;
    }

    return [
      'sampled_files'     => $sampled,
      'counts'            => $sum,
      'last_generated_at' => $last,
      'total_files'       => count(list_files($roots)),
    ];
}

function log_file_counts_by_dirname(array $roots): array
{
    $files = list_files($roots);

    $by = [];
    foreach ($files as $f) {
        $dir = trim((string)($f['service'] ?? 'logs'));
        if ($dir === '') {
            $dir = 'logs';
        }
        $by[$dir] = ($by[$dir] ?? 0) + 1;
    }

    ksort($by, SORT_NATURAL | SORT_FLAG_CASE);

    return [
      'total'  => count($files),
      'by_dir' => $by,
    ];
}
