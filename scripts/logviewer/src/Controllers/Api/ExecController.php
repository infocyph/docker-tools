<?php
declare(strict_types=1);

namespace LogViewer\Controllers\Api;

use LogViewer\Core\Config;
use LogViewer\Core\JsonResponse;
use LogViewer\Core\Request;
use LogViewer\Core\Response;
use LogViewer\Services\ShellRunner;

final class ExecController
{
    public function __construct(
        private readonly Config $cfg,
        private readonly ShellRunner $sh,
    ) {}

    public function handle(Request $r): Response
    {
        if (!$this->cfg->allowExec) {
            return new JsonResponse(['ok' => false, 'error' => 'exec disabled (set LOGVIEW_ALLOW_EXEC=1)'], 403);
        }

        $action = strtolower(trim($r->get('action')));
        $service = strtolower(trim($r->get('service')));
        $tail = $r->int('tail', 200, 50, 2000);

        if ($action === '' || $service === '') {
            return new JsonResponse(['ok' => false, 'error' => 'missing action/service'], 400);
        }

        $container = $this->containerFor($service);
        if ($container === '') {
            return new JsonResponse(['ok' => false, 'error' => 'unknown service container'], 400);
        }

        $cmd = null;

        // Whitelisted actions only
        if ($action === 'logs') {
            $cmd = ['docker', 'logs', '--tail', (string)$tail, $container];
        } elseif ($action === 'reload') {
            // only allow reload for nginx/apache/php-fpm
            $cmd = match ($service) {
                'nginx' => ['docker', 'exec', $container, 'sh', '-lc', 'nginx -s reload'],
                'apache' => ['docker', 'exec', $container, 'sh', '-lc', 'apachectl -k graceful 2>/dev/null || httpd -k graceful 2>/dev/null || true'],
                'php-fpm', 'phpfpm' => ['docker', 'exec', $container, 'sh', '-lc', 'kill -USR2 1 2>/dev/null || kill -HUP 1 2>/dev/null || true'],
                default => null,
            };
        } elseif ($action === 'config') {
            $cmd = match ($service) {
                'nginx' => ['docker', 'exec', $container, 'sh', '-lc', 'nginx -T 2>/dev/null | sed -n "1,220p"'],
                default => null,
            };
        }

        if (!$cmd) return new JsonResponse(['ok' => false, 'error' => 'unsupported action'], 400);

        [$code, $out, $err] = $this->sh->run($cmd, 12);

        return new JsonResponse([
            'ok' => $code === 0,
            'action' => $action,
            'service' => $service,
            'container' => $container,
            'code' => $code,
            'out' => $out,
            'err' => $err,
        ]);
    }

    private function containerFor(string $service): string
    {
        $service = strtolower($service);
        if (isset($this->cfg->containerMap[$service])) return $this->cfg->containerMap[$service];

        // default: upper-cased service name
        return strtoupper($service);
    }
}
