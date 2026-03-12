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
                'live-stats' => ['view' => 'live_stats', 'title' => 'Live Stack Telemetry | Admin Panel'],
            ],
            [
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
