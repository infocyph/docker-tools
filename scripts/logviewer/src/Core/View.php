<?php
declare(strict_types=1);

namespace LogViewer\Core;

final class View
{
    public function __construct(private readonly string $dir) {}

    /** @param array<string,mixed> $data */
    public function render(string $file, array $data = []): string
    {
        $path = $this->dir . '/' . ltrim($file, '/');
        if (!str_ends_with($path, '.php')) $path .= '.php';
        if (!is_file($path)) return 'View not found';

        extract($data, EXTR_SKIP);

        ob_start();
        require $path;
        return (string)ob_get_clean();
    }
}

