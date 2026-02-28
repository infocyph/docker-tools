<?php
declare(strict_types=1);

namespace LogViewer\Services;

final class StatsService
{
    public function __construct(
        private readonly LogScanner $scanner,
        private readonly Cache $cache,
        private readonly TailReader $tail,
        private readonly LogParser $parser,
        private readonly int $dashTailLines = 5000,
    ) {}

    /** @return array{total:int,by_dir:array<string,int>} */
    public function fileCountsByService(): array
    {
        $files = $this->scanner->listFiles();

        $by = [];
        foreach ($files as $f) {
            $dir = trim((string)($f['service'] ?? 'logs'));
            if ($dir === '') $dir = 'logs';
            $by[$dir] = ($by[$dir] ?? 0) + 1;
        }

        ksort($by, SORT_NATURAL | SORT_FLAG_CASE);

        return ['total' => count($files), 'by_dir' => $by];
    }

    /** @return array{sampled_files:int,counts:array<string,int>,last_generated_at:int,total_files:int} */
    public function dashboardLogStats(int $ttl, int $maxFiles = 20): array
    {
        $files = array_slice($this->scanner->listFiles(), 0, max(1, $maxFiles));

        $sum = ['debug' => 0, 'info' => 0, 'warn' => 0, 'error' => 0];
        $sampled = 0;
        $last = 0;

        foreach ($files as $f) {
            $payload = $this->loadCachedEntries($f['path'], $ttl);
            $c = $payload['meta']['counts'] ?? [];
            foreach ($sum as $k => $_) $sum[$k] += (int)($c[$k] ?? 0);
            $last = max($last, (int)($payload['meta']['generated_at'] ?? 0));
            $sampled++;
        }

        return [
            'sampled_files' => $sampled,
            'counts' => $sum,
            'last_generated_at' => $last,
            'total_files' => count($this->scanner->listFiles()),
        ];
    }

    /** @return array{meta:array<string,mixed>,entries:list<array<string,mixed>>} */
    public function loadCachedEntries(string $file, int $ttl): array
    {
        $st = @stat($file);
        $fileSize = (is_array($st) && isset($st['size'])) ? (int)$st['size'] : 0;
        $fileMtime = (is_array($st) && isset($st['mtime'])) ? (int)$st['mtime'] : 0;

        $key = 'entries|' . $file;

        $cached = $this->cache->get($key);
        if (is_array($cached) && isset($cached['entries'], $cached['meta'])) {
            $cm = (array)($cached['meta'] ?? []);
            $cSize = (int)($cm['size'] ?? -1);
            $cMtime = (int)($cm['mtime'] ?? -1);
            $cTotal = (int)($cm['total'] ?? 0);

            $cacheMatches = ($cSize === $fileSize && $cMtime === $fileMtime);
            $cacheNotBadEmpty = !($fileSize > 0 && $cTotal === 0);

            if ($cacheMatches && $cacheNotBadEmpty) {
                return $cached;
            }
        }

        [$code, $out, $err] = $this->tail->tailText($file, $this->dashTailLines);
        if ($code !== 0) {
            throw new \RuntimeException(trim($err) ?: 'read failed');
        }

        $entries = $this->parser->parseEntries($out);
        $counts = $this->parser->counts($entries);

        $payload = [
            'meta' => [
                'file' => $file,
                'gz' => $this->tail->isGz($file),
                'generated_at' => time(),
                'counts' => $counts,
                'total' => count($entries),
                'size' => $fileSize,
                'mtime' => $fileMtime,
            ],
            'entries' => $entries,
        ];

        $this->cache->set($key, $payload);
        return $payload;
    }
}

