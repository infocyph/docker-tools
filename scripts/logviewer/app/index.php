<?php

declare(strict_types=1);

require_once __DIR__ . '/bootstrap.php';

set_exception_handler(function (Throwable $e): void {
    http_response_code(500);

    $path = parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH) ?: '/';
    $isApi = str_starts_with($path, '/api/');

    error_log('[LogViewer] ' . $e);

    $payload = [
      'ok' => false,
      'error' => 'Internal Server Error',
      'message' => $e->getMessage(),
    ];

    if (!empty($GLOBALS['LOGVIEW_DEBUG'])) {
        $payload['file'] = $e->getFile();
        $payload['line'] = $e->getLine();
    }

    if ($isApi) {
        lv_security_headers(true);
        echo json_encode(
          $payload,
          JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE,
        );
        exit;
    }

    $json = json_encode(
      $payload,
      JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE,
    );

    echo '<!doctype html><html><head><meta charset="utf-8"></head><body>';
    echo '<script>';
    echo "console.error('LogViewer Error:', $json);";
    echo '</script>';
    echo '<h3 style="font-family:monospace;padding:20px;">Something went wrong. Check browser console.</h3>';
    echo '</body></html>';
    exit;
});

set_error_handler(
  function (int $severity, string $message, string $file, int $line): bool {
      if (!(error_reporting() & $severity)) {
          return false;
      }
      throw new ErrorException($message, 0, $severity, $file, $line);
  },
);

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
