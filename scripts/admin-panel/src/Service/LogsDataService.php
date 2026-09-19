<?php
declare(strict_types=1);

namespace AdminPanel\Service;

use AdminPanel\Support\ProcessRunner;
use DateTimeImmutable;
use FilesystemIterator;
use RecursiveDirectoryIterator;
use RecursiveIteratorIterator;
use Throwable;

final class LogsDataService
{
    /** @var array<string,bool> */
    private array $domainScopedServices = [
        'nginx' => true,
        'apache' => true,
        'php-fpm' => true,
    ];

    /** @var list<string> */
    private array $logRoots;

    /** @param list<string>|null $roots */
    public function __construct(?array $roots = null)
    {
        if ($roots !== null && $roots !== []) {
            $this->logRoots = $roots;
            return;
        }

        $configuredRootsRaw = trim((string)(getenv('ADMIN_PANEL_LOG_ROOTS') ?: getenv('LOGVIEW_ROOTS') ?: ''));
        $configuredRoots = array_values(array_filter(
            array_map(static fn(string $v): string => trim($v), explode(':', $configuredRootsRaw)),
            static fn(string $v): bool => $v !== ''
        ));
        if ($configuredRoots === []) {
            $configuredRoots = ['/global/log'];
        }

        $localLogsFallback = dirname(__DIR__, 4) . DIRECTORY_SEPARATOR . 'logs';
        if (!is_dir('/global/log') && is_dir($localLogsFallback) && !in_array($localLogsFallback, $configuredRoots, true)) {
            $configuredRoots[] = $localLogsFallback;
        }

        $this->logRoots = $configuredRoots;
    }

    /** @return array<string,mixed> */
    public function listFilesPayload(string $selectedToken = ''): array
    {
        $scan = $this->scan();
        $files = $scan['files'];
        $selectedToken = strtolower(trim($selectedToken));
        if (preg_match('/^[a-f0-9]{40}$/', $selectedToken) !== 1) {
            $selectedToken = '';
        }

        return [
            'rootsText' => $scan['rootsText'],
            'services' => $scan['services'],
            'domains' => $scan['domains'],
            'files' => $files,
            'activeToken' => $this->resolveActiveToken($files, $selectedToken),
        ];
    }

    /** @return array<string,mixed> */
    public function entriesPayload(string $token): array
    {
        $token = strtolower(trim($token));
        if (preg_match('/^[a-f0-9]{40}$/', $token) !== 1) {
            return $this->emptyEntries();
        }

        $scan = $this->scan();
        $selectedFile = null;
        foreach ($scan['files'] as $file) {
            if (hash_equals((string)$file['token'], $token)) {
                $selectedFile = $file;
                break;
            }
        }
        if (!is_array($selectedFile)) {
            return $this->emptyEntries();
        }

        $lines = $this->readTailLines((string)$selectedFile['path'], 250, 3 * 1024 * 1024);
        $rows = [];
        $lineIndex = count($lines);
        for ($i = count($lines) - 1; $i >= 0; --$i) {
            $raw = trim((string)$lines[$i]);
            if ($raw === '') {
                --$lineIndex;
                continue;
            }
            $level = $this->detectLevel($raw);
            $timeTs = $this->extractTimeEpoch($raw);
            if ($timeTs <= 0) {
                $timeTs = (int)$selectedFile['mtimeTs'];
            }
            $time = $timeTs > 0 ? date('Y-m-d H:i:s', $timeTs) : (string)$selectedFile['mtime'];
            $rows[] = [
                'level' => $level,
                'time' => $time,
                'timeTs' => $timeTs,
                'description' => $this->normalizeDescription($raw),
                'line' => number_format(max($lineIndex, 1)),
                'raw' => $raw,
            ];
            --$lineIndex;
        }

        $levelCounts = ['Debug' => 0, 'Info' => 0, 'Warning' => 0, 'Error' => 0];
        foreach ($rows as $row) {
            $level = (string)($row['level'] ?? 'Info');
            if (isset($levelCounts[$level])) {
                ++$levelCounts[$level];
            }
        }

        return [
            'found' => true,
            'file' => [
                'token' => (string)$selectedFile['token'],
                'name' => (string)$selectedFile['name'],
                'size' => (string)$selectedFile['size'],
                'sizeBytes' => (int)$selectedFile['sizeBytes'],
                'mtime' => (string)$selectedFile['mtime'],
                'mtimeTs' => (int)$selectedFile['mtimeTs'],
                'service' => (string)$selectedFile['service'],
                'serviceKey' => (string)$selectedFile['serviceKey'],
                'domain' => (string)$selectedFile['domain'],
            ],
            'rows' => $rows,
            'levelCounts' => $levelCounts,
        ];
    }

    /** @return array<string,mixed> */
    private function emptyEntries(): array
    {
        return [
            'found' => false,
            'file' => null,
            'rows' => [],
            'levelCounts' => ['Debug' => 0, 'Info' => 0, 'Warning' => 0, 'Error' => 0],
        ];
    }

    /** @return array<string,mixed> */
    private function scan(): array
    {
        $serviceMap = [];
        $serviceDomains = [];
        $files = [];
        $activeRoots = [];

        foreach ($this->logRoots as $rootCandidate) {
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
                $currentServiceKey = $this->serviceKey($dirName);
                $currentServiceLabel = $this->serviceLabel($dirName);
                $serviceMap[$currentServiceKey] = $currentServiceLabel;

                foreach ($this->findFiles($dirPath, 1, 3) as $path) {
                    $name = basename($path);
                    if (str_starts_with($name, '.')) {
                        continue;
                    }

                    $domain = '';
                    if (isset($this->domainScopedServices[$currentServiceKey])) {
                        $domain = (string)($this->extractDomain($name) ?? '');
                        if ($domain !== '') {
                            $serviceDomains[$currentServiceKey][$domain] = (int)($serviceDomains[$currentServiceKey][$domain] ?? 0) + 1;
                        }
                    }

                    $stat = @stat($path) ?: [];
                    $size = (int)($stat['size'] ?? 0);
                    $mtime = (int)($stat['mtime'] ?? 0);
                    $files[] = [
                        'token' => sha1($path),
                        'name' => $name,
                        'path' => $path,
                        'size' => $this->formatBytes($size),
                        'sizeBytes' => $size,
                        'mtime' => $mtime > 0 ? date('Y-m-d H:i:s', $mtime) : 'Unknown',
                        'mtimeTs' => $mtime,
                        'service' => $currentServiceLabel,
                        'serviceKey' => $currentServiceKey,
                        'domain' => $domain,
                        'isEmpty' => $this->isEmptyFile($name, $size),
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
        usort($files, static function (array $a, array $b): int {
            return ((int)$b['mtimeTs'] <=> (int)$a['mtimeTs']) ?: strnatcasecmp((string)$a['name'], (string)$b['name']);
        });

        return [
            'rootsText' => $activeRoots === [] ? '/global/log' : implode(', ', array_keys($activeRoots)),
            'services' => $services,
            'domains' => $serviceDomains,
            'files' => $files,
        ];
    }

    /** @param list<array{token:string,isEmpty:bool}> $files */
    private function resolveActiveToken(array $files, string $selectedToken): string
    {
        if ($selectedToken !== '') {
            foreach ($files as $file) {
                if (hash_equals((string)$file['token'], $selectedToken)) {
                    return (string)$file['token'];
                }
            }
        }
        foreach ($files as $file) {
            if (!(bool)$file['isEmpty']) {
                return (string)$file['token'];
            }
        }
        return isset($files[0]['token']) ? (string)$files[0]['token'] : '';
    }

    private function formatBytes(int $bytes): string
    {
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
    }

    private function isEmptyFile(string $name, int $sizeBytes): bool
    {
        if ($sizeBytes <= 0) {
            return true;
        }
        return preg_match('/\.gz$/i', $name) === 1 && $sizeBytes <= 20;
    }

    private function serviceLabel(string $raw): string
    {
        $clean = trim((string)(preg_replace('/[^a-zA-Z0-9]+/', ' ', $raw) ?? $raw));
        return $clean === '' ? 'UNKNOWN' : strtoupper($clean);
    }

    private function serviceKey(string $raw): string
    {
        $clean = strtolower(trim((string)(preg_replace('/[^a-zA-Z0-9]+/', '-', $raw) ?? $raw), '-'));
        return $clean !== '' ? $clean : 'unknown';
    }

    private function extractDomain(string $fileName): ?string
    {
        $normalized = preg_replace('/\.gz$/i', '', strtolower(trim($fileName))) ?? strtolower(trim($fileName));
        if ($normalized === '') {
            return null;
        }
        if (preg_match('/^(.+)\.(access|error)\.log(?:[-.].*)?$/i', $normalized, $matches) === 1) {
            $domain = trim((string)$matches[1], '.- ');
            return $domain !== '' ? $domain : null;
        }
        if (preg_match('/^(.+)\.log(?:[-.].*)?$/i', $normalized, $matches) === 1) {
            $domain = trim((string)$matches[1], '.- ');
            if ($domain === '' || in_array($domain, ['access', 'error'], true)) {
                return null;
            }
            return $domain;
        }
        return null;
    }

    /** @return list<string> */
    private function findFiles(string $dir, int $minDepth, int $maxDepth): array
    {
        $dir = rtrim($dir, DIRECTORY_SEPARATOR);
        if ($dir === '' || !is_dir($dir)) {
            return [];
        }
        $minDepth = max(0, $minDepth);
        $maxDepth = max($minDepth, $maxDepth);

        $native = ProcessRunner::run(
            [
                'find',
                $dir,
                '-mindepth', (string)$minDepth,
                '-maxdepth', (string)$maxDepth,
                '-type', 'f',
                '-print0',
            ],
            5,
            null,
            16 * 1024 * 1024
        );

        if ($native['ok']) {
            $out = (string)$native['stdout'];
            if ($out === '') {
                return [];
            }

            $res = [];
            foreach (explode("\0", $out) as $path) {
                if ($path !== '' && is_file($path)) {
                    $res[] = $path;
                }
            }
            return $res;
        }

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
    }

    /** @return list<string> */
    private function readTailLines(string $path, int $maxLines = 250, int $maxBytes = 2097152): array
    {
        if (!is_file($path) || !is_readable($path)) {
            return [];
        }
        if (preg_match('/\.gz$/i', $path) === 1) {
            return $this->readGzipTailLines($path, $maxLines, $maxBytes);
        }
        return $this->readRegularTailLines($path, $maxLines, $maxBytes);
    }

    /** @return list<string> */
    private function readRegularTailLines(string $path, int $maxLines, int $maxBytes): array
    {
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
        return $this->splitTailBuffer($buffer, $maxLines);
    }

    /** @return list<string> */
    private function readGzipTailLines(string $path, int $maxLines, int $maxBytes): array
    {
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
        return $this->splitTailBuffer($buffer, $maxLines);
    }

    /** @return list<string> */
    private function splitTailBuffer(string $buffer, int $maxLines): array
    {
        $lines = preg_split('/\r\n|\r|\n/', $buffer) ?: [];
        if ($lines !== [] && trim((string)end($lines)) === '') {
            array_pop($lines);
        }
        if (count($lines) > $maxLines) {
            $lines = array_slice($lines, -$maxLines);
        }
        return $lines;
    }

    private function detectLevel(string $line): string
    {
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
    }

    private function extractTimeEpoch(string $line): int
    {
        if (preg_match('/\b(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:[.,]\d+)?(?:Z|[+-]\d{2}:?\d{2}))\b/', $line, $matches) === 1) {
            $value = str_replace(',', '.', (string)$matches[1]);
            try {
                return (new DateTimeImmutable($value))->getTimestamp();
            } catch (Throwable) {
                // Continue with timezone-naive formats below.
            }
        }
        if (preg_match('/\b(\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2}(?:[.,]\d+)?)\b/', $line, $matches) === 1) {
            $value = str_replace(['T', ','], [' ', '.'], (string)$matches[1]);
            foreach (['!Y-m-d H:i:s.u', '!Y-m-d H:i:s'] as $format) {
                $dt = DateTimeImmutable::createFromFormat($format, $value);
                if ($dt !== false) {
                    return $dt->getTimestamp();
                }
            }
        }
        if (preg_match('/\b(\d{2}\/[A-Za-z]{3}\/\d{4}:\d{2}:\d{2}:\d{2}\s[+-]\d{4})\b/', $line, $matches) === 1) {
            $dt = DateTimeImmutable::createFromFormat('!d/M/Y:H:i:s O', (string)$matches[1]);
            if ($dt !== false) {
                return $dt->getTimestamp();
            }
        }
        if (preg_match('/\b(\d{2}-[A-Za-z]{3}-\d{4}\s\d{2}:\d{2}:\d{2})\b/', $line, $matches) === 1) {
            $dt = DateTimeImmutable::createFromFormat('!d-M-Y H:i:s', (string)$matches[1]);
            if ($dt !== false) {
                return $dt->getTimestamp();
            }
        }
        return 0;
    }

    private function normalizeDescription(string $line): string
    {
        $desc = trim($line);
        $desc = preg_replace('/^\[[^\]]+\]\s*[A-Za-z0-9_.-]+\.[A-Z]+:\s*/', '', $desc) ?? $desc;
        $desc = preg_replace('/^\[[^\]]+\]\s*/', '', $desc) ?? $desc;
        $desc = preg_replace('/^\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2}(?:[.,]\d+)?\s*/', '', $desc) ?? $desc;
        $desc = trim($desc);
        if ($desc === '') {
            return '(empty message)';
        }
        return strlen($desc) > 320 ? substr($desc, 0, 317) . '...' : $desc;
    }
}
