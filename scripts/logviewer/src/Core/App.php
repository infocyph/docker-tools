<?php
declare(strict_types=1);

namespace LogViewer\Core;

use LogViewer\Controllers\Api\EntriesController;
use LogViewer\Controllers\Api\FilesController;
use LogViewer\Controllers\Api\GrepController;
use LogViewer\Controllers\Api\HealthController;
use LogViewer\Controllers\Api\DownloadController;
use LogViewer\Controllers\Api\ExecController;
use LogViewer\Controllers\Api\ExportController;
use LogViewer\Controllers\Api\StreamController;
use LogViewer\Controllers\Api\RawController;
use LogViewer\Controllers\Api\TailController;
use LogViewer\Controllers\Page\DashboardController;
use LogViewer\Controllers\Page\LogsController;
use LogViewer\Services\Cache;
use LogViewer\Services\EntriesService;
use LogViewer\Services\GrepRunner;
use LogViewer\Services\LogParser;
use LogViewer\Services\LogScanner;
use LogViewer\Services\NginxVhosts;
use LogViewer\Services\RateLimiter;
use LogViewer\Services\ShellRunner;
use LogViewer\Services\StatsService;
use LogViewer\Services\StreamService;
use LogViewer\Services\TailReader;

final class App
{
    private readonly Config $cfg;
    private readonly AssetServer $assets;
    private readonly View $view;

    private readonly TailReader $tail;
    private readonly ShellRunner $sh;
    private readonly Cache $cache;
    private readonly LogParser $parser;
    private readonly LogScanner $scanner;

    private readonly EntriesService $entriesSvc;
    private readonly RateLimiter $rl;
    private readonly GrepRunner $grep;
    private readonly NginxVhosts $nginx;
    private readonly StatsService $stats;
    private readonly StreamService $stream;

    public function __construct(private readonly string $baseDir)
    {
        $this->cfg = new Config();
        Errors::register($this->cfg->debug);

        $this->assets = new AssetServer($this->baseDir . '/public');
        $this->view = new View($this->baseDir . '/app/pages');

        $this->tail = new TailReader();
        $this->sh = new ShellRunner();
        $this->cache = new Cache('/tmp', $this->cfg->cacheTtl);
        $this->parser = new LogParser();
        $this->scanner = new LogScanner($this->cfg->roots, $this->tail);

        $this->entriesSvc = new EntriesService($this->cache, $this->tail, $this->parser, $this->cfg->maxTailLines);
        $this->rl = new RateLimiter('/tmp');
        $this->grep = new GrepRunner($this->sh, $this->tail);

        $this->nginx = new NginxVhosts($this->cfg->nginxVhostDir);
        $this->stats = new StatsService($this->scanner, $this->cache, $this->tail, $this->parser, $this->cfg->dashTail);
        $this->stream = new StreamService($this->scanner, $this->entriesSvc);
    }

    public static function bootstrap(string $baseDir): self
    {
        self::autoload($baseDir . '/src');
        return new self($baseDir);
    }

    public function run(): never
    {
        $req = Request::fromGlobals();
        $path = $req->path;

        $this->requireAuth();

        if (str_starts_with($path, '/assets/')) {
            $this->assets->serve(substr($path, strlen('/assets/')));
        }

        if (str_starts_with($path, '/api/')) {
            $name = trim(substr($path, strlen('/api/')), '/');
            if ($name === '' || !preg_match('~^[a-zA-Z0-9_-]+$~', $name)) {
                (new JsonResponse(['ok' => false, 'error' => 'not found'], 404))->send();
            }

            $res = match ($name) {
                'files'   => (new FilesController($this->scanner))->handle($req),
                'entries' => (new EntriesController($this->scanner, $this->entriesSvc, $this->cfg))->handle($req),
                'grep'    => (new GrepController($this->scanner, $this->grep, $this->rl))->handle($req),
                'health'  => (new HealthController())->handle($req),
                'download'=> (new DownloadController($this->scanner, $this->tail))->handle($req),
                'stream'  => (new StreamController($this->stream))->handle($req),
                'export'  => (new ExportController($this->scanner, $this->entriesSvc, $this->stream))->handle($req),
                'exec'    => (new ExecController($this->cfg, $this->sh))->handle($req),
                'raw'     => (new RawController($this->scanner, $this->tail, $this->cfg))->handle($req),
                'tail'    => (new TailController($this->scanner, $this->tail))->handle($req), // never returns
                default   => new JsonResponse(['ok' => false, 'error' => 'not found'], 404),
            };

            $res->send();
        }

        $page = (string)($_GET['p'] ?? 'dashboard');
        if ($page !== 'dashboard' && $page !== 'logs') $page = 'dashboard';

        $res = match ($page) {
            'logs' => (new LogsController($this->view))->handle($req),
            default => (new DashboardController($this->view, $this->nginx, $this->stats, $this->cfg->cacheTtl))->handle($req),
        };

        $res->send();
    }


    private function requireAuth(): void
    {
        $auth = trim((string)$this->cfg->basicAuth);
        if ($auth === '') return;

        $user = $_SERVER['PHP_AUTH_USER'] ?? '';
        $pass = $_SERVER['PHP_AUTH_PW'] ?? '';

        // Some fastcgi setups provide the header instead
        if ($user === '' && isset($_SERVER['HTTP_AUTHORIZATION'])) {
            $h = (string)$_SERVER['HTTP_AUTHORIZATION'];
            if (stripos($h, 'basic ') === 0) {
                $raw = base64_decode(trim(substr($h, 6)), true);
                if (is_string($raw) && str_contains($raw, ':')) {
                    [$user, $pass] = explode(':', $raw, 2);
                }
            }
        }

        $expected = $auth; // "user:pass"
        $got = (string)$user . ':' . (string)$pass;

        // constant-time compare
        $ok = hash_equals(hash('sha256', $expected), hash('sha256', $got));
        if ($ok) return;

        http_response_code(401);
        header('WWW-Authenticate: Basic realm="LogViewer"');
        header('Content-Type: text/plain; charset=utf-8');
        echo "Unauthorized";
        exit;
    }


    private static function autoload(string $srcDir): void
    {
        spl_autoload_register(static function (string $class) use ($srcDir): void {
            if (!str_starts_with($class, 'LogViewer\\')) return;
            $rel = substr($class, strlen('LogViewer\\'));
            $file = $srcDir . '/' . str_replace('\\', '/', $rel) . '.php';
            if (is_file($file)) require $file;
        });
    }
}

