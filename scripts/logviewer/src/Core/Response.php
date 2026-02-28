<?php
declare(strict_types=1);

namespace LogViewer\Core;

class Response
{
    /** @var array<string,string> */
    protected array $headers = [];

    public function __construct(
        protected int $status = 200,
        protected string $body = '',
        protected string $contentType = 'text/html; charset=utf-8',
    ) {}

    public function header(string $k, string $v): self
    {
        $this->headers[$k] = $v;
        return $this;
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
