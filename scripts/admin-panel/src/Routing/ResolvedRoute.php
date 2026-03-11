<?php
declare(strict_types=1);

namespace AdminPanel\Routing;

final class ResolvedRoute
{
    public function __construct(
        public readonly string $slug,
        public readonly string $view,
        public readonly string $title,
        public readonly string $path,
    ) {
    }
}
