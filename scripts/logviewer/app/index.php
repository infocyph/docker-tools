<?php

declare(strict_types=1);

require_once __DIR__ . '/bootstrap.php';

/**
 * Global Exception Handler
 */
set_exception_handler(function (Throwable $e) use ($LOGVIEW_DEBUG): void {
    http_response_code(500);

    $path = parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH) ?: '/';
    $isApi = str_starts_with($path, '/api/');

    // Always log server-side
    error_log('[LogViewer] ' . (string)$e);

    if ($isApi) {
        lv_common_headers(false);
        header('Content-Type: application/json; charset=utf-8');

        $payload = [
          'ok' => false,
          'error' => 'Internal Server Error',
        ];

        if ($LOGVIEW_DEBUG) {
            $payload['message'] = $e->getMessage();
            $payload['file'] = $e->getFile();
            $payload['line'] = $e->getLine();
        }

        echo json_encode(
          $payload,
          JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE,
        );
        exit;
    }

    // UI page: keep it clean; show details only if debug.
    $payload = [
      'ok' => false,
      'error' => 'Internal Server Error',
    ];

    if ($LOGVIEW_DEBUG) {
        $payload['message'] = $e->getMessage();
        $payload['file'] = $e->getFile();
        $payload['line'] = $e->getLine();
    }

    $json = json_encode(
      $payload,
      JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE,
    );

    lv_common_headers(false);
    header('Content-Type: text/html; charset=utf-8');

    echo '<!doctype html><html><head><meta charset="utf-8"></head><body>';
    echo '<script>';
    echo "console.error('LogViewer Error:', $json);";
    echo '</script>';
    echo '<h3 style="font-family:ui-monospace,monospace;padding:20px;">Something went wrong. Check browser console.</h3>';
    if ($LOGVIEW_DEBUG) {
        echo '<pre style="padding:0 20px;white-space:pre-wrap;">' . htmlspecialchars(
            (string)$e,
            ENT_QUOTES,
            'UTF-8',
          ) . '</pre>';
    }
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
  int $line,
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
        // serve_asset has realpath containment checks
        serve_asset(substr($path, strlen('/assets/')));
    }

    if (str_starts_with($path, '/api/')) {
        $name = trim(substr($path, strlen('/api/')), '/');

        if ($name === '') {
            json_out(['ok' => false, 'error' => 'not found'], 404);
        }

        // Hard block traversal / weird names
        // (we only ship flat api files: entries, files, grep, tail, raw, etc.)
        if (!preg_match('~^[a-zA-Z0-9_-]+$~', $name)) {
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
