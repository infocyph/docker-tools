<?php
declare(strict_types=1);

namespace AdminPanel\Api;

final class TlsCertArtifactEndpoint
{
    /**
     * @param array<string,mixed> $query
     */
    public function handle(array $query = []): void
    {
        $kind = strtolower(trim((string)($query['kind'] ?? '')));
        if ($kind === 'rootca') {
            $path = $this->firstReadableFile(
                [
                    (string)getenv('TLS_MONITOR_ROOTCA_FILE'),
                    '/etc/share/rootCA/rootCA.pem',
                    '/etc/share/certs/rootCA.pem',
                ]
            );
            if ($path === null) {
                $this->sendJson(
                    404,
                    [
                        'ok' => false,
                        'error' => 'rootca_not_found',
                        'message' => 'Root CA file not found.',
                    ]
                );
                return;
            }
            $this->streamFile($path, 'application/x-x509-ca-cert', 'rootCA.pem');
            return;
        }

        if ($kind === 'mtls') {
            $path = $this->firstReadableFile(
                [
                    (string)getenv('TLS_MONITOR_MTLS_USER_P12_FILE'),
                    '/etc/share/certs/mTLS-user.p12',
                    '/etc/share/certs/lds-client-user.p12',
                    '/etc/mkcert/lds-client-user.p12',
                ]
            );
            if ($path === null) {
                $this->sendJson(
                    404,
                    [
                        'ok' => false,
                        'error' => 'mtls_bundle_not_found',
                        'message' => 'mTLS client bundle (.p12) not found.',
                    ]
                );
                return;
            }
            $this->streamFile($path, 'application/x-pkcs12', 'mTLS-user.p12');
            return;
        }

        $this->sendJson(
            400,
            [
                'ok' => false,
                'error' => 'invalid_kind',
                'message' => 'Use kind=rootca or kind=mtls.',
            ]
        );
    }

    /**
     * @param list<string> $candidates
     */
    private function firstReadableFile(array $candidates): ?string
    {
        foreach ($candidates as $candidate) {
            $path = trim($candidate);
            if ($path === '') {
                continue;
            }
            if (is_file($path) && is_readable($path)) {
                return $path;
            }
        }
        return null;
    }

    private function streamFile(string $path, string $contentType, string $downloadName): void
    {
        if (!headers_sent()) {
            http_response_code(200);
            header('Content-Type: ' . $contentType);
            header('Content-Length: ' . (string)filesize($path));
            header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');
            header('X-Content-Type-Options: nosniff');
            header('Content-Disposition: attachment; filename="' . $downloadName . '"');
        }
        if (function_exists('ob_get_level')) {
            while (ob_get_level() > 0) {
                @ob_end_clean();
            }
        }
        readfile($path);
    }

    /**
     * @param array<string,mixed> $payload
     */
    private function sendJson(int $status, array $payload): void
    {
        if (!headers_sent()) {
            http_response_code($status);
            header('Content-Type: application/json; charset=UTF-8');
            header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');
        }
        echo json_encode($payload, JSON_UNESCAPED_SLASHES);
    }
}
