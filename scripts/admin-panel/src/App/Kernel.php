<?php
declare(strict_types=1);

namespace AdminPanel\App;

use AdminPanel\Api\DockerLogsEndpoint;
use AdminPanel\Api\LogsEntriesEndpoint;
use AdminPanel\Api\LogsFilesEndpoint;
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
    private DockerLogsEndpoint $dockerLogsEndpoint;
    private LogsFilesEndpoint $logsFilesEndpoint;
    private LogsEntriesEndpoint $logsEntriesEndpoint;

    public function __construct(
        string $appDir,
        ?Router $router = null,
        ?AjaxResponder $ajaxResponder = null,
        ?LiveStatsEndpoint $liveStatsEndpoint = null,
        ?DockerLogsEndpoint $dockerLogsEndpoint = null,
        ?LogsFilesEndpoint $logsFilesEndpoint = null,
        ?LogsEntriesEndpoint $logsEntriesEndpoint = null
    )
    {
        $this->pagesDir = $appDir . '/pages';
        $this->layoutTop = $this->pagesDir . '/_layout_top.php';
        $this->layoutBottom = $this->pagesDir . '/_layout_bottom.php';
        $this->router = $router ?? Router::defaults();
        $this->ajaxResponder = $ajaxResponder ?? new AjaxResponder();
        $this->liveStatsEndpoint = $liveStatsEndpoint ?? new LiveStatsEndpoint();
        $this->dockerLogsEndpoint = $dockerLogsEndpoint ?? new DockerLogsEndpoint();
        $this->logsFilesEndpoint = $logsFilesEndpoint ?? new LogsFilesEndpoint();
        $this->logsEntriesEndpoint = $logsEntriesEndpoint ?? new LogsEntriesEndpoint();
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
        if ($path === '/api/docker-logs') {
            $this->dockerLogsEndpoint->handle($query);
            return;
        }
        if ($path === '/api/logs/files') {
            $this->logsFilesEndpoint->handle($query);
            return;
        }
        if ($path === '/api/logs/entries') {
            $this->logsEntriesEndpoint->handle($query);
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
