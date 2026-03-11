<?php
declare(strict_types=1);

namespace AdminPanel\App;

use AdminPanel\Api\LiveStatsEndpoint;
use AdminPanel\Http\AjaxResponder;
use AdminPanel\Http\RequestContext;
use AdminPanel\Routing\Router;

final class Kernel
{
    private string $pagesDir;
    private string $layoutTop;
    private string $layoutBottom;
    private Router $router;
    private AjaxResponder $ajaxResponder;
    private LiveStatsEndpoint $liveStatsEndpoint;

    public function __construct(
        string $appDir,
        ?Router $router = null,
        ?AjaxResponder $ajaxResponder = null,
        ?LiveStatsEndpoint $liveStatsEndpoint = null
    )
    {
        $this->pagesDir = $appDir . '/pages';
        $this->layoutTop = $this->pagesDir . '/_layout_top.php';
        $this->layoutBottom = $this->pagesDir . '/_layout_bottom.php';
        $this->router = $router ?? Router::defaults();
        $this->ajaxResponder = $ajaxResponder ?? new AjaxResponder();
        $this->liveStatsEndpoint = $liveStatsEndpoint ?? new LiveStatsEndpoint();
    }

    /**
     * @param array<string,mixed> $server
     * @param array<string,mixed> $query
     */
    public function handle(array $server, array $query): void
    {
        $path = $this->normalizePath($server);
        if ($path === '/api/live-stats') {
            $this->liveStatsEndpoint->handle();
            return;
        }

        $route = $this->router->resolve($server);
        $activePage = $route->slug;
        $pageTitle = $route->title;

        $pageFile = $this->pagesDir . '/' . $route->view . '.php';
        if (!is_file($pageFile)) {
            http_response_code(500);
            echo 'Page template not found.';
            return;
        }

        ob_start();
        require $pageFile;
        $pageContent = (string)ob_get_clean();

        $request = RequestContext::fromGlobals($server, $query);
        if ($this->ajaxResponder->send($request, $route, $pageContent)) {
            return;
        }

        require $this->layoutTop;
        echo $pageContent;
        require $this->layoutBottom;
    }

    /**
     * @param array<string,mixed> $server
     */
    private function normalizePath(array $server): string
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

        return '/' . ltrim($requestPath, '/');
    }
}
