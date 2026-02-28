<?php
declare(strict_types=1);

namespace LogViewer\Support;

final class Fs
{
    /**
     * Find files using system `find` for reliability across bind mounts.
     *
     * @return list<string> absolute file paths
     */
    public static function findFiles(string $dir, int $minDepth, int $maxDepth): array
    {
        $dir = rtrim($dir, DIRECTORY_SEPARATOR);
        if ($dir === '' || !is_dir($dir)) return [];

        $minDepth = max(0, $minDepth);
        $maxDepth = max($minDepth, $maxDepth);

        $cmd = [
            'find',
            $dir,
            '-mindepth', (string)$minDepth,
            '-maxdepth', (string)$maxDepth,
            '-type', 'f',
            '-print0',
        ];

        $descriptors = [
            1 => ['pipe', 'w'],
            2 => ['pipe', 'w'],
        ];

        $proc = @proc_open($cmd, $descriptors, $pipes);
        if (!\is_resource($proc)) return [];

        $out = stream_get_contents($pipes[1]) ?: '';
        fclose($pipes[1]);

        // swallow stderr
        $stderr = stream_get_contents($pipes[2]) ?: '';
        fclose($pipes[2]);
        unset($stderr);

        @proc_close($proc);

        if ($out === '') return [];

        $parts = explode("\0", $out);
        $res = [];
        foreach ($parts as $p) {
            if ($p === '' || !is_file($p)) continue;
            $res[] = $p;
        }
        return $res;
    }
}

