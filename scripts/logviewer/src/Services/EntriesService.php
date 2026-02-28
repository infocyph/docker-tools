<?php
declare(strict_types=1);

namespace LogViewer\Services;

final class EntriesService
{
    public function __construct(
        private readonly Cache $cache,
        private readonly TailReader $tail,
        private readonly LogParser $parser,
        private readonly int $maxTailLines,
    ) {}

    /** @return array{meta:array<string,mixed>,entries:list<array<string,mixed>>} */
    public function loadCached(string $file, int $ttl): array
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

        [$code, $out, $err] = $this->tail->tailText($file, $this->maxTailLines);
        if ($code !== 0) throw new \RuntimeException(trim($err) ?: 'read failed');

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
