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

$LOGVIEW_CACHE_TTL = max(1, (int)(getenv('LOGVIEW_CACHE_TTL') ?: 2));
$NGINX_VHOST_DIR = getenv('NGINX_VHOST_DIR') ?: '/etc/share/vhosts/nginx';

/**
 * Tail lines for parsing entries (NOT raw).
 * Keep moderate (parsing is heavier than raw tail).
 */
$LOGVIEW_MAX_TAIL_LINES = max(
  2000,
  (int)(getenv('LOGVIEW_MAX_TAIL_LINES') ?: 25000),
);

/**
 * Hard caps (dev-safe but not insane).
 */
$LOGVIEW_GZ_MAX_BYTES = (int)(getenv(
  'LOGVIEW_GZ_MAX_BYTES',
) ?: 0);     // if 0 => auto
$LOGVIEW_RG_MAX_BYTES = (int)(getenv(
  'LOGVIEW_RG_MAX_BYTES',
) ?: 0);     // if 0 => auto
$LOGVIEW_TAIL_MAX_BYTES = (int)(getenv(
  'LOGVIEW_TAIL_MAX_BYTES',
) ?: 0);   // if 0 => auto

function lv_mem_available_bytes(): int
{
    // Prefer MemAvailable from /proc/meminfo (Linux containers)
    $p = '/proc/meminfo';
    if (is_readable($p)) {
        $txt = @file_get_contents($p);
        if ($txt !== false && preg_match(
            '~^MemAvailable:\s+(\d+)\s+kB~mi',
            $txt,
            $m,
          )) {
            return (int)$m[1] * 1024;
        }
    }

    // Fallback: memory_limit
    $ml = ini_get('memory_limit');
    if (!$ml || $ml === '-1') {
        return 256 * 1024 * 1024; // assume 256MB if unlimited/unknown
    }
    $ml = trim((string)$ml);
    $unit = strtolower(substr($ml, -1));
    $num = (int)$ml;
    return match ($unit) {
        'g' => $num * 1024 * 1024 * 1024,
        'm' => $num * 1024 * 1024,
        'k' => $num * 1024,
        default => (int)$ml,
    };
}

function lv_auto_caps(): array
{
    $mem = lv_mem_available_bytes();

    // Very conservative fractions (dev-safe):
    // - gz: up to 10% of available, clamp 16–96MB
    // - rg output: up to 6% of available, clamp 1–32MB
    // - tail buffer: up to 8% of available, clamp 8–64MB
    $gz = max(16 * 1024 * 1024, min(96 * 1024 * 1024, (int)($mem * 0.10)));
    $rg = max(1 * 1024 * 1024, min(32 * 1024 * 1024, (int)($mem * 0.06)));
    $tail = max(8 * 1024 * 1024, min(64 * 1024 * 1024, (int)($mem * 0.08)));

    return [$gz, $rg, $tail];
}

function lv_caps(): array
{
    global $LOGVIEW_GZ_MAX_BYTES, $LOGVIEW_RG_MAX_BYTES, $LOGVIEW_TAIL_MAX_BYTES;

    [$gz, $rg, $tail] = lv_auto_caps();

    if ($LOGVIEW_GZ_MAX_BYTES > 0) {
        $gz = $LOGVIEW_GZ_MAX_BYTES;
    }
    if ($LOGVIEW_RG_MAX_BYTES > 0) {
        $rg = $LOGVIEW_RG_MAX_BYTES;
    }
    if ($LOGVIEW_TAIL_MAX_BYTES > 0) {
        $tail = $LOGVIEW_TAIL_MAX_BYTES;
    }

    return [$gz, $rg, $tail];
}

function lv_security_headers(bool $isJson = true): void
{
    header('Cache-Control: no-store');
    header('X-Content-Type-Options: nosniff');
    header('Referrer-Policy: no-referrer');
    header('X-Frame-Options: SAMEORIGIN');
    header('Permissions-Policy: interest-cohort=()');

    if ($isJson) {
        header('Content-Type: application/json; charset=utf-8');
    }
}

function json_out(array $data, int $code = 200): never
{
    http_response_code($code);
    lv_security_headers(true);
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
      'css' => 'text/css; charset=utf-8',
      'js' => 'application/javascript; charset=utf-8',
      'png' => 'image/png',
      'jpg' => 'image/jpeg',
      'jpeg' => 'image/jpeg',
      'svg' => 'image/svg+xml',
      'ico' => 'image/x-icon',
    ];

    header('Content-Type: ' . ($map[$ext] ?? 'application/octet-stream'));
    header('Cache-Control: public, max-age=3600');
    header('X-Content-Type-Options: nosniff');
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

/**
 * PHP-native tail for plain files (fast + dependency-free).
 */
function tail_plain_php(string $file, int $lines): array
{
    [$gzCap, $rgCap, $tailCap] = lv_caps();

    $lines = max(10, $lines);

    $fp = @fopen($file, 'rb');
    if (!$fp) {
        return [1, '', 'fopen failed'];
    }

    if (fseek($fp, 0, SEEK_END) !== 0) {
        fclose($fp);
        return [1, '', 'fseek failed'];
    }

    $pos = ftell($fp);
    if ($pos === false) {
        fclose($fp);
        return [1, '', 'ftell failed'];
    }

    $buf = '';
    $chunk = 8192;

    while ($pos > 0 && substr_count($buf, "\n") < ($lines + 1)) {
        $read = ($pos >= $chunk) ? $chunk : $pos;
        $pos -= $read;

        if (fseek($fp, $pos, SEEK_SET) !== 0) {
            break;
        }

        $data = fread($fp, $read);
        if ($data === false || $data === '') {
            break;
        }

        $buf = $data . $buf;

        if (strlen($buf) > $tailCap) {
            break;
        } // dynamic safety cap
    }

    fclose($fp);

    $all = preg_split("/\r\n|\n|\r/", $buf) ?: [];
    $slice = array_slice($all, -$lines);
    return [0, implode("\n", $slice), ''];
}

/**
 * Tail last N lines.
 * - .gz: stream decompress with cap
 * - plain: PHP tail
 */
function tail_text(string $file, int $lines): array
{
    [$gzCap, $rgCap, $tailCap] = lv_caps();
    $lines = max(10, $lines);

    if (is_gz($file)) {
        $h = @gzopen($file, 'rb');
        if (!$h) {
            return [1, '', 'gzopen failed'];
        }

        $content = '';
        while (!gzeof($h)) {
            $content .= gzread($h, 8192);
            if (strlen($content) > $gzCap) {
                break;
            } // dynamic cap
        }
        gzclose($h);

        $all = preg_split("/\r\n|\n|\r/", $content) ?: [];
        $slice = array_slice($all, -$lines);
        return [0, implode("\n", $slice), ''];
    }

    return tail_plain_php($file, $lines);
}

/**
 * Deep search across full file (works for .gz too).
 * Exit code 1 = no matches.
 * Output is byte-capped to avoid browser/memory pain.
 */
function grep_text(string $file, string $q, int $limit = 500): array
{
    [$gzCap, $rgCap, $tailCap] = lv_caps();

    $q = trim($q);
    if ($q === '') {
        return [0, '', 'missing q'];
    }

    $limit = max(50, min(5000, $limit));
    $rg = 'rg --no-heading --line-number --max-count ' . (int)$limit . ' -S -- ' . escapeshellarg(
        $q,
      );

    // Byte cap (lines can be enormous)
    $capCmd = ' | head -c ' . (int)$rgCap;

    if (is_gz($file)) {
        $cmd = 'gzip -dc -- ' . escapeshellarg($file) . ' | ' . $rg . $capCmd;
        return sh_pipe($cmd, 20);
    }

    return sh_pipe($rg . ' ' . escapeshellarg($file) . $capCmd, 15);
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
              'name' => $name,
              'path' => $path,
              'size' => $f->getSize(),
              'mtime' => $f->getMTime(),
              'gz' => is_gz($path),
            ];
        }
    }

    usort(
      $out,
      static fn(
        $a,
        $b,
      ) => ($b['mtime'] <=> $a['mtime']) ?: ($b['size'] <=> $a['size']),
    );

    return $out;
}

function cache_key(string $file): string
{
    return '/tmp/logviewer_' . hash('sha256', $file) . '.json';
}

/**
 * Parse into entries:
 * - JSON line logs (level/message/timestamp common patterns)
 * - Access logs (status-based)
 * - Laravel grouped
 * - Generic grouped
 */
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

        // 0) JSON logs (one line = one entry)
        // Common shapes:
        // {"level":"error","message":"...","timestamp":"..."} OR {"severity":"WARN",...}
        if ($line !== '' && $line[0] === '{') {
            $j = json_decode($line, true);
            if (is_array($j)) {
                $lvlRaw = (string)($j['level'] ?? $j['severity'] ?? $j['lvl'] ?? $j['log_level'] ?? '');
                $msg = (string)($j['message'] ?? $j['msg'] ?? $j['event'] ?? $j['error'] ?? '');
                $ts = (string)($j['timestamp'] ?? $j['time'] ?? $j['datetime'] ?? $j['ts'] ?? '');

                $lvl = strtolower(trim($lvlRaw));
                if ($lvl === 'warning') {
                    $lvl = 'warn';
                }
                if ($lvl === 'critical' || $lvl === 'fatal') {
                    $lvl = 'error';
                }
                if (!in_array($lvl, ['debug', 'info', 'warn', 'error'], true)) {
                    // nginx json access: status present
                    if (isset($j['status']) && is_numeric($j['status'])) {
                        $code = (int)$j['status'];
                        $lvl = ($code >= 500) ? 'error' : (($code >= 400) ? 'warn' : 'info');
                    } else {
                        $lvl = 'info';
                    }
                }

                $summary = $msg !== '' ? $msg : mb_substr($line, 0, 220);

                $flush();
                $entries[] = [
                  'ts' => $ts,
                  'level' => $lvl,
                  'summary' => $summary,
                  'body' => $line,
                ];
                continue;
            }
        }

        // 1) Access log detectors
        if (preg_match('~"\s*[A-Z]+\s+[^"]+"\s+(\d{3})\b~', $line, $m)) {
            $code = (int)$m[1];
            $lvl = ($code >= 500) ? 'error' : (($code >= 400) ? 'warn' : 'info');

            $flush();
            $entries[] = [
              'ts' => '',
              'level' => $lvl,
              'summary' => mb_substr($line, 0, 220),
              'body' => $line,
            ];
            continue;
        }

        if (
          preg_match('~\b(1\d{2}|2\d{2}|3\d{2}|4\d{2}|5\d{2})\b~', $line, $m)
          && (preg_match(
              '~\b(GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS)\b~',
              $line,
            ) || str_contains($line, 'HTTP/'))
        ) {
            $code = (int)$m[1];
            $lvl = ($code >= 500) ? 'error' : (($code >= 400) ? 'warn' : 'info');

            $flush();
            $entries[] = [
              'ts' => '',
              'level' => $lvl,
              'summary' => mb_substr($line, 0, 220),
              'body' => $line,
            ];
            continue;
        }

        // 2) Laravel
        if (preg_match(
          '~^\[(\d{4}-\d{2}-\d{2}) (\d{2}:\d{2}:\d{2})\]\s+([^.]+)\.([A-Z]+):\s*(.*)$~',
          $line,
          $m,
        )) {
            $flush();
            $lvl = strtolower($m[4]);
            if ($lvl === 'warning') {
                $lvl = 'warn';
            }

            $cur = [
              'ts' => $m[1] . ' ' . $m[2],
              'level' => $lvl,
              'summary' => $m[5] !== '' ? $m[5] : '(no message)',
              'body' => $line . "\n",
            ];
            continue;
        }

        // 3) Generic grouping
        $isNew = false;
        $lvl = 'info';
        $ts = '';

        if (preg_match(
          '~^\[(\d{2}-[A-Za-z]{3}-\d{4} \d{2}:\d{2}:\d{2})\]\s+([A-Z]+)\b~',
          $line,
          $m,
        )) {
            $isNew = true;
            $ts = $m[1];
            $lvl = strtolower($m[2]);
            if ($lvl === 'warning') {
                $lvl = 'warn';
            }
        } elseif (preg_match(
          '~^(\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2}).*\b(ERROR|WARN|WARNING|INFO|DEBUG)\b~i',
          $line,
          $m,
        )) {
            $isNew = true;
            $ts = $m[1];
            $lvl = strtolower($m[2]);
            if ($lvl === 'warning') {
                $lvl = 'warn';
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
              'ts' => $ts,
              'level' => $lvl,
              'summary' => mb_substr($line, 0, 220),
              'body' => $line . "\n",
            ];
        } else {
            if (!$cur) {
                $cur = [
                  'ts' => '',
                  'level' => 'info',
                  'summary' => mb_substr($line, 0, 220),
                  'body' => $line . "\n",
                ];
            } else {
                $cur['body'] .= $line . "\n";
            }
        }
    }

    $flush();

    if (!$entries) {
        foreach ($lines as $line) {
            if ($line === '') {
                continue;
            }
            $entries[] = [
              'ts' => '',
              'level' => 'info',
              'summary' => mb_substr($line, 0, 220),
              'body' => $line,
            ];
        }
    }

    return $entries;
}

function lv_counts(array $entries): array
{
    $counts = ['debug' => 0, 'info' => 0, 'warn' => 0, 'error' => 0];
    foreach ($entries as $e) {
        $l = (string)($e['level'] ?? 'info');
        if ($l === 'warning') {
            $l = 'warn';
        }
        if (!isset($counts[$l])) {
            $l = 'info';
        }
        $counts[$l]++;
    }
    return $counts;
}

/**
 * Incremental cache update (plain files only):
 * - If file grew and growth is small, read only appended bytes and parse+merge.
 * - Always trims to last $maxTail entries (keeps UI fast).
 */
function load_cached_entries(string $file, int $maxTailLines, int $ttl): array
{
    $ck = cache_key($file);

    $stFile = @stat($file);
    $fileSize = (is_array(
        $stFile,
      ) && isset($stFile['size'])) ? (int)$stFile['size'] : 0;
    $fileMtime = (is_array(
        $stFile,
      ) && isset($stFile['mtime'])) ? (int)$stFile['mtime'] : 0;

    $cached = null;

    if (is_file($ck)) {
        $raw = @file_get_contents($ck);
        if ($raw !== false) {
            $j = json_decode($raw, true);
            if (is_array($j) && isset($j['entries'], $j['meta']) && is_array(
                $j['entries'],
              )) {
                $cached = $j;
            }
        }
    }

    // Fast return if cache is fresh and matches file state
    if ($cached) {
        $cm = $cached['meta'] ?? [];
        $cSize = (int)($cm['size'] ?? -1);
        $cMtime = (int)($cm['mtime'] ?? -1);
        $cGen = (int)($cm['generated_at'] ?? 0);
        $cTotal = (int)($cm['total'] ?? 0);

        $fresh = (time() - $cGen) <= $ttl;
        $matches = ($cSize === $fileSize && $cMtime === $fileMtime);
        $notBadEmpty = !($fileSize > 0 && $cTotal === 0);

        if ($fresh && $matches && $notBadEmpty) {
            return $cached;
        }

        // Incremental update only for plain files that grew
        if (!is_gz(
            $file,
          ) && $fileSize >= 0 && $cSize >= 0 && $fileSize > $cSize) {
            $delta = $fileSize - $cSize;

            // Only do incremental if growth is "small enough" (8MB cap)
            if ($delta <= 8 * 1024 * 1024) {
                $fp = @fopen($file, 'rb');
                if ($fp) {
                    if (@fseek($fp, $cSize, SEEK_SET) === 0) {
                        $append = '';
                        while (!feof($fp)) {
                            $chunk = fread($fp, 8192);
                            if ($chunk === false || $chunk === '') {
                                break;
                            }
                            $append .= $chunk;
                            if (strlen($append) > (10 * 1024 * 1024)) {
                                break;
                            }
                        }
                        fclose($fp);

                        if ($append !== '') {
                            $newEntries = parse_entries($append);
                            $merged = array_merge(
                              $cached['entries'],
                              $newEntries,
                            );

                            // Keep last N entries (based on tail lines)
                            if (count($merged) > $maxTailLines) {
                                $merged = array_slice($merged, -$maxTailLines);
                            }

                            $payload = [
                              'meta' => [
                                'file' => $file,
                                'gz' => false,
                                'generated_at' => time(),
                                'counts' => lv_counts($merged),
                                'total' => count($merged),
                                'size' => $fileSize,
                                'mtime' => $fileMtime,
                              ],
                              'entries' => $merged,
                            ];

                            @file_put_contents(
                              $ck,
                              json_encode(
                                $payload,
                                JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE,
                              ),
                              LOCK_EX,
                            );

                            return $payload;
                        }
                    } else {
                        fclose($fp);
                    }
                }
            }
        }
    }

    // Full rebuild (tail + parse)
    [$code, $out, $err] = tail_text($file, $maxTailLines);
    if ($code !== 0) {
        json_out(['ok' => false, 'error' => trim($err) ?: 'read failed'], 500);
    }

    $entries = parse_entries($out);

    $payload = [
      'meta' => [
        'file' => $file,
        'gz' => is_gz($file),
        'generated_at' => time(),
        'counts' => lv_counts($entries),
        'total' => count($entries),
        'size' => $fileSize,
        'mtime' => $fileMtime,
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
      'total' => count($files),
      'by_dir' => $by,
    ];
}
