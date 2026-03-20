<?php
declare(strict_types=1);

namespace AdminPanel\Http;

use AdminPanel\Routing\ResolvedRoute;

final class AjaxResponder
{
    public function send(RequestContext $request, ResolvedRoute $route, string $content): bool
    {
        if (!$request->isAjax) {
            return false;
        }

        if ($request->wantsJson) {
            $payload = [
                'ok' => true,
                'page' => $route->slug,
                'title' => $route->title,
                'route' => $route->path,
                'content' => $content,
            ];

            if (!headers_sent()) {
                header('Content-Type: application/json; charset=UTF-8');
            }

            $json = json_encode($payload, JSON_UNESCAPED_SLASHES);
            if ($json === false) {
                $json = '{"ok":false,"error":"failed_to_encode_json"}';
            }
            echo $json;
            return true;
        }

        if (!headers_sent()) {
            header('Content-Type: text/html; charset=UTF-8');
        }
        echo $content;
        return true;
    }
}
