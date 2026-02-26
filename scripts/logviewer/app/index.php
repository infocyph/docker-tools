<?php

declare(strict_types=1);

require_once __DIR__ . '/bootstrap.php';

$path = parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH) ?: '/';

if (str_starts_with($path, '/assets/')) {
    serve_asset(substr($path, strlen('/assets/')));
}

if (str_starts_with($path, '/api/')) {
    $name = trim(substr($path, strlen('/api/')), '/');
    if ($name === '') {
        json_out(['ok' => false, 'error' => 'not found'], 404);
    }

    $api = __DIR__ . '/api/' . $name . '.php';
    if (!is_file($api)) {
        json_out(['ok' => false, 'error' => 'not found'], 404);
    }
    require_once $api;
    exit;
}

$page = (string)($_GET['p'] ?? 'dashboard');
if ($page !== 'dashboard' && $page !== 'logs') {
    $page = 'dashboard';
}

require_once __DIR__ . '/pages/' . $page . '.php';