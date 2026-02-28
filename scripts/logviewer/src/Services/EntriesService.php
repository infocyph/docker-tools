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

    /**
     * Cache + (best-effort) incremental refresh:
     * - Cache key includes file mtime/size.
     * - If file grew and we have a previous cache payload, we only read an overlap window
     *   from the end and append parsed entries, then trim to maxTailLines.
     *
     * @return array{meta:array<string,mixed>,entries:list<array<string,mixed>>}
     */
    public function loadCached(string $file, int $ttl): array
    {
        $t0 = hrtime(true);

        $st = @stat($file) ?: [];
        $fileSize = (int)($st['size'] ?? 0);
        $fileMtime = (int)($st['mtime'] ?? 0);

        $key = 'entries|' . $file . '|' . $fileMtime . '|' . $fileSize;

        $cached = $this->cache->get($key);
        if (is_array($cached) && isset($cached['entries'], $cached['meta'])) {
            $cached['meta']['timing'] = ['load_ms' => (int)((hrtime(true)-$t0)/1_000_000)];
            return $cached;
        }

        // Try to find the most recent cached payload for this file to do an incremental update.
        $prev = $this->cache->getLatestByPrefix('entries|' . $file . '|');

        if (is_array($prev) && isset($prev['entries'], $prev['meta'])) {
            $pm = (array)($prev['meta'] ?? []);
            $pSize = (int)($pm['size'] ?? -1);
            $pMtime = (int)($pm['mtime'] ?? -1);

            // If the file only appended data, attempt a cheap delta read with overlap.
            if ($pSize >= 0 && $fileSize >= $pSize && $fileMtime >= $pMtime) {
                $overlap = 128 * 1024; // bytes
                $from = max(0, $pSize - $overlap);

                $tRead = hrtime(true);
                $chunk = $this->readFromOffset($file, $from, 8 * 1024 * 1024); // cap
                $tailMs = (int)((hrtime(true)-$tRead)/1_000_000);

                // Parse only the chunk, append, then keep last N entries.
                $tParse = hrtime(true);
                $deltaEntries = $this->parser->parseEntries($chunk);
                $parseMs = (int)((hrtime(true)-$tParse)/1_000_000);

                $merged = array_merge((array)$prev['entries'], $deltaEntries);
                if (count($merged) > ($this->maxTailLines * 2)) {
                    // keep memory bounded (entries are not 1:1 with lines)
                    $merged = array_slice($merged, -($this->maxTailLines * 2));
                }

                $counts = $this->parser->counts($merged);

                $payload = [
                    'meta' => [
                        'file' => $file,
                        'gz' => $this->tail->isGz($file),
                        'generated_at' => time(),
                        'counts' => $counts,
                        'total' => count($merged),
                        'size' => $fileSize,
                        'mtime' => $fileMtime,
                        'incremental' => true,
                        'timing' => [
                            'tail_ms' => $tailMs,
                            'parse_ms' => $parseMs,
                            'load_ms' => (int)((hrtime(true)-$t0)/1_000_000),
                        ],
                    ],
                    'entries' => $merged,
                ];

                $this->cache->set($key, $payload);
                return $payload;
            }
        }

        // Full refresh fallback (tail last N lines)
        $tRead = hrtime(true);
        [$code, $out, $err] = $this->tail->tailText($file, $this->maxTailLines);
        $tailMs = (int)((hrtime(true)-$tRead)/1_000_000);

        if ($code !== 0) throw new \RuntimeException(trim($err) ?: 'read failed');

        $tParse = hrtime(true);
        $entries = $this->parser->parseEntries($out);
        $parseMs = (int)((hrtime(true)-$tParse)/1_000_000);

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
                'incremental' => false,
                'timing' => [
                    'tail_ms' => $tailMs,
                    'parse_ms' => $parseMs,
                    'load_ms' => (int)((hrtime(true)-$t0)/1_000_000),
                ],
            ],
            'entries' => $entries,
        ];

        $this->cache->set($key, $payload);
        return $payload;
    }

    private function readFromOffset(string $file, int $offset, int $maxBytes): string
    {
        $fp = @fopen($file, 'rb');
        if (!$fp) return '';

        if ($offset > 0) @fseek($fp, $offset, SEEK_SET);

        $buf = '';
        while (!feof($fp) && strlen($buf) < $maxBytes) {
            $chunk = fread($fp, 8192);
            if ($chunk === false || $chunk === '') break;
            $buf .= $chunk;
        }
        fclose($fp);
        return $buf;
    }
}

