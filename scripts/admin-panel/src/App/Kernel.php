<?php
declare(strict_types=1);

namespace AdminPanel\App;

use AdminPanel\Api\DockerLogsEndpoint;
use AdminPanel\Api\DbHealthEndpoint;
use AdminPanel\Api\DriftMonitorEndpoint;
use AdminPanel\Api\HostManagerEndpoint;
use AdminPanel\Api\LogHeatmapEndpoint;
use AdminPanel\Api\LogsEntriesEndpoint;
use AdminPanel\Api\LogsFilesEndpoint;
use AdminPanel\Api\LiveStatsEndpoint;
use AdminPanel\Api\QueueHealthEndpoint;
use AdminPanel\Api\RuntimeEventsEndpoint;
use AdminPanel\Api\TlsCertArtifactEndpoint;
use AdminPanel\Api\TlsMonitorEndpoint;
use AdminPanel\Api\VolumeMonitorEndpoint;
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
    private DbHealthEndpoint $dbHealthEndpoint;
    private QueueHealthEndpoint $queueHealthEndpoint;
    private LogHeatmapEndpoint $logHeatmapEndpoint;
    private DriftMonitorEndpoint $driftMonitorEndpoint;
    private HostManagerEndpoint $hostManagerEndpoint;
    private RuntimeEventsEndpoint $runtimeEventsEndpoint;
    private TlsCertArtifactEndpoint $tlsCertArtifactEndpoint;
    private TlsMonitorEndpoint $tlsMonitorEndpoint;
    private VolumeMonitorEndpoint $volumeMonitorEndpoint;
    private LogsFilesEndpoint $logsFilesEndpoint;
    private LogsEntriesEndpoint $logsEntriesEndpoint;

    public function __construct(
        string $appDir,
        ?Router $router = null,
        ?AjaxResponder $ajaxResponder = null,
        ?LiveStatsEndpoint $liveStatsEndpoint = null,
        ?DockerLogsEndpoint $dockerLogsEndpoint = null,
        ?DbHealthEndpoint $dbHealthEndpoint = null,
        ?QueueHealthEndpoint $queueHealthEndpoint = null,
        ?LogHeatmapEndpoint $logHeatmapEndpoint = null,
        ?DriftMonitorEndpoint $driftMonitorEndpoint = null,
        ?HostManagerEndpoint $hostManagerEndpoint = null,
        ?RuntimeEventsEndpoint $runtimeEventsEndpoint = null,
        ?TlsCertArtifactEndpoint $tlsCertArtifactEndpoint = null,
        ?TlsMonitorEndpoint $tlsMonitorEndpoint = null,
        ?VolumeMonitorEndpoint $volumeMonitorEndpoint = null,
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
        $this->dbHealthEndpoint = $dbHealthEndpoint ?? new DbHealthEndpoint();
        $this->queueHealthEndpoint = $queueHealthEndpoint ?? new QueueHealthEndpoint();
        $this->logHeatmapEndpoint = $logHeatmapEndpoint ?? new LogHeatmapEndpoint();
        $this->driftMonitorEndpoint = $driftMonitorEndpoint ?? new DriftMonitorEndpoint();
        $this->hostManagerEndpoint = $hostManagerEndpoint ?? new HostManagerEndpoint();
        $this->runtimeEventsEndpoint = $runtimeEventsEndpoint ?? new RuntimeEventsEndpoint();
        $this->tlsCertArtifactEndpoint = $tlsCertArtifactEndpoint ?? new TlsCertArtifactEndpoint();
        $this->tlsMonitorEndpoint = $tlsMonitorEndpoint ?? new TlsMonitorEndpoint();
        $this->volumeMonitorEndpoint = $volumeMonitorEndpoint ?? new VolumeMonitorEndpoint();
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
        if ($path === '/api/db-health') {
            $this->dbHealthEndpoint->handle($query);
            return;
        }
        if ($path === '/api/queue-health') {
            $this->queueHealthEndpoint->handle($query);
            return;
        }
        if ($path === '/api/log-heatmap') {
            $this->logHeatmapEndpoint->handle($query);
            return;
        }
        if ($path === '/api/drift-monitor') {
            $this->driftMonitorEndpoint->handle($query);
            return;
        }
        if ($path === '/api/hosts') {
            $this->hostManagerEndpoint->handle($query, $server);
            return;
        }
        if ($path === '/api/runtime-events') {
            $this->runtimeEventsEndpoint->handle($query);
            return;
        }
        if ($path === '/api/tls-cert-artifact') {
            $this->tlsCertArtifactEndpoint->handle($query);
            return;
        }
        if ($path === '/api/tls-monitor') {
            $this->tlsMonitorEndpoint->handle($query);
            return;
        }
        if ($path === '/api/volume-monitor') {
            $this->volumeMonitorEndpoint->handle($query);
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
        $request = RequestContext::fromGlobals($server, $query);

        $pageFile = $this->pagesDir . '/' . $route->view . '.php';
        if (!is_file($pageFile)) {
            http_response_code(500);
            echo 'Page template not found.';
            return;
        }

        if ($request->isAjax) {
            ob_start();
            require $pageFile;
            $pageContent = (string)ob_get_clean();
            if ($this->ajaxResponder->send($request, $route, $pageContent)) {
                return;
            }
        }

        require $this->layoutTop;
        if (function_exists('ob_get_level') && ob_get_level() > 0 && function_exists('ob_flush')) {
            @ob_flush();
        }
        if (function_exists('flush')) {
            @flush();
        }
        require $pageFile;
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
