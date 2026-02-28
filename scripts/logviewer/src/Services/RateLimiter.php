<?php
declare(strict_types=1);

namespace LogViewer\Services;

final class RateLimiter
{
    public function __construct(private readonly string $dir = '/tmp') {}

    public function allow(string $bucket, string $key, int $max, int $windowSec): bool
    {
        $rk = rtrim($this->dir, '/') . '/logviewer_rl_' . hash('sha256', $bucket . '|' . $key) . '.json';
        $now = time();

        $rl = ['t' => $now, 'n' => 0];
        if (is_file($rk)) {
            $raw = @file_get_contents($rk);
            $j = is_string($raw) ? json_decode($raw, true) : null;
            if (is_array($j) && isset($j['t'], $j['n'])) {
                $t = (int)$j['t'];
                $n = (int)$j['n'];
                if (($now - $t) <= $windowSec) {
                    $rl = ['t' => $t, 'n' => $n];
                }
            }
        }

        $rl['n']++;

        @file_put_contents($rk, json_encode($rl), LOCK_EX);

        return $rl['n'] <= $max;
    }
}
