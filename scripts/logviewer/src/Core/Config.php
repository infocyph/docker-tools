<?php
declare(strict_types=1);

namespace LogViewer\Core;

final class Config
{
    public readonly bool $debug;
    /** @var list<string> */
    public readonly array $roots;
    public readonly string $nginxVhostDir;

    public readonly int $maxTailLines;
    public readonly int $cacheTtl;
    public readonly int $dashTail;
    public readonly int $rawDefaultMaxBytes;

    public function __construct()
    {
        $this->debug = filter_var(getenv('LOGVIEW_DEBUG') ?: '0', FILTER_VALIDATE_BOOL);

        $roots = array_map('trim', explode(':', getenv('LOGVIEW_ROOTS') ?: '/global/log'));
        $roots = array_values(array_filter($roots, static fn($v) => $v !== ''));
        $this->roots = $roots ?: ['/global/log'];

        $this->nginxVhostDir = getenv('NGINX_VHOST_DIR') ?: '/etc/share/vhosts/nginx';

        $this->cacheTtl = max(1, (int)(getenv('LOGVIEW_CACHE_TTL') ?: 2));
        $this->maxTailLines = max(2000, (int)(getenv('LOGVIEW_MAX_TAIL_LINES') ?: self::defaultTailLines()));
        $this->dashTail = max(2000, (int)(getenv('LOGVIEW_DASH_TAIL') ?: 5000));
        $this->rawDefaultMaxBytes = max(1024 * 1024, (int)(getenv('LOGVIEW_RAW_MAX_BYTES') ?: (32 * 1024 * 1024)));
    }

    private static function detectMemMb(): int
    {
        $meminfo = @file_get_contents('/proc/meminfo');
        if (!is_string($meminfo)) return 0;

        if (preg_match('~^MemTotal:\s+(\d+)\s+kB~mi', $meminfo, $m)) {
            return (int)floor(((int)$m[1]) / 1024);
        }
        return 0;
    }

    private static function defaultTailLines(): int
    {
        $mb = self::detectMemMb();

        return match (true) {
            $mb >= 64000 => 60000,
            $mb >= 32000 => 45000,
            $mb >= 16000 => 35000,
            $mb >=  8000 => 25000,
            $mb >=  4000 => 18000,
            default      => 12000,
        };
    }
}
