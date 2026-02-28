<?php
declare(strict_types=1);

namespace LogViewer\Core;

final class JsonResponse extends Response
{
    /** @param array<string,mixed> $data */
    public function __construct(array $data, int $status = 200)
    {
        $json = json_encode($data, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
        parent::__construct($status, $json !== false ? $json : '{"ok":false,"error":"json_encode failed"}', 'application/json; charset=utf-8');
    }

    public function send(): never
    {
        http_response_code($this->status);
        Headers::common(false);
        header('Content-Type: ' . $this->contentType);
        foreach ($this->headers as $k => $v) {
            header($k . ': ' . $v);
        }
        echo $this->body;
        exit;
    }
}
