<?php
declare(strict_types=1);

namespace LogViewer\Core;

final class Request
{
    /** @param array<string, string> $query */
    public function __construct(
        public readonly string $method,
        public readonly string $path,
        public readonly array $query,
        /** @var array<string, string> */
        public readonly array $server,
    ) {}

    public static function fromGlobals(): self
    {
        $uri = (string)($_SERVER['REQUEST_URI'] ?? '/');
        $path = parse_url($uri, PHP_URL_PATH) ?: '/';

        $q = [];
        foreach ($_GET as $k => $v) {
            if (!is_string($k)) continue;
            if (is_array($v)) continue;
            $q[$k] = (string)$v;
        }

        return new self(
            strtoupper((string)($_SERVER['REQUEST_METHOD'] ?? 'GET')),
            $path,
            $q,
            array_map('strval', $_SERVER),
        );
    }

    public function ip(): string
    {
        return $this->server['REMOTE_ADDR'] ?? 'unknown';
    }

    public function get(string $key, string $default = ''): string
    {
        $v = $this->query[$key] ?? $default;
        return is_string($v) ? $v : $default;
    }

    public function int(string $key, int $default, int $min, int $max): int
    {
        $n = (int)($this->query[$key] ?? $default);
        if ($n < $min) return $min;
        if ($n > $max) return $max;
        return $n;
    }
}
