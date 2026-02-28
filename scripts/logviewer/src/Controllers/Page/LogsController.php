<?php
declare(strict_types=1);

namespace LogViewer\Controllers\Page;

use LogViewer\Core\Request;
use LogViewer\Core\Response;
use LogViewer\Core\View;

final class LogsController
{
    public function __construct(private readonly View $view) {}

    public function handle(Request $r): Response
    {
        $html = $this->view->render('logs.php', []);
        return new Response(200, $html, 'text/html; charset=utf-8');
    }
}
