<?php
declare(strict_types=1);

spl_autoload_register(static function (string $class): void {
    $prefix = 'AdminPanel\\';
    if (!str_starts_with($class, $prefix)) {
        return;
    }

    $relative = substr($class, strlen($prefix));
    if ($relative === '') {
        return;
    }

    $path = __DIR__ . '/../src/' . str_replace('\\', '/', $relative) . '.php';
    if (is_file($path)) {
        require $path;
    }
});
