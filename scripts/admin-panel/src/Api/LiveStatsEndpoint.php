<?php
declare(strict_types=1);

namespace AdminPanel\Api;

use AdminPanel\Service\StatusSnapshot;

final class LiveStatsEndpoint
{
    private StatusSnapshot $statusSnapshot;

    public function __construct(?StatusSnapshot $statusSnapshot = null)
    {
        $this->statusSnapshot = $statusSnapshot ?? new StatusSnapshot();
    }

    public function handle(): void
    {
        $payload = $this->statusSnapshot->collect();

        if (!headers_sent()) {
            header('Content-Type: application/json; charset=UTF-8');
            header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');
        }

        echo json_encode($payload, JSON_UNESCAPED_SLASHES);
    }
}
