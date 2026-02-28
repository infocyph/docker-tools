<?php
declare(strict_types=1);

namespace LogViewer\Core;

final class Errors
{
    public static function register(bool $debug): void
    {
        ini_set('display_errors', '0');
        error_reporting(E_ALL);

        set_error_handler(static function (int $severity, string $message, string $file, int $line): bool {
            if (!(error_reporting() & $severity)) return false;
            throw new \ErrorException($message, 0, $severity, $file, $line);
        });

        set_exception_handler(static function (\Throwable $e) use ($debug): void {
            http_response_code(500);

            $path = parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH) ?: '/';
            $isApi = str_starts_with($path, '/api/');

            error_log('[LogViewer] ' . (string)$e);

            if ($isApi) {
                Headers::common(false);
                header('Content-Type: application/json; charset=utf-8');

                $payload = ['ok' => false, 'error' => 'Internal Server Error'];
                if ($debug) {
                    $payload['message'] = $e->getMessage();
                    $payload['file'] = $e->getFile();
                    $payload['line'] = $e->getLine();
                }

                echo json_encode($payload, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
                exit;
            }

            $payload = ['ok' => false, 'error' => 'Internal Server Error'];
            if ($debug) {
                $payload['message'] = $e->getMessage();
                $payload['file'] = $e->getFile();
                $payload['line'] = $e->getLine();
            }

            $json = json_encode($payload, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);

            Headers::common(false);
            header('Content-Type: text/html; charset=utf-8');

            echo '<!doctype html><html><head><meta charset="utf-8"></head><body>';
            echo '<script>';
            echo "console.error('LogViewer Error:', $json);";
            echo '</script>';
            echo '<h3 style="font-family:ui-monospace,monospace;padding:20px;">Something went wrong. Check browser console.</h3>';
            if ($debug) {
                echo '<pre style="padding:0 20px;white-space:pre-wrap;">' . htmlspecialchars((string)$e, ENT_QUOTES, 'UTF-8') . '</pre>';
            }
            echo '</body></html>';
            exit;
        });
    }
}

