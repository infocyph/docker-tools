<?php
declare(strict_types=1);

namespace AdminPanel\Http;

final class RequestContext
{
    public function __construct(
        public readonly bool $isAjax,
        public readonly bool $wantsJson,
    ) {
    }

    /**
     * @param array<string,mixed> $server
     * @param array<string,mixed> $query
     */
    public static function fromGlobals(array $server, array $query): self
    {
        $xRequestedWith = strtolower((string)($server['HTTP_X_REQUESTED_WITH'] ?? ''));
        $isAjax = $xRequestedWith === 'xmlhttprequest' || (isset($query['ajax']) && (string)$query['ajax'] !== '0');

        $accept = strtolower((string)($server['HTTP_ACCEPT'] ?? ''));
        $wantsJson = str_contains($accept, 'application/json')
            || (isset($query['format']) && strtolower((string)$query['format']) === 'json');

        return new self($isAjax, $wantsJson);
    }
}
