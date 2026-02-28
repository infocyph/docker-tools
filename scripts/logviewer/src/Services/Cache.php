<?php
declare(strict_types=1);

namespace LogViewer\Services;

final class Cache
{
    public function __construct(
        private readonly string $dir = '/tmp',
        private readonly int $ttl = 2,
    ) {}

    private function path(string $key): string
    {
        return rtrim($this->dir, '/') . '/logviewer_' . hash('sha256', $key) . '.json';
    }

    /** @return array<string,mixed>|null */
    public function get(string $key): ?array
    {
        $p = $this->path($key);
        if (!is_file($p)) return null;

        $st = @stat($p);
        if (!$st) return null;
        if ((time() - (int)$st['mtime']) > $this->ttl) return null;

        $raw = @file_get_contents($p);
        if (!is_string($raw)) return null;

        $j = json_decode($raw, true);
        return is_array($j) ? $j : null;
    }

    public function getLatestByPrefix(string $prefix): ?array
    {
        $p = rtrim($this->dir, '/') . '/logviewer_latest_' . hash('sha256', $prefix) . '.txt';
        $k = is_file($p) ? trim((string)@file_get_contents($p)) : '';
        if ($k === '') return null;
        return $this->get($k);
    }

    /** @param array<string,mixed> $value */
    public function set(string $key, array $value): void
    {
        $p = $this->path($key);
        @file_put_contents($p, json_encode($value, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE), LOCK_EX);

        // pointer for incremental refresh (latest key per file)
        if (str_starts_with($key, 'entries|')) {
            // prefix: entries|<file>|
            $parts = explode('|', $key, 4);
            if (count($parts) >= 3) {
                $prefix = $parts[0] . '|' . $parts[1] . '|';
                $lp = rtrim($this->dir, '/') . '/logviewer_latest_' . hash('sha256', $prefix) . '.txt';
                @file_put_contents($lp, $key, LOCK_EX);
            }
        }
    }
}


