<?php
declare(strict_types=1);

namespace LogViewer\Services;

use FilesystemIterator;
use LogViewer\Support\Fs;

final class LogScanner
{
    /** @param list<string> $roots */
    public function __construct(
        private readonly array $roots,
        private readonly TailReader $tail,
    ) {}

    /** @return list<string> */
    public function roots(): array { return $this->roots; }


    public function displayPath(string $absPath): string
    {
        $absPath = str_replace('\\', '/', $absPath);
        foreach ($this->roots as $root) {
            $rr = realpath($root);
            if ($rr === false) continue;
            $rr = str_replace('\\', '/', $rr);
            $rr = rtrim($rr, '/') . '/';
            if (str_starts_with($absPath, $rr)) {
                $rel = '/' . ltrim(substr($absPath, strlen($rr)), '/');
                return $rel === '/' ? '/' : $rel;
            }
        }
        return $absPath;
    }


    public function resolve(string $input): string
    {
        $input = trim($input);
        if ($input === '') throw new \RuntimeException('missing file');

        $candidate = $input;
        if (!str_starts_with($candidate, '/')) {
            $base = $this->roots[0] ?? '/global/log';
            $candidate = rtrim($base, '/') . '/' . ltrim($candidate, '/');
        }

        $real = realpath($candidate);
        if ($real === false || !is_file($real)) throw new \RuntimeException('file not found');
        if (!$this->isUnderRoots($real)) throw new \RuntimeException('not allowed');

        return $real;
    }

    private function isUnderRoots(string $real): bool
    {
        foreach ($this->roots as $r) {
            $rr = realpath($r);
            if ($rr === false) continue;
            $rr = rtrim($rr, DIRECTORY_SEPARATOR) . DIRECTORY_SEPARATOR;
            if (str_starts_with($real, $rr)) return true;
        }
        return false;
    }

    private function looksLikeTemplateToken(string $s): bool
    {
        if ($s === '') return true;
        if (str_contains($s, '{{') || str_contains($s, '}}')) return true;
        if (str_contains($s, '$')) return true;
        return false;
    }

    private function isLogLike(string $name): bool
    {
        if ($this->looksLikeTemplateToken($name)) return false;

        $n = preg_replace('~\\.gz$~i', '', $name) ?? $name;

        // common extensions
        if (preg_match('~\\.(log|out|err|txt)$~i', $n)) return true;

        // rotated logs like: error.log-20260228, gc.log.07
        $low = strtolower($n);
        if (str_contains($low, 'access') || str_contains($low, 'error')) return true;
        if (preg_match('~\\.log[-\\.]\\d+($|\\.)~i', $n)) return true;

        return false;
    }

    /**
     * Services list for UI (includes empty dirs).
     *
     * @return array<string,string> map: absolute_dir => service_name
     */
    public function listServices(): array
    {
        $services = [];
        foreach ($this->roots as $root) {
            $rr = realpath($root);
            if ($rr === false || !is_dir($rr)) continue;
            $rr = rtrim($rr, DIRECTORY_SEPARATOR);

            $rootBase = basename($rr) ?: 'logs';
            $rootBaseLower = strtolower($rootBase);
            $rootServiceFallback = in_array($rootBaseLower, ['log', 'logs', 'global'], true) ? 'logs' : $rootBase;

            $services[$rr] = $rootServiceFallback;
            foreach ($this->listServicesForRoot($rr) as $dir => $svc) {
                $services[$dir] = $svc;
            }
        }
        return $services;
    }

    /** @return array<string,string> */
    private function listServicesForRoot(string $rr): array
    {
        $dirs = [];
        try {
            $it = new FilesystemIterator($rr, FilesystemIterator::SKIP_DOTS);
            foreach ($it as $f) {
                if (!$f->isDir()) continue;
                $name = $f->getFilename();
                if ($this->looksLikeTemplateToken($name)) continue;
                $dirs[$f->getPathname()] = $name;
            }
        } catch (\Throwable) {
            // ignore
        }

        asort($dirs, SORT_NATURAL | SORT_FLAG_CASE);
        return $dirs;
    }

    /** @return list<array{service:string,name:string,path:string,size:int,mtime:int,gz:bool}> */
    public function listFiles(): array
    {
        // Use `find` for file discovery: it behaves consistently across bind mounts.
        // Our layout is shallow, so depth limits keep it fast.
        $out = [];

        foreach ($this->roots as $root) {
            $rr = realpath($root);
            if ($rr === false || !is_dir($rr)) continue;
            $rr = rtrim($rr, DIRECTORY_SEPARATOR);

            $rootBase = basename($rr) ?: 'logs';
            $rootBaseLower = strtolower($rootBase);
            $rootServiceFallback = in_array($rootBaseLower, ['log', 'logs', 'global'], true) ? 'logs' : $rootBase;

            // files directly under root (rare)
            foreach (Fs::findFiles($rr, 1, 1) as $path) {
                $name = basename($path);
                if (!$this->isLogLike($name)) continue;
                $st = @stat($path) ?: [];
                $out[] = [
                    'service' => $rootServiceFallback,
                    'name'    => $name,
                    'path'    => $path,
                    'size'    => (int)($st['size'] ?? 0),
                    'mtime'   => (int)($st['mtime'] ?? 0),
                    'gz'      => $this->tail->isGz($path),
                ];
            }

            foreach ($this->listServicesForRoot($rr) as $serviceDir => $serviceName) {
                foreach (Fs::findFiles($serviceDir, 1, 3) as $path) {
                    $name = basename($path);
                    if (!$this->isLogLike($name)) continue;
                    $st = @stat($path) ?: [];
                    $out[] = [
                        'service' => $serviceName,
                        'name'    => $name,
                        'path'    => $path,
                        'size'    => (int)($st['size'] ?? 0),
                        'mtime'   => (int)($st['mtime'] ?? 0),
                        'gz'      => $this->tail->isGz($path),
                    ];
                }
            }
        }

        usort($out, static fn($a, $b) => ($b['mtime'] <=> $a['mtime']) ?: ($b['size'] <=> $a['size']));
        return $out;
    }
}
