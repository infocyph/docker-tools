<?php

declare(strict_types=1);

require_once __DIR__ . '/bootstrap.php';

/**
 * Global Exception Handler
 */
set_exception_handler(function (Throwable $e): void {

    http_response_code(500);

    $isApi = str_starts_with(
      parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH) ?: '/',
      '/api/'
    );

    $payload = [
      'ok'      => false,
      'error'   => 'Internal Server Error',
      'message' => $e->getMessage(),
      'file'    => $e->getFile(),
      'line'    => $e->getLine(),
    ];

    // Log to PHP error log (server side)
    error_log('[LogViewer] ' . $e);

    if ($isApi) {
        header('Content-Type: application/json; charset=utf-8');
        echo json_encode($payload, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
        exit;
    }

    // For UI pages → send error to browser console safely
    $json = json_encode($payload, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);

    echo '<!doctype html><html><head><meta charset="utf-8"></head><body>';
    echo '<script>';
    echo "console.error('LogViewer Error:', $json);";
    echo '</script>';
    echo '<h3 style="font-family:monospace;padding:20px;">Something went wrong. Check browser console.</h3>';
    echo '</body></html>';
    exit;
});

/**
 * Convert PHP warnings/notices into Exceptions
 */
set_error_handler(function (
  int $severity,
  string $message,
  string $file,
  int $line
): bool {
    if (!(error_reporting() & $severity)) {
        return false;
    }
    throw new ErrorException($message, 0, $severity, $file, $line);
});

/**
 * Router
 */
try {

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

} catch (Throwable $e) {
    // Re-throw to global handler
    throw $e;
}