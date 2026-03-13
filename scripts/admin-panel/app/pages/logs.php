<?php
declare(strict_types=1);

$findFiles = static function (string $dir, int $minDepth, int $maxDepth): array {
    $dir = rtrim($dir, DIRECTORY_SEPARATOR);
    if ($dir === '' || !is_dir($dir)) {
        return [];
    }

    $minDepth = max(0, $minDepth);
    $maxDepth = max($minDepth, $maxDepth);

    $cmd = [
        'find',
        $dir,
        '-mindepth', (string)$minDepth,
        '-maxdepth', (string)$maxDepth,
        '-type', 'f',
        '-print0',
    ];

    $descriptors = [
        1 => ['pipe', 'w'],
        2 => ['pipe', 'w'],
    ];

    $proc = @proc_open($cmd, $descriptors, $pipes);
    if (\is_resource($proc)) {
        $out = stream_get_contents($pipes[1]) ?: '';
        fclose($pipes[1]);

        $stderr = stream_get_contents($pipes[2]) ?: '';
        fclose($pipes[2]);
        unset($stderr);

        @proc_close($proc);

        if ($out !== '') {
            $parts = explode("\0", $out);
            $res = [];
            foreach ($parts as $p) {
                if ($p === '' || !is_file($p)) {
                    continue;
                }
                $res[] = $p;
            }
            return $res;
        }
    }

    // Fallback when `find`/`proc_open` is unavailable.
    $res = [];
    $rootLen = strlen($dir);
    try {
        $iterator = new RecursiveIteratorIterator(
            new RecursiveDirectoryIterator($dir, FilesystemIterator::SKIP_DOTS),
            RecursiveIteratorIterator::SELF_FIRST
        );
        foreach ($iterator as $item) {
            if (!$item->isFile()) {
                continue;
            }
            $path = $item->getPathname();
            $relative = ltrim(str_replace('\\', '/', substr($path, $rootLen)), '/');
            if ($relative === '') {
                continue;
            }
            $depth = substr_count($relative, '/');
            if ($depth < ($minDepth - 1) || $depth > ($maxDepth - 1)) {
                continue;
            }
            $res[] = $path;
        }
    } catch (Throwable) {
        return [];
    }

    return $res;
};

$formatBytes = static function (int $bytes): string {
    if ($bytes < 1024) {
        return $bytes . ' B';
    }

    $units = ['KB', 'MB', 'GB', 'TB'];
    $size = (float)$bytes;
    foreach ($units as $index => $unit) {
        $size /= 1024;
        if ($size < 1024 || $index === array_key_last($units)) {
            return number_format($size, 2) . ' ' . $unit;
        }
    }

    return number_format($size, 2) . ' TB';
};

$isEmptyFile = static function (string $name, int $sizeBytes): bool {
    if ($sizeBytes <= 0) {
        return true;
    }
    if (preg_match('/\\.gz$/i', $name) === 1 && $sizeBytes <= 20) {
        return true;
    }
    return false;
};

$serviceLabel = static function (string $raw): string {
    $clean = preg_replace('/[^a-zA-Z0-9]+/', ' ', $raw) ?? $raw;
    $clean = trim($clean);
    if ($clean === '') {
        return 'UNKNOWN';
    }
    return strtoupper((string)$clean);
};

$serviceKey = static function (string $raw): string {
    $clean = preg_replace('/[^a-zA-Z0-9]+/', '-', $raw) ?? $raw;
    $clean = strtolower(trim($clean, '-'));
    return $clean !== '' ? $clean : 'unknown';
};

$domainScopedServices = [
    'nginx' => true,
    'apache' => true,
    'php-fpm' => true,
];

$extractDomain = static function (string $fileName): ?string {
    $normalized = preg_replace('/\\.gz$/i', '', strtolower(trim($fileName))) ?? strtolower(trim($fileName));
    if ($normalized === '') {
        return null;
    }

    if (preg_match('/^(.+)\\.(access|error)\\.log(?:[-.].*)?$/i', $normalized, $matches) === 1) {
        $domain = trim((string)$matches[1], '.- ');
        return $domain !== '' ? $domain : null;
    }

    if (preg_match('/^(.+)\\.log(?:[-.].*)?$/i', $normalized, $matches) === 1) {
        $domain = trim((string)$matches[1], '.- ');
        if ($domain === '' || in_array($domain, ['access', 'error'], true)) {
            return null;
        }
        return $domain;
    }

    return null;
};

$configuredRootsRaw = trim((string)(getenv('LOGVIEW_ROOTS') ?: ''));
$logRoots = array_values(array_filter(
    array_map(static fn(string $v): string => trim($v), explode(':', $configuredRootsRaw)),
    static fn(string $v): bool => $v !== ''
));
if ($logRoots === []) {
    $logRoots = ['/global/log'];
}

$localLogsFallback = dirname(__DIR__, 4) . DIRECTORY_SEPARATOR . 'logs';
if (!is_dir('/global/log') && is_dir($localLogsFallback) && !in_array($localLogsFallback, $logRoots, true)) {
    $logRoots[] = $localLogsFallback;
}

$serviceMap = [];
$serviceDomains = [];
$logFiles = [];
$activeRoots = [];

foreach ($logRoots as $rootCandidate) {
    $root = realpath($rootCandidate);
    if ($root === false || !is_dir($root)) {
        continue;
    }

    $root = rtrim($root, DIRECTORY_SEPARATOR);
    $activeRoots[$root] = $root;

    try {
        $dirs = new FilesystemIterator($root, FilesystemIterator::SKIP_DOTS);
    } catch (Throwable) {
        continue;
    }

    foreach ($dirs as $entry) {
        if (!$entry->isDir()) {
            continue;
        }

        $dirPath = $entry->getPathname();
        $dirName = $entry->getFilename();
        $currentServiceKey = $serviceKey($dirName);
        $currentServiceLabel = $serviceLabel($dirName);
        $serviceMap[$currentServiceKey] = $currentServiceLabel;

        foreach ($findFiles($dirPath, 1, 3) as $path) {
            $name = basename($path);
            if (str_starts_with($name, '.')) {
                continue;
            }

            $domain = '';
            if (isset($domainScopedServices[$currentServiceKey])) {
                $domain = (string)($extractDomain($name) ?? '');
                if ($domain !== '') {
                    if (!isset($serviceDomains[$currentServiceKey][$domain])) {
                        $serviceDomains[$currentServiceKey][$domain] = 0;
                    }
                    $serviceDomains[$currentServiceKey][$domain]++;
                }
            }

            $stat = @stat($path) ?: [];
            $size = (int)($stat['size'] ?? 0);
            $mtime = (int)($stat['mtime'] ?? 0);
            $logFiles[] = [
                'name' => $name,
                'path' => $path,
                'size' => $formatBytes($size),
                'mtime' => $mtime > 0 ? date('Y-m-d H:i:s', $mtime) : 'Unknown',
                'service' => $currentServiceLabel,
                'serviceKey' => $currentServiceKey,
                'domain' => $domain,
                'sizeBytes' => $size,
                'isEmpty' => $isEmptyFile($name, $size),
                'mtimeTs' => $mtime,
                'active' => false,
            ];
        }
    }
}

uasort($serviceMap, static fn(string $a, string $b): int => strnatcasecmp($a, $b));
$services = [];
foreach ($serviceMap as $key => $label) {
    $services[] = ['key' => $key, 'label' => $label];
}

foreach ($serviceDomains as $service => $domainsMap) {
    uksort($domainsMap, static fn(string $a, string $b): int => strnatcasecmp($a, $b));
    $serviceDomains[$service] = $domainsMap;
}

usort($logFiles, static function (array $a, array $b): int {
    return ($b['mtimeTs'] <=> $a['mtimeTs'])
        ?: strnatcasecmp((string)$a['name'], (string)$b['name']);
});
$logRootsText = $activeRoots === [] ? '/global/log' : implode(', ', array_keys($activeRoots));
$serviceDomainsJson = json_encode(
    $serviceDomains,
    JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE | JSON_HEX_TAG | JSON_HEX_AMP | JSON_HEX_APOS | JSON_HEX_QUOT
);
if (!is_string($serviceDomainsJson)) {
    $serviceDomainsJson = '{}';
}

$splitTailBuffer = static function (string $buffer, int $maxLines): array {
    $lines = preg_split('/\r\n|\r|\n/', $buffer) ?: [];
    if ($lines !== [] && trim((string)end($lines)) === '') {
        array_pop($lines);
    }
    if (count($lines) > $maxLines) {
        $lines = array_slice($lines, -$maxLines);
    }
    return $lines;
};

$readGzipTailLines = static function (string $path, int $maxLines, int $maxBytes) use ($splitTailBuffer): array {
    if (!function_exists('gzopen')) {
        return [];
    }

    $fh = @gzopen($path, 'rb');
    if (!is_resource($fh)) {
        return [];
    }

    $chunkSize = 8192;
    $buffer = '';

    while (!gzeof($fh)) {
        $chunk = (string)@gzread($fh, $chunkSize);
        if ($chunk === '') {
            break;
        }

        $buffer .= $chunk;
        if (strlen($buffer) > $maxBytes) {
            $buffer = (string)substr($buffer, -$maxBytes);
        }
    }

    @gzclose($fh);

    return $splitTailBuffer($buffer, $maxLines);
};

$readTailLines = static function (string $path, int $maxLines = 250, int $maxBytes = 2097152) use ($splitTailBuffer, $readGzipTailLines): array {
    if (!is_file($path) || !is_readable($path)) {
        return [];
    }

    if (preg_match('/\\.gz$/i', $path) === 1) {
        return $readGzipTailLines($path, $maxLines, $maxBytes);
    }

    $fh = @fopen($path, 'rb');
    if (!is_resource($fh)) {
        return [];
    }

    $chunkSize = 8192;
    $buffer = '';
    $bytesRead = 0;
    @fseek($fh, 0, SEEK_END);
    $position = (int)@ftell($fh);

    while ($position > 0 && substr_count($buffer, "\n") <= $maxLines && $bytesRead < $maxBytes) {
        $readSize = min($chunkSize, $position);
        $position -= $readSize;
        @fseek($fh, $position, SEEK_SET);
        $chunk = (string)@fread($fh, $readSize);
        if ($chunk === '') {
            break;
        }
        $buffer = $chunk . $buffer;
        $bytesRead += strlen($chunk);
    }

    @fclose($fh);

    return $splitTailBuffer($buffer, $maxLines);
};

$detectLevel = static function (string $line): string {
    $upper = strtoupper($line);
    if (preg_match('/\b(EMERGENCY|ALERT|CRITICAL|ERROR|FATAL|EXCEPTION)\b/', $upper) === 1) {
        return 'Error';
    }
    if (preg_match('/\b(WARN|WARNING)\b/', $upper) === 1) {
        return 'Warning';
    }
    if (preg_match('/\b(DEBUG|TRACE)\b/', $upper) === 1) {
        return 'Debug';
    }
    return 'Info';
};

$extractTime = static function (string $line): string {
    if (preg_match('/\b(\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2}(?:[.,]\d+)?)\b/', $line, $matches) === 1) {
        return str_replace('T', ' ', (string)$matches[1]);
    }
    if (preg_match('/\b(\d{2}-[A-Za-z]{3}-\d{4}\s\d{2}:\d{2}:\d{2})\b/', $line, $matches) === 1) {
        $dt = DateTimeImmutable::createFromFormat('d-M-Y H:i:s', (string)$matches[1]);
        if ($dt !== false) {
            return $dt->format('Y-m-d H:i:s');
        }
    }
    return '';
};

$normalizeDescription = static function (string $line): string {
    $desc = trim($line);
    $desc = preg_replace('/^\[[^\]]+\]\s*[A-Za-z0-9_.-]+\.[A-Z]+:\s*/', '', $desc) ?? $desc;
    $desc = preg_replace('/^\[[^\]]+\]\s*/', '', $desc) ?? $desc;
    $desc = preg_replace('/^\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2}(?:[.,]\d+)?\s*/', '', $desc) ?? $desc;
    $desc = trim($desc);
    if ($desc === '') {
        return '(empty message)';
    }
    if (strlen($desc) > 320) {
        return substr($desc, 0, 317) . '...';
    }
    return $desc;
};

$selectedTokenRaw = trim((string)($_GET['file'] ?? ''));
$selectedToken = preg_match('/^[a-f0-9]{40}$/', $selectedTokenRaw) === 1 ? $selectedTokenRaw : '';
$activeFile = null;
$defaultActiveIndex = null;

foreach ($logFiles as $idx => &$file) {
    $token = sha1((string)$file['path']);
    $file['token'] = $token;
    $file['active'] = false;

    if (!(bool)($file['isEmpty'] ?? false) && $defaultActiveIndex === null) {
        $defaultActiveIndex = $idx;
    }

    if ($selectedToken !== '' && !(bool)($file['isEmpty'] ?? false) && hash_equals($token, $selectedToken)) {
        $file['active'] = true;
        $activeFile = $file;
    }
}
unset($file);

if ($activeFile === null && $logFiles !== []) {
    $fallbackIndex = $defaultActiveIndex ?? 0;
    $logFiles[$fallbackIndex]['active'] = true;
    $activeFile = $logFiles[$fallbackIndex];
}

$rows = [];
if (is_array($activeFile) && isset($activeFile['path']) && is_string($activeFile['path'])) {
    $lines = $readTailLines($activeFile['path'], 250, 3 * 1024 * 1024);
    $lineIndex = count($lines);
    for ($i = count($lines) - 1; $i >= 0; $i--) {
        $raw = trim((string)$lines[$i]);
        if ($raw === '') {
            $lineIndex--;
            continue;
        }

        $level = $detectLevel($raw);
        $time = $extractTime($raw);
        if ($time === '') {
            $time = (string)($activeFile['mtime'] ?? 'Unknown');
        }

        $rows[] = [
            'level' => $level,
            'time' => $time,
            'description' => $normalizeDescription($raw),
            'line' => number_format(max($lineIndex, 1)),
            'raw' => $raw,
        ];
        $lineIndex--;
    }
}
$activeViewingTitle = 'Viewing: none';
if (is_array($activeFile)) {
    $activeViewingTitle = 'Viewing: ' . (string)$activeFile['service'] . ' / ' . (string)$activeFile['name'];
}

$levelCounts = [
    'Debug' => 0,
    'Info' => 0,
    'Warning' => 0,
    'Error' => 0,
];
foreach ($rows as $row) {
    $levelName = (string)($row['level'] ?? 'Info');
    if (isset($levelCounts[$levelName])) {
        $levelCounts[$levelName]++;
    }
}

$levelChips = [
    ['label' => 'Debug', 'count' => number_format($levelCounts['Debug']), 'tone' => 'debug'],
    ['label' => 'Info', 'count' => number_format($levelCounts['Info']), 'tone' => 'info'],
    ['label' => 'Warning', 'count' => number_format($levelCounts['Warning']), 'tone' => 'warning'],
    ['label' => 'Error', 'count' => number_format($levelCounts['Error']), 'tone' => 'error'],
];

$levelUi = [
    'Error' => ['icon' => 'bi-x-octagon-fill', 'class' => 'ap-logv-lvl-error'],
    'Warning' => ['icon' => 'bi-exclamation-triangle-fill', 'class' => 'ap-logv-lvl-warning'],
    'Info' => ['icon' => 'bi-info-circle-fill', 'class' => 'ap-logv-lvl-info'],
    'Debug' => ['icon' => 'bi-bug-fill', 'class' => 'ap-logv-lvl-debug'],
];
?>

<section class="ap-page-head">
  <div>
    <p class="ap-breadcrumb mb-1">Home / Logs</p>
    <h2 class="ap-page-title mb-1">Log Viewer</h2>
    <p id="apLogRootsText" class="ap-page-sub mb-0">
      Filter by service/domain and inspect recent entries instantly.
    </p>
  </div>
</section>

<section class="ap-logv-stage">
  <article class="ap-logv-shell">
    <div class="ap-logv-layout">
      <aside class="ap-logv-files">
        <div class="ap-logv-side-head">
          <div class="ap-logv-service-wrap">
            <div class="ap-logv-service-head">
              <label for="apLogService" class="ap-logv-service-label">Service</label>
              <div id="apLogFilterWrap" class="ap-logv-filter-wrap">
                <button
                  id="apLogFilterBtn"
                  class="btn ap-logv-filter-btn"
                  type="button"
                  aria-expanded="false"
                  aria-controls="apLogFilterMenu"
                  title="File filters"
                >
                  <i class="bi bi-gear-fill" aria-hidden="true"></i>
                </button>
                <div id="apLogFilterMenu" class="ap-logv-filter-menu" hidden>
                  <label class="ap-logv-filter-item">
                    <input id="apLogFilterHideEmpty" type="checkbox" checked>
                    <span>Hide empty files</span>
                  </label>
                  <label class="ap-logv-filter-item">
                    <input id="apLogFilterHideLocalhost" type="checkbox" checked>
                    <span>Hide localhost.*</span>
                  </label>
                  <label class="ap-logv-filter-item">
                    <input id="apLogFilterHideCompressed" type="checkbox">
                    <span>Hide compressed (.gz)</span>
                  </label>
                  <div class="ap-logv-filter-date">
                    <label for="apLogFilterDateFrom" class="ap-logv-filter-date-label">Date from</label>
                    <input id="apLogFilterDateFrom" class="form-control form-control-sm ap-logv-filter-date-input" type="date" title="Format: Y-m-d">
                  </div>
                  <div class="ap-logv-filter-date">
                    <label for="apLogFilterDateTo" class="ap-logv-filter-date-label">Date to</label>
                    <input id="apLogFilterDateTo" class="form-control form-control-sm ap-logv-filter-date-input" type="date" title="Format: Y-m-d">
                  </div>
                  <p class="ap-logv-filter-date-help mb-0">Format: Y-m-d</p>
                  <button id="apLogFilterDateClear" class="btn ap-logv-filter-clear" type="button">Clear Date Filter</button>
                </div>
              </div>
            </div>
            <div class="ap-logv-service-select-wrap">
              <select id="apLogService" class="form-select ap-logv-service-select" <?= $services === [] ? 'disabled' : '' ?>>
                <option value="all">All Services</option>
                <?php foreach ($services as $service): ?>
                  <option value="<?= htmlspecialchars($service['key'], ENT_QUOTES, 'UTF-8') ?>"><?= htmlspecialchars($service['label'], ENT_QUOTES, 'UTF-8') ?></option>
                <?php endforeach; ?>
              </select>
              <i class="bi bi-chevron-down ap-logv-service-caret" aria-hidden="true"></i>
            </div>
          </div>
          <div id="apLogDomainWrap" class="ap-logv-domain-wrap is-hidden">
            <label for="apLogDomain" class="ap-logv-service-label">Domain</label>
            <div id="apLogDomainUi" class="ap-logv-multi is-disabled" aria-disabled="true">
              <button id="apLogDomainTrigger" class="btn ap-logv-multi-trigger" type="button" disabled aria-expanded="false">
                <span id="apLogDomainValue" class="ap-logv-multi-value">All Domains</span>
                <i class="bi bi-chevron-down ap-logv-multi-caret" aria-hidden="true"></i>
              </button>
              <div id="apLogDomainMenu" class="ap-logv-multi-menu" hidden></div>
            </div>
            <select id="apLogDomain" class="ap-logv-domain-native" multiple disabled></select>
          </div>
        </div>

        <div id="apLogFileList" class="ap-logv-file-list">
          <?php if ($logFiles === []): ?>
            <p class="text-muted small mb-0 px-2 py-2">No log files found.</p>
          <?php else: ?>
            <?php foreach ($logFiles as $file): ?>
              <button
                class="btn ap-logv-file-item <?= $file['active'] ? 'is-active' : '' ?>"
                type="button"
                data-service="<?= htmlspecialchars((string)$file['serviceKey'], ENT_QUOTES, 'UTF-8') ?>"
                data-domain="<?= htmlspecialchars((string)$file['domain'], ENT_QUOTES, 'UTF-8') ?>"
                data-empty="<?= !empty($file['isEmpty']) ? '1' : '0' ?>"
                data-localhost="<?= preg_match('/^localhost\./i', (string)$file['name']) === 1 ? '1' : '0' ?>"
                data-compressed="<?= preg_match('/\.gz$/i', (string)$file['name']) === 1 ? '1' : '0' ?>"
                data-mtime-ts="<?= (int)($file['mtimeTs'] ?? 0) ?>"
                data-name="<?= htmlspecialchars((string)$file['name'], ENT_QUOTES, 'UTF-8') ?>"
                data-file="<?= htmlspecialchars((string)($file['token'] ?? ''), ENT_QUOTES, 'UTF-8') ?>"
              >
                <span class="ap-logv-file-top">
                  <span class="ap-logv-file-name" title="<?= htmlspecialchars((string)$file['name'], ENT_QUOTES, 'UTF-8') ?>"><?= htmlspecialchars($file['name'], ENT_QUOTES, 'UTF-8') ?></span>
                  <span class="ap-logv-file-size"><?= htmlspecialchars($file['size'], ENT_QUOTES, 'UTF-8') ?></span>
                </span>
                <span class="ap-logv-file-meta">
                  <span class="ap-logv-file-mtime"><?= htmlspecialchars($file['mtime'], ENT_QUOTES, 'UTF-8') ?></span>
                  <span class="ap-logv-file-service"><?= htmlspecialchars($file['service'], ENT_QUOTES, 'UTF-8') ?></span>
                </span>
              </button>
            <?php endforeach; ?>
          <?php endif; ?>
        </div>
      </aside>

      <div class="ap-logv-main">
        <section class="ap-logv-main-content" aria-label="Log entries">
          <header class="ap-logv-toolbar">
            <div class="ap-logv-chip-row">
              <button class="btn ap-logv-chip ap-logv-chip-all is-active" type="button" data-level="all">
                <span class="ap-logv-chip-dot"></span>
                All:
                <strong id="apLogChipAllCount"><?= count($rows) ?></strong>
              </button>
              <?php foreach ($levelChips as $chip): ?>
                <button
                  class="btn ap-logv-chip ap-logv-chip-<?= htmlspecialchars($chip['tone'], ENT_QUOTES, 'UTF-8') ?>"
                  type="button"
                  data-level="<?= htmlspecialchars((string)strtolower((string)$chip['label']), ENT_QUOTES, 'UTF-8') ?>"
                >
                  <span class="ap-logv-chip-dot"></span>
                  <?= htmlspecialchars($chip['label'], ENT_QUOTES, 'UTF-8') ?>:
                  <strong><?= htmlspecialchars($chip['count'], ENT_QUOTES, 'UTF-8') ?></strong>
                </button>
              <?php endforeach; ?>
            </div>
            <div class="ap-logv-tools">
              <label class="ap-logv-search" aria-label="Search logs">
                <i class="bi bi-search"></i>
                <input id="apLogSearchInput" type="search" value="" placeholder="Search... RegEx welcome!">
              </label>
              <button id="apLogRefreshBtn" class="btn ap-logv-icon-btn" type="button" aria-label="Refresh" title="Refresh files and entries">
                <i class="bi bi-arrow-repeat"></i>
              </button>
              <div id="apLogSettings" class="ap-logv-settings">
                <button
                  id="apLogSettingsBtn"
                  class="btn ap-logv-icon-btn"
                  type="button"
                  aria-label="Settings"
                  title="Search settings"
                  aria-expanded="false"
                  aria-controls="apLogSettingsMenu"
                >
                  <i class="bi bi-gear-fill"></i>
                </button>
                <div id="apLogSettingsMenu" class="ap-logv-settings-menu" hidden>
                  <label class="ap-logv-settings-item">
                    <input id="apLogRegexMode" type="checkbox" checked>
                    <span>Regex mode</span>
                  </label>
                  <label class="ap-logv-settings-item">
                    <input id="apLogRegexCase" type="checkbox">
                    <span>Case sensitive</span>
                  </label>
                </div>
              </div>
            </div>
          </header>

          <div class="ap-logv-current-strip" title="<?= htmlspecialchars($activeViewingTitle, ENT_QUOTES, 'UTF-8') ?>">
            <?php if (is_array($activeFile)): ?>
              Viewing: <?= htmlspecialchars((string)$activeFile['service'], ENT_QUOTES, 'UTF-8') ?> / <?= htmlspecialchars((string)$activeFile['name'], ENT_QUOTES, 'UTF-8') ?>
            <?php else: ?>
              Viewing: none
            <?php endif; ?>
          </div>

          <div class="ap-logv-table-head">
            <div class="ap-logv-head-left">
              <span>Level</span>
              <span>Time</span>
              <span>Description</span>
            </div>
          </div>

          <div id="apLogTableBody" class="ap-logv-table-body">
            <?php if ($rows === []): ?>
              <p class="text-muted small mb-0 px-3 py-3">No readable entries in the selected log file.</p>
            <?php else: ?>
              <?php foreach ($rows as $row): ?>
                <?php
                  $ui = $levelUi[$row['level']] ?? $levelUi['Info'];
                  $isError = strtolower((string)$row['level']) === 'error';
                  $rowLevel = strtolower((string)$row['level']);
                  $detailMeta = sprintf(
                      'Service: %s · File: %s · Line: %s',
                      (string)($activeFile['service'] ?? 'N/A'),
                      (string)($activeFile['name'] ?? 'N/A'),
                      (string)$row['line']
                  );
                  $detailTrace = (string)($row['raw'] ?? $row['description']);
                ?>
                <details
                  class="ap-logv-entry <?= $isError ? 'is-error' : '' ?>"
                  name="apLogEntry"
                  data-level="<?= htmlspecialchars($rowLevel, ENT_QUOTES, 'UTF-8') ?>"
                >
                  <summary class="ap-logv-row">
                    <div class="ap-logv-row-main">
                      <span class="ap-logv-level <?= htmlspecialchars($ui['class'], ENT_QUOTES, 'UTF-8') ?>">
                        <i class="bi <?= htmlspecialchars($ui['icon'], ENT_QUOTES, 'UTF-8') ?>"></i>
                        <?= htmlspecialchars($row['level'], ENT_QUOTES, 'UTF-8') ?>
                      </span>
                      <span><?= htmlspecialchars($row['time'], ENT_QUOTES, 'UTF-8') ?></span>
                      <span class="ap-logv-desc"><?= htmlspecialchars($row['description'], ENT_QUOTES, 'UTF-8') ?></span>
                    </div>
                    <div class="ap-logv-row-line">
                      <span><?= htmlspecialchars($row['line'], ENT_QUOTES, 'UTF-8') ?></span>
                      <i class="bi bi-chevron-down ap-logv-row-caret" aria-hidden="true"></i>
                    </div>
                  </summary>
                  <div class="ap-logv-row-detail">
                    <p class="ap-logv-detail-meta mb-2"><?= htmlspecialchars($detailMeta, ENT_QUOTES, 'UTF-8') ?></p>
                    <p class="ap-logv-detail-label mb-1">Message</p>
                    <p class="ap-logv-detail-text mb-2"><?= htmlspecialchars($row['description'], ENT_QUOTES, 'UTF-8') ?></p>
                    <p class="ap-logv-detail-label mb-1">Raw Line</p>
                    <pre class="ap-logv-detail-code mb-0"><?= htmlspecialchars($detailTrace, ENT_QUOTES, 'UTF-8') ?></pre>
                  </div>
                </details>
              <?php endforeach; ?>
            <?php endif; ?>
          </div>

          <footer class="ap-logv-footer">
            <p id="apLogFooterMeta" class="ap-logv-foot-meta mb-0">
              <?php if (is_array($activeFile)): ?>
                <?= htmlspecialchars((string)$activeFile['service'], ENT_QUOTES, 'UTF-8') ?>
                <span>.</span>
                <?= htmlspecialchars((string)$activeFile['name'], ENT_QUOTES, 'UTF-8') ?>
                <span>.</span>
                <?= htmlspecialchars((string)$activeFile['size'], ENT_QUOTES, 'UTF-8') ?>
              <?php else: ?>
                No active log file selected
              <?php endif; ?>
            </p>
          </footer>
        </section>
      </div>
    </div>
  </article>
</section>

<script id="apLogServiceDomains" type="application/json"><?= $serviceDomainsJson ?></script>

<script>
  document.addEventListener("DOMContentLoaded", function () {
    var bindExclusive = function (selector) {
      var items = Array.prototype.slice.call(document.querySelectorAll(selector));
      items.forEach(function (item) {
        item.addEventListener("toggle", function () {
          if (!item.open) {
            return;
          }
          items.forEach(function (other) {
            if (other !== item && other.open) {
              other.open = false;
            }
          });
        });
      });
    };

    var basePath = (document.body && document.body.getAttribute("data-ap-base")) || "";
    if (basePath === "/") {
      basePath = "";
    }
    var logsFilesApiUrl = basePath + "/api/logs/files";
    var logsEntriesApiUrl = basePath + "/api/logs/entries";

    var serviceSelect = document.getElementById("apLogService");
    var filterWrapEl = document.getElementById("apLogFilterWrap");
    var filterBtnEl = document.getElementById("apLogFilterBtn");
    var filterMenuEl = document.getElementById("apLogFilterMenu");
    var filterHideEmptyEl = document.getElementById("apLogFilterHideEmpty");
    var filterHideLocalhostEl = document.getElementById("apLogFilterHideLocalhost");
    var filterHideCompressedEl = document.getElementById("apLogFilterHideCompressed");
    var filterDateFromEl = document.getElementById("apLogFilterDateFrom");
    var filterDateToEl = document.getElementById("apLogFilterDateTo");
    var filterDateClearEl = document.getElementById("apLogFilterDateClear");
    var domainWrap = document.getElementById("apLogDomainWrap");
    var domainUi = document.getElementById("apLogDomainUi");
    var domainTrigger = document.getElementById("apLogDomainTrigger");
    var domainValue = document.getElementById("apLogDomainValue");
    var domainMenu = document.getElementById("apLogDomainMenu");
    var domainSelect = document.getElementById("apLogDomain");
    var domainDataNode = document.getElementById("apLogServiceDomains");
    var rootsTextEl = document.getElementById("apLogRootsText");
    var fileListEl = document.getElementById("apLogFileList");
    var tableBodyEl = document.getElementById("apLogTableBody");
    var currentStripEl = document.querySelector(".ap-logv-current-strip");
    var footerMetaEl = document.getElementById("apLogFooterMeta");
    var allCountEl = document.getElementById("apLogChipAllCount");
    var searchInputEl = document.getElementById("apLogSearchInput");
    var refreshBtnEl = document.getElementById("apLogRefreshBtn");
    var settingsWrapEl = document.getElementById("apLogSettings");
    var settingsBtnEl = document.getElementById("apLogSettingsBtn");
    var settingsMenuEl = document.getElementById("apLogSettingsMenu");
    var regexModeEl = document.getElementById("apLogRegexMode");
    var caseSensitiveEl = document.getElementById("apLogRegexCase");

    var fileItems = Array.prototype.slice.call(document.querySelectorAll(".ap-logv-file-item"));
    var levelChips = Array.prototype.slice.call(document.querySelectorAll(".ap-logv-chip"));
    var logEntries = Array.prototype.slice.call(document.querySelectorAll(".ap-logv-entry"));
    var activeFileToken = "";
    var selectedLevelState = "all";
    var searchDebounceTimer = null;
    var refreshing = false;
    var domainEnabledServices = {
      nginx: true,
      apache: true,
      "php-fpm": true
    };
    var serviceDomains = {};
    if (domainDataNode) {
      try {
        serviceDomains = JSON.parse(domainDataNode.textContent || "{}");
      } catch (e) {
        serviceDomains = {};
      }
    }

    var levelUi = {
      error: { icon: "bi-x-octagon-fill", className: "ap-logv-lvl-error", label: "Error" },
      warning: { icon: "bi-exclamation-triangle-fill", className: "ap-logv-lvl-warning", label: "Warning" },
      info: { icon: "bi-info-circle-fill", className: "ap-logv-lvl-info", label: "Info" },
      debug: { icon: "bi-bug-fill", className: "ap-logv-lvl-debug", label: "Debug" }
    };

    var escapeHtml = function (value) {
      return String(value || "")
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;")
        .replace(/'/g, "&#039;");
    };

    var numberFmt = function (value) {
      var n = Number(value);
      if (!isFinite(n)) {
        return "0";
      }
      return String(Math.max(0, Math.round(n)).toLocaleString());
    };

    var fileTokenFromUrl = function () {
      try {
        var url = new URL(window.location.href);
        var token = String(url.searchParams.get("file") || "").toLowerCase();
        return /^[a-f0-9]{40}$/.test(token) ? token : "";
      } catch (e) {
        return "";
      }
    };

    var setFileTokenInUrl = function (token) {
      try {
        var url = new URL(window.location.href);
        if (!token) {
          url.searchParams.delete("file");
        } else {
          url.searchParams.set("file", String(token).toLowerCase());
        }
        window.history.replaceState({}, "", url.toString());
      } catch (e) {
        // noop
      }
    };

    var fetchJson = function (url) {
      return fetch(url, {
        method: "GET",
        credentials: "same-origin",
        cache: "no-store",
        headers: {
          "Accept": "application/json",
          "X-Requested-With": "XMLHttpRequest"
        }
      }).then(function (response) {
        return response.text().then(function (text) {
          var payload = {};
          try {
            payload = JSON.parse(text || "{}");
          } catch (e) {
            payload = {};
          }
          if (!response.ok || payload.ok !== true) {
            throw new Error(String((payload && payload.error) || ("HTTP " + response.status)));
          }
          return payload;
        });
      });
    };

    var refreshFileItems = function () {
      fileItems = Array.prototype.slice.call(document.querySelectorAll(".ap-logv-file-item"));
    };

    var setActiveFileByToken = function (token) {
      var normalized = String(token || "").toLowerCase();
      activeFileToken = normalized;
      fileItems.forEach(function (fileItem) {
        var itemToken = String(fileItem.dataset.file || "").toLowerCase();
        fileItem.classList.toggle("is-active", normalized !== "" && itemToken === normalized);
      });
    };

    var getFirstVisibleFile = function () {
      for (var i = 0; i < fileItems.length; i++) {
        if (!fileItems[i].classList.contains("is-hidden")) {
          return fileItems[i];
        }
      }
      return null;
    };

    var getActiveVisibleFile = function () {
      for (var i = 0; i < fileItems.length; i++) {
        if (fileItems[i].classList.contains("is-active") && !fileItems[i].classList.contains("is-hidden")) {
          return fileItems[i];
        }
      }
      return null;
    };

    var updateChipCounts = function (counts) {
      var safe = counts && typeof counts === "object" ? counts : {};
      var debugCount = Number(safe.Debug || 0);
      var infoCount = Number(safe.Info || 0);
      var warningCount = Number(safe.Warning || 0);
      var errorCount = Number(safe.Error || 0);
      var total = Math.max(0, debugCount) + Math.max(0, infoCount) + Math.max(0, warningCount) + Math.max(0, errorCount);

      if (allCountEl) {
        allCountEl.textContent = numberFmt(total);
      }
      levelChips.forEach(function (chip) {
        var level = String(chip.dataset.level || "").toLowerCase();
        var strong = chip.querySelector("strong");
        if (!strong) {
          return;
        }
        if (level === "debug") {
          strong.textContent = numberFmt(debugCount);
        } else if (level === "info") {
          strong.textContent = numberFmt(infoCount);
        } else if (level === "warning") {
          strong.textContent = numberFmt(warningCount);
        } else if (level === "error") {
          strong.textContent = numberFmt(errorCount);
        }
      });
    };
    var setSearchInvalid = function (invalid, message) {
      if (!searchInputEl) {
        return;
      }
      var isInvalid = !!invalid;
      searchInputEl.classList.toggle("is-invalid", isInvalid);
      var searchWrap = searchInputEl.closest(".ap-logv-search");
      if (searchWrap) {
        searchWrap.classList.toggle("is-invalid", isInvalid);
      }
      searchInputEl.setAttribute("title", isInvalid ? String(message || "Invalid regex pattern") : "");
    };
    var getSearchMatcher = function () {
      if (!searchInputEl) {
        return function () {
          return true;
        };
      }

      var query = String(searchInputEl.value || "").trim();
      if (query === "") {
        setSearchInvalid(false, "");
        return function () {
          return true;
        };
      }

      var regexMode = !!(regexModeEl && regexModeEl.checked);
      var caseSensitive = !!(caseSensitiveEl && caseSensitiveEl.checked);

      if (regexMode) {
        try {
          var regex = new RegExp(query, caseSensitive ? "" : "i");
          setSearchInvalid(false, "");
          return function (text) {
            return regex.test(text);
          };
        } catch (error) {
          setSearchInvalid(true, "Invalid regex pattern. Falling back to plain text.");
        }
      } else {
        setSearchInvalid(false, "");
      }

      var needle = caseSensitive ? query : query.toLowerCase();
      return function (text) {
        var haystack = caseSensitive ? text : text.toLowerCase();
        return haystack.indexOf(needle) !== -1;
      };
    };
    var applyEntryFilters = function () {
      var matcher = getSearchMatcher();
      logEntries = Array.prototype.slice.call(document.querySelectorAll(".ap-logv-entry"));
      logEntries.forEach(function (entry) {
        var rowLevel = String(entry.dataset.level || "").toLowerCase();
        var levelVisible = selectedLevelState === "all" || selectedLevelState === rowLevel;
        var entryText = String(entry.textContent || "");
        var searchVisible = matcher(entryText);
        var isVisible = levelVisible && searchVisible;
        entry.classList.toggle("is-hidden", !isVisible);
        if (!isVisible && entry.open) {
          entry.open = false;
        }
      });
    };
    var closeSettingsMenu = function () {
      if (!settingsMenuEl || !settingsBtnEl) {
        return;
      }
      settingsMenuEl.hidden = true;
      settingsBtnEl.setAttribute("aria-expanded", "false");
    };
    var toggleSettingsMenu = function () {
      if (!settingsMenuEl || !settingsBtnEl) {
        return;
      }
      var open = !!settingsMenuEl.hidden;
      settingsMenuEl.hidden = !open;
      settingsBtnEl.setAttribute("aria-expanded", open ? "true" : "false");
    };
    var recoverFromLoadError = function () {
      updateDomainSelector(serviceSelect ? (serviceSelect.value || "all") : "all");
      applyServiceFilter(false);
      var fallbackToken = fileTokenFromUrl();
      if (!fallbackToken) {
        var fallbackActive = getActiveVisibleFile() || getFirstVisibleFile();
        fallbackToken = fallbackActive ? String(fallbackActive.dataset.file || "") : "";
      }
      if (fallbackToken) {
        loadEntriesAjax(fallbackToken, false);
      } else {
        renderRows([], null);
        updateChipCounts({ Debug: 0, Info: 0, Warning: 0, Error: 0 });
      }
    };
    var refreshData = function () {
      if (refreshing) {
        return;
      }
      refreshing = true;
      if (refreshBtnEl) {
        refreshBtnEl.classList.add("is-loading");
        refreshBtnEl.setAttribute("aria-busy", "true");
      }

      loadFilesAjax().then(function () {
        refreshing = false;
        if (refreshBtnEl) {
          refreshBtnEl.classList.remove("is-loading");
          refreshBtnEl.removeAttribute("aria-busy");
        }
      }, function () {
        recoverFromLoadError();
        refreshing = false;
        if (refreshBtnEl) {
          refreshBtnEl.classList.remove("is-loading");
          refreshBtnEl.removeAttribute("aria-busy");
        }
      });
    };
    var closeFilterMenu = function () {
      if (!filterMenuEl || !filterBtnEl) {
        return;
      }
      filterMenuEl.hidden = true;
      filterBtnEl.setAttribute("aria-expanded", "false");
    };
    var toggleFilterMenu = function () {
      if (!filterMenuEl || !filterBtnEl) {
        return;
      }
      var shouldOpen = !!filterMenuEl.hidden;
      filterMenuEl.hidden = !shouldOpen;
      filterBtnEl.setAttribute("aria-expanded", shouldOpen ? "true" : "false");
    };
    var parseYmdDate = function (rawValue) {
      var value = String(rawValue || "").trim();
      if (value === "") {
        return null;
      }
      if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) {
        return null;
      }
      var parts = value.split("-");
      var year = Number(parts[0]);
      var month = Number(parts[1]);
      var day = Number(parts[2]);
      if (!isFinite(year) || !isFinite(month) || !isFinite(day)) {
        return null;
      }
      var dt = new Date(year, month - 1, day, 0, 0, 0, 0);
      if (
        dt.getFullYear() !== year
        || (dt.getMonth() + 1) !== month
        || dt.getDate() !== day
      ) {
        return null;
      }
      return dt;
    };
    var parseDateStartMs = function (rawValue) {
      var dt = parseYmdDate(rawValue);
      if (!dt) {
        return null;
      }
      var time = dt.getTime();
      return isFinite(time) ? time : null;
    };
    var parseDateEndMs = function (rawValue) {
      var dt = parseYmdDate(rawValue);
      if (!dt) {
        return null;
      }
      dt.setHours(23, 59, 59, 999);
      var time = dt.getTime();
      return isFinite(time) ? time : null;
    };
    var getCurrentFileFilterState = function () {
      var dateFromMs = parseDateStartMs(filterDateFromEl ? filterDateFromEl.value : "");
      var dateToMs = parseDateEndMs(filterDateToEl ? filterDateToEl.value : "");
      if (dateFromMs !== null && dateToMs !== null && dateFromMs > dateToMs) {
        var swapped = dateFromMs;
        dateFromMs = dateToMs;
        dateToMs = swapped;
      }
      return {
        hideEmpty: !!(filterHideEmptyEl && filterHideEmptyEl.checked),
        hideLocalhost: !!(filterHideLocalhostEl && filterHideLocalhostEl.checked),
        hideCompressed: !!(filterHideCompressedEl && filterHideCompressedEl.checked),
        dateFromMs: dateFromMs,
        dateToMs: dateToMs
      };
    };
    var fileMatchesBaseFilters = function (fileItem, selectedService, state) {
      var itemService = String(fileItem.dataset.service || "").toLowerCase();
      var itemIsEmpty = String(fileItem.dataset.empty || "0") === "1";
      var itemIsLocalhost = String(fileItem.dataset.localhost || "0") === "1";
      var itemIsCompressed = String(fileItem.dataset.compressed || "0") === "1";
      var itemMtimeTs = Number(fileItem.dataset.mtimeTs || "0");
      var itemMtimeMs = isFinite(itemMtimeTs) ? Math.round(itemMtimeTs * 1000) : 0;

      var serviceVisible = selectedService === "all" || itemService === selectedService;
      if (!serviceVisible) {
        return false;
      }
      if (state.hideEmpty && itemIsEmpty) {
        return false;
      }
      if (state.hideLocalhost && itemIsLocalhost) {
        return false;
      }
      if (state.hideCompressed && itemIsCompressed) {
        return false;
      }
      if (state.dateFromMs !== null || state.dateToMs !== null) {
        if (itemMtimeMs <= 0) {
          return false;
        }
        if (state.dateFromMs !== null && itemMtimeMs < state.dateFromMs) {
          return false;
        }
        if (state.dateToMs !== null && itemMtimeMs > state.dateToMs) {
          return false;
        }
      }

      return true;
    };
    var computeDomainCountsForService = function (serviceKey) {
      var counts = {};
      if (!serviceKey || serviceKey === "all") {
        return counts;
      }
      var state = getCurrentFileFilterState();
      fileItems.forEach(function (fileItem) {
        if (!fileMatchesBaseFilters(fileItem, serviceKey, state)) {
          return;
        }
        var domain = String(fileItem.dataset.domain || "").toLowerCase();
        if (domain === "") {
          return;
        }
        if (!Object.prototype.hasOwnProperty.call(counts, domain)) {
          counts[domain] = 0;
        }
        counts[domain]++;
      });
      return counts;
    };
    var refreshDomainOptionCounts = function (serviceKey) {
      if (!domainSelect || !domainMenu || !serviceKey || serviceKey === "all") {
        return;
      }
      var counts = computeDomainCountsForService(serviceKey);
      var total = 0;

      Array.prototype.slice.call(domainSelect.options || []).forEach(function (opt) {
        var value = String(opt.value || "").toLowerCase();
        var label = String(opt.dataset.label || opt.value || "");
        var count = Number(counts[value] || 0);
        total += count;
        opt.textContent = label + " (" + String(count) + ")";
      });

      Array.prototype.slice.call(domainMenu.querySelectorAll(".ap-logv-multi-option")).forEach(function (node) {
        var value = String(node.dataset.value || "").toLowerCase();
        var countEl = node.querySelector("strong");
        if (!countEl) {
          return;
        }
        if (value === "__all") {
          countEl.textContent = String(total);
          return;
        }
        countEl.textContent = String(Number(counts[value] || 0));
      });
    };
    var closeDomainMenu = function () {
      if (!domainMenu || !domainTrigger) {
        return;
      }
      domainMenu.hidden = true;
      domainTrigger.setAttribute("aria-expanded", "false");
      if (domainUi) {
        domainUi.classList.remove("is-open");
      }
    };
    var getSelectedDomains = function () {
      if (!domainSelect) {
        return [];
      }
      return Array.prototype.slice.call(domainSelect.selectedOptions || []).map(function (opt) {
        return String(opt.value || "").toLowerCase();
      }).filter(function (value) {
        return value !== "";
      });
    };
    var syncDomainSummary = function () {
      if (!domainValue || !domainSelect) {
        return;
      }
      var selectedOptions = Array.prototype.slice.call(domainSelect.selectedOptions || []);
      if (selectedOptions.length === 0) {
        domainValue.textContent = "All Domains";
        return;
      }
      if (selectedOptions.length <= 2) {
        domainValue.textContent = selectedOptions.map(function (opt) {
          return String(opt.dataset.label || opt.value || "");
        }).join(", ");
        return;
      }
      domainValue.textContent = String(selectedOptions.length) + " domains selected";
    };
    var refreshDomainMenuState = function () {
      if (!domainMenu || !domainSelect) {
        return;
      }
      var selected = getSelectedDomains();
      var selectedSet = {};
      selected.forEach(function (value) {
        selectedSet[value] = true;
      });
      var optionNodes = Array.prototype.slice.call(domainMenu.querySelectorAll(".ap-logv-multi-option"));
      optionNodes.forEach(function (node) {
        var value = String(node.dataset.value || "").toLowerCase();
        var active = value === "__all"
          ? selected.length === 0
          : Object.prototype.hasOwnProperty.call(selectedSet, value);
        node.classList.toggle("is-active", active);
      });
      syncDomainSummary();
    };
    var setDomainValues = function (values, autoLoad) {
      if (typeof autoLoad === "undefined") {
        autoLoad = true;
      }
      if (!domainSelect) {
        return;
      }
      var normalized = {};
      values.forEach(function (v) {
        var key = String(v || "").toLowerCase();
        if (key !== "") {
          normalized[key] = true;
        }
      });
      Array.prototype.slice.call(domainSelect.options || []).forEach(function (opt) {
        opt.selected = Object.prototype.hasOwnProperty.call(normalized, String(opt.value || "").toLowerCase());
      });
      refreshDomainMenuState();
      applyServiceFilter(autoLoad);
    };
    var buildDomainOptions = function (normalizedService) {
      if (!domainSelect || !domainMenu) {
        return;
      }

      domainSelect.innerHTML = "";
      domainMenu.innerHTML = "";

      var allButton = document.createElement("button");
      allButton.type = "button";
      allButton.className = "ap-logv-multi-option";
      allButton.dataset.value = "__all";
      var allLabel = document.createElement("span");
      allLabel.textContent = "All Domains";
      var allCount = document.createElement("strong");
      allCount.textContent = "0";
      allButton.appendChild(allLabel);
      allButton.appendChild(allCount);
      allButton.addEventListener("click", function () {
        setDomainValues([], true);
      });
      domainMenu.appendChild(allButton);

      var domains = serviceDomains[normalizedService] && typeof serviceDomains[normalizedService] === "object"
        ? serviceDomains[normalizedService]
        : {};
      var dynamicCounts = computeDomainCountsForService(normalizedService);
      var domainMap = {};
      Object.keys(domains).forEach(function (domain) {
        var key = String(domain || "").toLowerCase();
        if (key !== "") {
          domainMap[key] = String(domain);
        }
      });
      Object.keys(dynamicCounts).forEach(function (domain) {
        var key = String(domain || "").toLowerCase();
        if (key !== "" && !Object.prototype.hasOwnProperty.call(domainMap, key)) {
          domainMap[key] = key;
        }
      });
      var domainNames = Object.keys(domainMap).sort(function (a, b) {
        return a.localeCompare(b, undefined, { numeric: true, sensitivity: "base" });
      });

      domainNames.forEach(function (domain) {
        var value = String(domain || "").toLowerCase();
        if (!value) {
          return;
        }

        var displayLabel = String(domainMap[value] || value);
        var count = Number(dynamicCounts[value] || 0);
        var option = document.createElement("option");
        option.value = value;
        option.dataset.label = displayLabel;
        option.textContent = displayLabel + " (" + String(count) + ")";
        domainSelect.appendChild(option);

        var button = document.createElement("button");
        button.type = "button";
        button.className = "ap-logv-multi-option";
        button.dataset.value = value;
        var label = document.createElement("span");
        label.textContent = displayLabel;
        var countEl = document.createElement("strong");
        countEl.textContent = String(count);
        button.appendChild(label);
        button.appendChild(countEl);
        button.addEventListener("click", function () {
          var selectedNow = getSelectedDomains();
          var map = {};
          selectedNow.forEach(function (selected) {
            map[selected] = true;
          });
          if (Object.prototype.hasOwnProperty.call(map, value)) {
            delete map[value];
          } else {
            map[value] = true;
          }
          setDomainValues(Object.keys(map), true);
        });
        domainMenu.appendChild(button);
      });
      refreshDomainOptionCounts(normalizedService);

      if (domainNames.length === 0) {
        domainSelect.setAttribute("disabled", "disabled");
        if (domainTrigger) {
          domainTrigger.setAttribute("disabled", "disabled");
        }
        if (domainUi) {
          domainUi.classList.add("is-disabled");
          domainUi.setAttribute("aria-disabled", "true");
        }
        if (domainValue) {
          domainValue.textContent = "No domains";
        }
        closeDomainMenu();
        return;
      }

      domainSelect.removeAttribute("disabled");
      if (domainTrigger) {
        domainTrigger.removeAttribute("disabled");
      }
      if (domainUi) {
        domainUi.classList.remove("is-disabled");
        domainUi.setAttribute("aria-disabled", "false");
      }
      setDomainValues([], false);
    };

    var renderRows = function (rows, fileMeta) {
      if (!tableBodyEl) {
        return;
      }

      if (!Array.isArray(rows) || rows.length === 0) {
        tableBodyEl.innerHTML = '<p class="text-muted small mb-0 px-3 py-3">No readable entries in the selected log file.</p>';
      } else {
        var html = [];
        rows.forEach(function (row) {
          var levelKey = String((row && row.level) || "info").toLowerCase();
          if (!Object.prototype.hasOwnProperty.call(levelUi, levelKey)) {
            levelKey = "info";
          }
          var ui = levelUi[levelKey];
          var levelLabel = ui.label;
          var line = String((row && row.line) || "");
          var desc = String((row && row.description) || "");
          var time = String((row && row.time) || "");
          var raw = String((row && row.raw) || desc);
          var detailMeta = "Service: " + String((fileMeta && fileMeta.service) || "N/A") + " · File: " + String((fileMeta && fileMeta.name) || "N/A") + " · Line: " + line;
          html.push(
            '<details class="ap-logv-entry' + (levelKey === "error" ? " is-error" : "") + '" name="apLogEntry" data-level="' + escapeHtml(levelKey) + '">' +
              '<summary class="ap-logv-row">' +
                '<div class="ap-logv-row-main">' +
                  '<span class="ap-logv-level ' + escapeHtml(ui.className) + '">' +
                    '<i class="bi ' + escapeHtml(ui.icon) + '"></i>' + escapeHtml(levelLabel) +
                  "</span>" +
                  "<span>" + escapeHtml(time) + "</span>" +
                  '<span class="ap-logv-desc">' + escapeHtml(desc) + "</span>" +
                "</div>" +
                '<div class="ap-logv-row-line">' +
                  "<span>" + escapeHtml(line) + "</span>" +
                  '<i class="bi bi-chevron-down ap-logv-row-caret" aria-hidden="true"></i>' +
                "</div>" +
              "</summary>" +
              '<div class="ap-logv-row-detail">' +
                '<p class="ap-logv-detail-meta mb-2">' + escapeHtml(detailMeta) + "</p>" +
                '<p class="ap-logv-detail-label mb-1">Message</p>' +
                '<p class="ap-logv-detail-text mb-2">' + escapeHtml(desc) + "</p>" +
                '<p class="ap-logv-detail-label mb-1">Raw Line</p>' +
                '<pre class="ap-logv-detail-code mb-0">' + escapeHtml(raw) + "</pre>" +
              "</div>" +
            "</details>"
          );
        });
        tableBodyEl.innerHTML = html.join("");
      }

      if (currentStripEl) {
        var stripText = fileMeta ? ("Viewing: " + String(fileMeta.service || "N/A") + " / " + String(fileMeta.name || "N/A")) : "Viewing: none";
        currentStripEl.textContent = stripText;
        currentStripEl.setAttribute("title", stripText);
      }
      if (footerMetaEl) {
        if (fileMeta) {
          footerMetaEl.innerHTML = escapeHtml(String(fileMeta.service || "N/A")) + " <span>.</span> " + escapeHtml(String(fileMeta.name || "N/A")) + " <span>.</span> " + escapeHtml(String(fileMeta.size || "0 B"));
        } else {
          footerMetaEl.textContent = "No active log file selected";
        }
      }

      logEntries = Array.prototype.slice.call(document.querySelectorAll(".ap-logv-entry"));
      bindExclusive(".ap-logv-entry");
      applyLevelFilter(selectedLevelState);
    };

    var loadEntriesAjax = function (token, syncUrl) {
      var normalizedToken = String(token || "").toLowerCase();
      if (normalizedToken === "") {
        setActiveFileByToken("");
        renderRows([], null);
        updateChipCounts({ Debug: 0, Info: 0, Warning: 0, Error: 0 });
        return Promise.resolve();
      }

      return fetchJson(logsEntriesApiUrl + "?file=" + encodeURIComponent(normalizedToken)).then(function (payload) {
        setActiveFileByToken(normalizedToken);
        renderRows(payload.rows || [], payload.file || null);
        updateChipCounts(payload.levelCounts || { Debug: 0, Info: 0, Warning: 0, Error: 0 });
        if (syncUrl) {
          setFileTokenInUrl(normalizedToken);
        }
      }).catch(function () {
        renderRows([], null);
        updateChipCounts({ Debug: 0, Info: 0, Warning: 0, Error: 0 });
      });
    };

    var bindFileClicks = function () {
      refreshFileItems();
      fileItems.forEach(function (fileItem) {
        fileItem.addEventListener("click", function () {
          if (fileItem.classList.contains("is-hidden")) {
            return;
          }
          var token = String(fileItem.dataset.file || "");
          if (token === "") {
            return;
          }
          loadEntriesAjax(token, true);
        });
      });
    };

    var renderServiceOptions = function (services) {
      if (!serviceSelect) {
        return;
      }
      var selected = String(serviceSelect.value || "all").toLowerCase();
      var html = ['<option value="all">All Services</option>'];
      (Array.isArray(services) ? services : []).forEach(function (service) {
        var key = String(service && service.key ? service.key : "").toLowerCase();
        var label = String(service && service.label ? service.label : key);
        if (!key) {
          return;
        }
        html.push('<option value="' + escapeHtml(key) + '">' + escapeHtml(label) + "</option>");
      });
      serviceSelect.innerHTML = html.join("");
      var hasSelected = Array.prototype.some.call(serviceSelect.options, function (opt) {
        return String(opt.value || "").toLowerCase() === selected;
      });
      serviceSelect.value = hasSelected ? selected : "all";
      serviceSelect.disabled = serviceSelect.options.length <= 1;
    };

    var renderFileList = function (files, activeToken) {
      if (!fileListEl) {
        return;
      }
      if (!Array.isArray(files) || files.length === 0) {
        fileListEl.innerHTML = '<p class="text-muted small mb-0 px-2 py-2">No log files found.</p>';
        refreshFileItems();
        return;
      }
      var html = [];
      files.forEach(function (file) {
        var token = String((file && file.token) || "");
        var fileName = String((file && file.name) || "");
        var isLocalhostFile = /^localhost\./i.test(fileName);
        var isCompressedFile = /\.gz$/i.test(fileName);
        var mtimeTs = Number((file && file.mtimeTs) || 0);
        var activeClass = token !== "" && token.toLowerCase() === String(activeToken || "").toLowerCase() ? " is-active" : "";
        html.push(
          '<button class="btn ap-logv-file-item' + activeClass + '" type="button" data-service="' + escapeHtml(String((file && file.serviceKey) || "").toLowerCase()) + '" data-domain="' + escapeHtml(String((file && file.domain) || "").toLowerCase()) + '" data-empty="' + (file && file.isEmpty ? "1" : "0") + '" data-localhost="' + (isLocalhostFile ? "1" : "0") + '" data-compressed="' + (isCompressedFile ? "1" : "0") + '" data-mtime-ts="' + (isFinite(mtimeTs) ? String(Math.round(mtimeTs)) : "0") + '" data-name="' + escapeHtml(fileName) + '" data-file="' + escapeHtml(token) + '">' +
            '<span class="ap-logv-file-top">' +
              '<span class="ap-logv-file-name" title="' + escapeHtml(fileName) + '">' + escapeHtml(fileName) + "</span>" +
              '<span class="ap-logv-file-size">' + escapeHtml(String((file && file.size) || "0 B")) + "</span>" +
            "</span>" +
            '<span class="ap-logv-file-meta">' +
              '<span class="ap-logv-file-mtime">' + escapeHtml(String((file && file.mtime) || "Unknown")) + "</span>" +
              '<span class="ap-logv-file-service">' + escapeHtml(String((file && file.service) || "UNKNOWN")) + "</span>" +
            "</span>" +
          "</button>"
        );
      });
      fileListEl.innerHTML = html.join("");
      bindFileClicks();
      setActiveFileByToken(activeToken || "");
    };

    var loadFilesAjax = function () {
      var requestedToken = fileTokenFromUrl();
      var endpoint = logsFilesApiUrl + (requestedToken ? ("?file=" + encodeURIComponent(requestedToken)) : "");
      return fetchJson(endpoint).then(function (payload) {
        serviceDomains = payload.domains && typeof payload.domains === "object" ? payload.domains : {};
        renderServiceOptions(payload.services || []);
        renderFileList(payload.files || [], payload.activeToken || requestedToken);
        updateDomainSelector(serviceSelect ? (serviceSelect.value || "all") : "all");
        if (rootsTextEl && payload.rootsText) {
          rootsTextEl.textContent = "Filter by service/domain and inspect recent entries instantly.";
        }
        return applyServiceFilter(false).then(function () {
          var activeVisible = getActiveVisibleFile();
          var token = requestedToken
            || (activeVisible ? String(activeVisible.dataset.file || "") : "")
            || String(payload.activeToken || "");
          if (token !== "") {
            return loadEntriesAjax(token, false);
          }
          renderRows([], null);
          updateChipCounts({ Debug: 0, Info: 0, Warning: 0, Error: 0 });
          return Promise.resolve();
        });
      });
    };

    var updateDomainSelector = function (serviceValue) {
      if (!domainWrap || !domainSelect) {
        return;
      }

      var normalizedService = String(serviceValue || "all").toLowerCase();
      var shouldShow = Object.prototype.hasOwnProperty.call(domainEnabledServices, normalizedService);
      domainWrap.classList.toggle("is-hidden", !shouldShow);

      if (!shouldShow) {
        closeDomainMenu();
        domainSelect.setAttribute("disabled", "disabled");
        if (domainTrigger) {
          domainTrigger.setAttribute("disabled", "disabled");
        }
        if (domainUi) {
          domainUi.classList.add("is-disabled");
          domainUi.setAttribute("aria-disabled", "true");
        }
        if (domainValue) {
          domainValue.textContent = "All Domains";
        }
        domainSelect.innerHTML = "";
        if (domainMenu) {
          domainMenu.innerHTML = "";
        }
        return;
      }

      buildDomainOptions(normalizedService);
    };

    var applyServiceFilter = function (autoLoad) {
      if (typeof autoLoad === "undefined") {
        autoLoad = true;
      }
      if (!serviceSelect) {
        return Promise.resolve();
      }
      var selectedService = String(serviceSelect.value || "all").toLowerCase();
      var selectedDomains = [];
      var filterState = getCurrentFileFilterState();
      if (domainWrap && domainSelect && !domainWrap.classList.contains("is-hidden")) {
        selectedDomains = getSelectedDomains();
        refreshDomainOptionCounts(selectedService);
      }

      var firstVisible = null;
      fileItems.forEach(function (fileItem) {
        var itemDomain = String(fileItem.dataset.domain || "").toLowerCase();
        var serviceVisible = fileMatchesBaseFilters(fileItem, selectedService, filterState);
        var domainVisible = selectedDomains.length === 0 || selectedDomains.indexOf(itemDomain) !== -1;
        var isVisible = serviceVisible && domainVisible;
        fileItem.classList.toggle("is-hidden", !isVisible);
        if (isVisible && firstVisible === null) {
          firstVisible = fileItem;
        }
      });
      var activeVisible = getActiveVisibleFile();
      if (!activeVisible && firstVisible) {
        var firstToken = String(firstVisible.dataset.file || "");
        setActiveFileByToken(firstToken);
        if (autoLoad) {
          return loadEntriesAjax(firstToken, true);
        }
      } else if (activeVisible && autoLoad) {
        var activeToken = String(activeVisible.dataset.file || "");
        if (activeToken !== "" && activeToken !== activeFileToken) {
          return loadEntriesAjax(activeToken, true);
        }
      }
      if (!firstVisible) {
        setActiveFileByToken("");
        renderRows([], null);
        updateChipCounts({ Debug: 0, Info: 0, Warning: 0, Error: 0 });
      }
      return Promise.resolve();
    };

    var applyLevelFilter = function (selectedLevel) {
      var normalizedLevel = String(selectedLevel || "all").toLowerCase();
      selectedLevelState = normalizedLevel;
      levelChips.forEach(function (chip) {
        var chipLevel = String(chip.dataset.level || "").toLowerCase();
        chip.classList.toggle("is-active", chipLevel === normalizedLevel);
      });
      applyEntryFilters();
    };

    if (serviceSelect) {
      serviceSelect.addEventListener("change", function () {
        updateDomainSelector(serviceSelect.value || "all");
        applyServiceFilter(true);
      });
      if (domainTrigger && domainMenu && domainUi) {
        domainTrigger.addEventListener("click", function () {
          if (domainUi.classList.contains("is-disabled")) {
            return;
          }
          var open = !domainMenu.hidden;
          if (open) {
            closeDomainMenu();
            return;
          }
          domainMenu.hidden = false;
          domainTrigger.setAttribute("aria-expanded", "true");
          domainUi.classList.add("is-open");
        });
      }
      if (domainSelect) {
        domainSelect.addEventListener("change", function () {
          refreshDomainMenuState();
          applyServiceFilter(true);
        });
      }
    }
    if (filterBtnEl) {
      filterBtnEl.addEventListener("click", function (event) {
        event.preventDefault();
        toggleFilterMenu();
      });
    }
    [filterHideEmptyEl, filterHideLocalhostEl, filterHideCompressedEl].forEach(function (node) {
      if (!node) {
        return;
      }
      node.addEventListener("change", function () {
        applyServiceFilter(true);
      });
    });
    if (filterDateFromEl) {
      filterDateFromEl.addEventListener("change", function () {
        applyServiceFilter(true);
      });
    }
    if (filterDateToEl) {
      filterDateToEl.addEventListener("change", function () {
        applyServiceFilter(true);
      });
    }
    if (filterDateClearEl) {
      filterDateClearEl.addEventListener("click", function () {
        if (filterDateFromEl) {
          filterDateFromEl.value = "";
        }
        if (filterDateToEl) {
          filterDateToEl.value = "";
        }
        applyServiceFilter(true);
      });
    }
    if (searchInputEl) {
      searchInputEl.addEventListener("input", function () {
        if (searchDebounceTimer !== null) {
          window.clearTimeout(searchDebounceTimer);
        }
        searchDebounceTimer = window.setTimeout(function () {
          applyEntryFilters();
          searchDebounceTimer = null;
        }, 120);
      });
      searchInputEl.addEventListener("keydown", function (event) {
        if (event.key === "Enter") {
          event.preventDefault();
          if (searchDebounceTimer !== null) {
            window.clearTimeout(searchDebounceTimer);
            searchDebounceTimer = null;
          }
          applyEntryFilters();
        }
      });
    }
    if (regexModeEl) {
      regexModeEl.addEventListener("change", function () {
        applyEntryFilters();
      });
    }
    if (caseSensitiveEl) {
      caseSensitiveEl.addEventListener("change", function () {
        applyEntryFilters();
      });
    }
    if (refreshBtnEl) {
      refreshBtnEl.addEventListener("click", function () {
        refreshData();
      });
    }
    if (settingsBtnEl) {
      settingsBtnEl.addEventListener("click", function (event) {
        event.preventDefault();
        toggleSettingsMenu();
      });
    }
    document.addEventListener("click", function (event) {
      if (domainUi && !domainUi.contains(event.target)) {
        closeDomainMenu();
      }
      if (filterWrapEl && !filterWrapEl.contains(event.target)) {
        closeFilterMenu();
      }
      if (settingsWrapEl && !settingsWrapEl.contains(event.target)) {
        closeSettingsMenu();
      }
    });
    document.addEventListener("keydown", function (event) {
      if (event.key === "Escape") {
        closeDomainMenu();
        closeFilterMenu();
        closeSettingsMenu();
      }
    });

    levelChips.forEach(function (chip) {
      chip.addEventListener("click", function () {
        applyLevelFilter(chip.dataset.level || "all");
      });
    });
    applyLevelFilter("all");
    bindFileClicks();
    loadFilesAjax().catch(recoverFromLoadError);
  });
</script>
