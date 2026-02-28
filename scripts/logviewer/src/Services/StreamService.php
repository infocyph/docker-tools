<?php
declare(strict_types=1);

namespace LogViewer\Services;

final class StreamService
{
    public function __construct(
        private readonly LogScanner $scanner,
        private readonly EntriesService $entries,
    ) {}

    /**
     * Merge newest entries across all log files of a service, best-effort by timestamp.
     *
     * @return array{meta:array<string,mixed>,items:list<array<string,mixed>>}
     */
    public function stream(string $service, int $limitEntries = 200, int $sinceMinutes = 0): array
    {
        $service = trim($service);
        if ($service === '') throw new \RuntimeException('missing service');

        $limitEntries = max(50, min(2000, $limitEntries));
        $cut = ($sinceMinutes > 0) ? (time() - ($sinceMinutes * 60)) : 0;

        $files = $this->scanner->listFiles();
        $svcLower = strtolower($service);
        $svcFiles = array_values(array_filter($files, static function ($f) use ($svcLower) {
            return strtolower((string)($f['service'] ?? '')) === $svcLower;
        }));

        // Prioritize newest files first; read only a subset to keep it fast.
        usort($svcFiles, static fn($a, $b) => ((int)($b['mtime'] ?? 0) <=> (int)($a['mtime'] ?? 0)));
        $svcFiles = array_slice($svcFiles, 0, 20); // cap

        $merged = [];
        $seen = 0;

        foreach ($svcFiles as $f) {
            $path = (string)$f['path'];
            if ($path === '') continue;

            // Use cached loader; it already tails + parses efficiently.
            $payload = $this->entries->loadCached($path, 2);
            $items = array_reverse((array)($payload['entries'] ?? [])); // newest first

            $display = $this->scanner->displayPath($path);
            $name = (string)($f['name'] ?? basename($path));

            foreach ($items as $it) {
                $ts = (string)($it['ts'] ?? '');
                $t = $ts !== '' ? strtotime($ts) : false;

                if ($cut > 0 && $t !== false && $t < $cut) continue;

                $it['source'] = [
                    'service' => (string)($f['service'] ?? $service),
                    'name' => $name,
                    'path' => $path,
                    'display_path' => $display,
                ];
                $it['_t'] = ($t !== false) ? (int)$t : (int)($f['mtime'] ?? 0);
                $merged[] = $it;
                $seen++;

                // keep memory bounded
                if ($seen >= ($limitEntries * 30)) break;
            }
        }

        usort($merged, static fn($a, $b) => ((int)($b['_t'] ?? 0) <=> (int)($a['_t'] ?? 0)));
        $merged = array_slice($merged, 0, $limitEntries);

        // strip internal
        foreach ($merged as &$m) unset($m['_t']);
        unset($m);

        return [
            'meta' => [
                'service' => $service,
                'limit' => $limitEntries,
                'since_minutes' => $sinceMinutes,
                'files_considered' => count($svcFiles),
                'generated_at' => time(),
            ],
            'items' => $merged,
        ];
    }
}
