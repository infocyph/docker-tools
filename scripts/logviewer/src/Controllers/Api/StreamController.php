<?php
declare(strict_types=1);

namespace LogViewer\Controllers\Api;

use LogViewer\Core\JsonResponse;
use LogViewer\Core\Request;
use LogViewer\Core\Response;
use LogViewer\Services\StreamService;

final class StreamController
{
    public function __construct(private readonly StreamService $stream) {}

    public function handle(Request $r): Response
    {
        $service = trim($r->get('service'));
        $limit = $r->int('limit', 200, 50, 2000);
        $sinceMin = $r->int('since_minutes', 0, 0, 60*24*30);

        $payload = $this->stream->stream($service, $limit, $sinceMin);

        return new JsonResponse([
            'ok' => true,
            'meta' => $payload['meta'],
            'items' => $payload['items'],
        ]);
    }
}
