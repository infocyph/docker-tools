<?php
declare(strict_types=1);

namespace LogViewer\Controllers\Page;

use LogViewer\Core\Request;
use LogViewer\Core\Response;
use LogViewer\Core\View;
use LogViewer\Services\NginxVhosts;
use LogViewer\Services\StatsService;

final class DashboardController
{
    public function __construct(
        private readonly View $view,
        private readonly NginxVhosts $nginx,
        private readonly StatsService $stats,
        private readonly int $cacheTtl,
    ) {}

    public function handle(Request $r): Response
    {
        $domains = $this->nginx->domains();
        $logCounts = $this->stats->fileCountsByService();

        $data = [
            'activePage' => 'dashboard',
            'pageTitle' => 'Dashboard',
            'domains' => $domains,
            'domainCount' => count($domains),
            'logCounts' => $logCounts,
            'logFileTotal' => (int)($logCounts['total'] ?? 0),
            'serviceCount' => count((array)($logCounts['by_dir'] ?? [])),
            'systemDomains' => [
                'WebMail' => 'webmail.localhost',
                'DB Client (RDBMS)' => 'db.localhost',
                'Redis Insight' => 'ri.localhost',
                'Mongo Express' => 'me.localhost',
                'Kibana' => 'kibana.localhost',
            ],
        ];

        $html = $this->view->render('dashboard.php', $data);
        return new Response(200, $html, 'text/html; charset=utf-8');
    }
}

