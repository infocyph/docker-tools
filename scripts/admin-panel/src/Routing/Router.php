<?php
declare(strict_types=1);

namespace AdminPanel\Routing;

final class Router
{
    /** @var array<string,array{view:string,title:string}> */
    private array $routes;

    /** @var array<string,string> */
    private array $aliases;

    /**
     * @param array<string,array{view:string,title:string}> $routes
     * @param array<string,string> $aliases
     */
    public function __construct(array $routes, array $aliases = [])
    {
        $this->routes = $routes;
        $this->aliases = $aliases;
    }

    public static function defaults(): self
    {
        return new self(
            [
                'dashboard' => ['view' => 'dashboard', 'title' => 'Operations Overview | Admin Panel'],
                'logs' => ['view' => 'logs', 'title' => 'Log Streams | Admin Panel'],
                'docker-logs' => ['view' => 'docker_logs', 'title' => 'Docker Logs | Admin Panel'],
                'db-health' => ['view' => 'db_health', 'title' => 'DB / Redis Health | Admin Panel'],
                'queue-health' => ['view' => 'queue_health', 'title' => 'Queue / Cron Health | Admin Panel'],
                'slo-view' => ['view' => 'slo_view', 'title' => 'Error Budget / SLO | Admin Panel'],
                'log-heatmap' => ['view' => 'log_heatmap', 'title' => 'Log Error Heatmap | Admin Panel'],
                'drift-monitor' => ['view' => 'drift_monitor', 'title' => 'Config Drift Monitor | Admin Panel'],
                'alerts' => ['view' => 'alerts', 'title' => 'Alert Rules | Admin Panel'],
                'synthetic-flows' => ['view' => 'synthetic_flows', 'title' => 'Synthetic Flows | Admin Panel'],
                'tls-monitor' => ['view' => 'tls_monitor', 'title' => 'TLS / mTLS Monitor | Admin Panel'],
                'volume-monitor' => ['view' => 'volume_monitor', 'title' => 'Volume Growth / Inode Monitor | Admin Panel'],
                'live-stats' => ['view' => 'live_stats', 'title' => 'Live Stack Telemetry | Admin Panel'],
            ],
            [
                'docker_logs' => 'docker-logs',
                'db_health' => 'db-health',
                'queue_health' => 'queue-health',
                'slo_view' => 'slo-view',
                'log_heatmap' => 'log-heatmap',
                'drift_monitor' => 'drift-monitor',
                'synthetic_flows' => 'synthetic-flows',
                'tls_monitor' => 'tls-monitor',
                'volume_monitor' => 'volume-monitor',
                'live_stats' => 'live-stats',
            ],
        );
    }

    /**
     * @param array<string,mixed> $server
     */
    public function resolve(array $server): ResolvedRoute
    {
        $requestUri = (string)($server['REQUEST_URI'] ?? '/');
        $requestPath = (string)(parse_url($requestUri, PHP_URL_PATH) ?? '/');
        $requestPath = trim($requestPath);
        if ($requestPath === '') {
            $requestPath = '/';
        }

        $scriptName = (string)($server['SCRIPT_NAME'] ?? '/index.php');
        $scriptDir = str_replace('\\', '/', dirname($scriptName));
        if ($scriptDir === '.' || $scriptDir === '/') {
            $scriptDir = '';
        }

        if ($scriptDir !== '' && str_starts_with($requestPath, $scriptDir . '/')) {
            $requestPath = substr($requestPath, strlen($scriptDir));
        }

        $segments = explode('/', trim($requestPath, '/'));
        $firstSegment = strtolower((string)($segments[0] ?? ''));
        $slug = $firstSegment === '' ? 'dashboard' : $firstSegment;
        $slug = $this->aliases[$slug] ?? $slug;

        if (!isset($this->routes[$slug])) {
            $slug = 'dashboard';
        }

        $route = $this->routes[$slug];
        $path = $slug === 'dashboard' ? '/' : '/' . $slug;

        return new ResolvedRoute($slug, $route['view'], $route['title'], $path);
    }
}
