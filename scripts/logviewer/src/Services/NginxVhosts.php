<?php
declare(strict_types=1);

namespace LogViewer\Services;

use FilesystemIterator;
use RecursiveDirectoryIterator;
use RecursiveIteratorIterator;

final class NginxVhosts
{
    public function __construct(private readonly string $dir) {}

    /** @return list<string> */
    public function domains(): array
    {
        $d = realpath($this->dir);
        if ($d === false || !is_dir($d)) return [];

        $out = [];

        $it = new RecursiveIteratorIterator(
            new RecursiveDirectoryIterator($d, FilesystemIterator::SKIP_DOTS),
            RecursiveIteratorIterator::SELF_FIRST
        );

        foreach ($it as $f) {
            if (!$f->isFile()) continue;

            $name = $f->getFilename();
            if (!preg_match('~\.conf$~i', $name)) continue;

            $dom = preg_replace('~\.conf$~i', '', $name) ?? '';
            $dom = trim($dom);
            if ($dom !== '') $out[$dom] = true;
        }

        $domains = array_keys($out);
        sort($domains, SORT_NATURAL | SORT_FLAG_CASE);
        return $domains;
    }
}
