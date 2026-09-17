<?php
declare(strict_types=1);

namespace AdminPanel\Service;

use AdminPanel\Support\ProcessRunner;

final class AutomationManagerService
{
    private const DEFAULT_CRON_DIR = '/etc/share/scheduler/cron-jobs';
    private const DEFAULT_SUPERVISOR_DIR = '/etc/share/scheduler/supervisor';
    private const DEFAULT_APP_SCAN_DIR = '/app';
    private const DEFAULT_RUNNER_CONTAINER = 'RUNNER';
    private const DEFAULT_TOOLS_CONTAINER = 'SERVER_TOOLS';
    private const DEFAULT_SUPERVISOR_CTL_CONF = '/etc/supervisor/supervisord.conf';
    private const CONTENT_MAX_BYTES = 262144;

    /** @return array<string,mixed> */
    public function listConfigs(): array
    {
        $cronDir = $this->cronDir();
        $supervisorDir = $this->supervisorDir();
        $cronItems = $this->listFiles('cron', $cronDir);
        $supervisorItems = $this->listFiles('supervisor', $supervisorDir);

        return [
            'ok' => true,
            'generated_at' => gmdate('Y-m-d\TH:i:s\Z'),
            'paths' => ['cron' => $cronDir, 'supervisor' => $supervisorDir],
            'writable' => [
                'cron' => $this->isDirWritable($cronDir),
                'supervisor' => $this->isDirWritable($supervisorDir),
            ],
            'summary' => ['cron' => count($cronItems), 'supervisor' => count($supervisorItems)],
            'items' => ['cron' => $cronItems, 'supervisor' => $supervisorItems],
        ];
    }

    /** @return array<string,mixed> */
    public function formOptions(): array
    {
        $allContainers = $this->listRunningContainers();
        $phpContainers = $this->listPhpContainers($allContainers);
        $phpArgSuggestions = $this->phpArgSuggestions();

        return [
            'containers' => ['all' => $allContainers, 'php' => $phpContainers],
            'cron' => [
                'schedule_modes' => [
                    ['value' => 'every_minute', 'label' => 'Every minute'],
                    ['value' => 'every_n_minutes', 'label' => 'Every N minutes'],
                    ['value' => 'hourly', 'label' => 'Hourly'],
                    ['value' => 'every_n_hours', 'label' => 'Every N hours'],
                    ['value' => 'daily', 'label' => 'Daily'],
                    ['value' => 'weekly', 'label' => 'Weekly'],
                    ['value' => 'monthly', 'label' => 'Monthly'],
                    ['value' => 'custom', 'label' => 'Custom fields'],
                ],
                'runner_modes' => [
                    ['value' => 'pexe', 'label' => 'pexe (PHP command in container)'],
                    ['value' => 'dexe', 'label' => 'dexe (shell command in container)'],
                    ['value' => 'custom', 'label' => 'Custom command'],
                ],
                'php_arg_suggestions' => $phpArgSuggestions,
            ],
            'supervisor' => [
                'runner_modes' => [
                    ['value' => 'pexe', 'label' => 'pexe (PHP command in container)'],
                    ['value' => 'dexe', 'label' => 'dexe (shell command in container)'],
                    ['value' => 'custom', 'label' => 'Custom command'],
                ],
                'php_arg_suggestions' => $phpArgSuggestions,
            ],
            'paths' => [
                'cron' => $this->cronDir(),
                'supervisor' => $this->supervisorDir(),
                'app_scan_dir' => $this->appScanDir(),
            ],
        ];
    }

    /** @param array<string,mixed> $payload @return array<string,mixed> */
    public function saveConfig(array $payload): array
    {
        $kind = $this->normalizeKind((string)($payload['kind'] ?? ''));
        if ($kind === null) {
            return ['ok' => false, 'error' => 'validation_kind', 'message' => 'kind must be cron or supervisor.'];
        }

        $name = $this->normalizeName((string)($payload['name'] ?? ''));
        if (!$this->isValidName($name)) {
            return ['ok' => false, 'error' => 'validation_name', 'message' => 'Invalid file name. Use letters, numbers, dot, underscore, and hyphen only.'];
        }

        $originalName = $this->normalizeName((string)($payload['original_name'] ?? ''));
        if ($originalName !== '' && !$this->isValidName($originalName)) {
            return ['ok' => false, 'error' => 'validation_original_name', 'message' => 'Invalid original_name.'];
        }

        $content = $this->normalizeContent((string)($payload['content'] ?? ''));
        if (trim($content) === '') {
            return ['ok' => false, 'error' => 'validation_content', 'message' => 'Config content cannot be empty.'];
        }
        if (strlen($content) > self::CONTENT_MAX_BYTES || str_contains($content, "\0")) {
            return ['ok' => false, 'error' => 'validation_content', 'message' => 'Config content is invalid or too large.'];
        }

        $validation = $this->validateConfigContent($kind, $content);
        if (!(bool)($validation['ok'] ?? false)) {
            return $validation;
        }

        $dir = $this->dirForKind($kind);
        if (!$this->ensureDir($dir) || !$this->isDirWritable($dir)) {
            return ['ok' => false, 'error' => 'config_dir_unavailable', 'message' => 'Failed to create or access config directory: ' . $dir];
        }

        $targetPath = $dir . DIRECTORY_SEPARATOR . $name;
        $oldPath = ($originalName !== '' && $originalName !== $name)
            ? $dir . DIRECTORY_SEPARATOR . $originalName
            : '';
        $targetSnapshot = $this->snapshotFile($targetPath);
        $oldSnapshot = $oldPath !== '' ? $this->snapshotFile($oldPath) : null;

        $stage = @tempnam($dir, '.lds-stage-');
        if (!is_string($stage) || $stage === '') {
            return ['ok' => false, 'error' => 'write_failed', 'message' => 'Unable to create staged config.'];
        }

        try {
            $bytes = @file_put_contents($stage, $content, LOCK_EX);
            if (!is_int($bytes) || $bytes !== strlen($content)) {
                return ['ok' => false, 'error' => 'write_failed', 'message' => 'Unable to stage config file: ' . $name];
            }
            @chmod($stage, $targetSnapshot['mode'] ?? 0644);

            if (!@rename($stage, $targetPath)) {
                return ['ok' => false, 'error' => 'write_failed', 'message' => 'Unable to install config file atomically: ' . $name];
            }
            $stage = '';

            $reload = null;
            if ($kind === 'supervisor') {
                $reload = $this->reloadSupervisor();
                if (!(bool)($reload['ok'] ?? false)) {
                    $this->restoreFile($targetPath, $targetSnapshot);
                    if ($oldPath !== '') {
                        $this->restoreFile($oldPath, $oldSnapshot);
                    }
                    $this->reloadSupervisor();
                    return [
                        'ok' => false,
                        'error' => 'supervisor_reload_failed',
                        'message' => 'Supervisor rejected the update; previous config restored.',
                        'reload' => $reload,
                    ];
                }
            }

            if ($oldPath !== '' && is_file($oldPath) && !@unlink($oldPath)) {
                $this->restoreFile($targetPath, $targetSnapshot);
                $this->restoreFile($oldPath, $oldSnapshot);
                if ($kind === 'supervisor') {
                    $this->reloadSupervisor();
                }
                return ['ok' => false, 'error' => 'rename_cleanup_failed', 'message' => 'Unable to remove previous config name; previous state restored.'];
            }

            $message = ucfirst($kind) . ' config saved.';
            if ($kind === 'supervisor') {
                $message .= ' Supervisor reread/update applied.';
            }
            $list = $this->listConfigs();
            return [
                'ok' => true,
                'message' => $message,
                'kind' => $kind,
                'name' => $name,
                'reload' => $reload,
                'item' => $this->findItem($list, $kind, $name),
                'summary' => $list['summary'] ?? [],
            ];
        } finally {
            if (is_string($stage) && $stage !== '' && is_file($stage)) {
                @unlink($stage);
            }
        }
    }

    /** @return array<string,mixed> */
    public function deleteConfig(string $kindInput, string $nameInput): array
    {
        $kind = $this->normalizeKind($kindInput);
        if ($kind === null) {
            return ['ok' => false, 'error' => 'validation_kind', 'message' => 'kind must be cron or supervisor.'];
        }
        $name = $this->normalizeName($nameInput);
        if (!$this->isValidName($name)) {
            return ['ok' => false, 'error' => 'validation_name', 'message' => 'Invalid file name.'];
        }

        $path = $this->dirForKind($kind) . DIRECTORY_SEPARATOR . $name;
        if (!is_file($path)) {
            return ['ok' => false, 'error' => 'not_found', 'message' => 'Config file not found: ' . $name];
        }

        $snapshot = $this->snapshotFile($path);
        $backup = dirname($path) . DIRECTORY_SEPARATOR . '.lds-delete-' . bin2hex(random_bytes(6));
        if (!@rename($path, $backup)) {
            return ['ok' => false, 'error' => 'delete_failed', 'message' => 'Failed to stage config deletion: ' . $name];
        }

        $reload = null;
        if ($kind === 'supervisor') {
            $reload = $this->reloadSupervisor();
            if (!(bool)($reload['ok'] ?? false)) {
                @rename($backup, $path);
                $this->restoreFile($path, $snapshot);
                $this->reloadSupervisor();
                return [
                    'ok' => false,
                    'error' => 'supervisor_reload_failed',
                    'message' => 'Supervisor rejected the deletion; previous config restored.',
                    'reload' => $reload,
                ];
            }
        }

        if (is_file($backup)) {
            @unlink($backup);
        }

        $message = ucfirst($kind) . ' config deleted.';
        if ($kind === 'supervisor') {
            $message .= ' Supervisor reread/update applied.';
        }
        $list = $this->listConfigs();
        return [
            'ok' => true,
            'message' => $message,
            'kind' => $kind,
            'name' => $name,
            'reload' => $reload,
            'summary' => $list['summary'] ?? [],
        ];
    }

    /** @return array<int,array<string,mixed>> */
    private function listFiles(string $kind, string $dir): array
    {
        if (!is_dir($dir)) {
            return [];
        }
        $entries = @scandir($dir);
        if (!is_array($entries)) {
            return [];
        }

        $items = [];
        foreach ($entries as $entry) {
            $name = trim((string)$entry);
            if ($name === '' || $name === '.' || $name === '..' || str_starts_with($name, '.')) {
                continue;
            }
            $path = $dir . DIRECTORY_SEPARATOR . $name;
            if (!is_file($path)) {
                continue;
            }
            $content = $this->readContent($path);
            $mtime = @filemtime($path);
            $items[] = [
                'kind' => $kind,
                'name' => $name,
                'path' => $path,
                'size' => strlen($content),
                'updated_at' => $mtime !== false ? gmdate('Y-m-d\TH:i:s\Z', (int)$mtime) : gmdate('Y-m-d\TH:i:s\Z'),
                'read_only' => !is_writable($path),
                'summary' => $this->buildSummary($kind, $content),
                'content' => $content,
            ];
        }

        usort($items, static fn(array $a, array $b): int => strcmp((string)($a['name'] ?? ''), (string)($b['name'] ?? '')));
        return $items;
    }

    private function readContent(string $path): string
    {
        $raw = @file_get_contents($path, false, null, 0, self::CONTENT_MAX_BYTES);
        if (!is_string($raw)) {
            return '';
        }
        return str_replace(["\r\n", "\r"], "\n", $raw);
    }

    private function buildSummary(string $kind, string $content): string
    {
        $lines = preg_split('/\n/', $content) ?: [];
        foreach ($lines as $line) {
            $line = trim((string)$line);
            if ($line === '') {
                continue;
            }
            if ($kind === 'cron' && str_starts_with($line, '#')) {
                continue;
            }
            if ($kind === 'supervisor' && (str_starts_with($line, ';') || str_starts_with($line, '#'))) {
                continue;
            }
            return strlen($line) > 120 ? substr($line, 0, 117) . '...' : $line;
        }
        return '-';
    }

    private function normalizeContent(string $content): string
    {
        $content = str_replace(["\r\n", "\r"], "\n", $content);
        if ($content !== '' && !str_ends_with($content, "\n")) {
            $content .= "\n";
        }
        return $content;
    }

    /** @return array<string,mixed> */
    private function validateConfigContent(string $kind, string $content): array
    {
        if ($kind === 'supervisor') {
            $container = $this->runnerContainer();
            $script = "tmp=\$(mktemp); cat >\"\$tmp\"; supervisord -t -c \"\$tmp\" >/dev/null; rc=\$?; rm -f \"\$tmp\"; exit \$rc";
            $res = ProcessRunner::run(['docker', 'exec', '-i', $container, 'sh', '-c', $script], 15, $content, 131072);
            if (!(bool)($res['ok'] ?? false)) {
                return [
                    'ok' => false,
                    'error' => 'validation_supervisor',
                    'message' => trim((string)($res['stderr'] ?? 'Supervisor config validation failed.')) ?: 'Supervisor config validation failed.',
                ];
            }
            return ['ok' => true];
        }

        $lines = preg_split('/\n/', $content) ?: [];
        foreach ($lines as $line) {
            $line = trim((string)$line);
            if ($line === '' || str_starts_with($line, '#') || preg_match('/^[A-Za-z_][A-Za-z0-9_]*=/', $line) === 1) {
                continue;
            }
            $parts = preg_split('/\s+/', $line, 7) ?: [];
            if (count($parts) < 7) {
                return ['ok' => false, 'error' => 'validation_cron', 'message' => 'Cron entries must use /etc/cron.d format: five schedule fields, user, and command.'];
            }
        }
        return ['ok' => true];
    }

    /** @return array{content:string,mode:int}|null */
    private function snapshotFile(string $path): ?array
    {
        if (!is_file($path)) {
            return null;
        }
        $content = @file_get_contents($path);
        if (!is_string($content)) {
            return null;
        }
        $perms = @fileperms($path);
        return ['content' => $content, 'mode' => is_int($perms) ? ($perms & 0777) : 0644];
    }

    /** @param array{content:string,mode:int}|null $snapshot */
    private function restoreFile(string $path, ?array $snapshot): void
    {
        if ($snapshot === null) {
            @unlink($path);
            return;
        }
        $dir = dirname($path);
        $tmp = @tempnam($dir, '.lds-restore-');
        if (!is_string($tmp) || $tmp === '') {
            return;
        }
        if (@file_put_contents($tmp, $snapshot['content'], LOCK_EX) === false) {
            @unlink($tmp);
            return;
        }
        @chmod($tmp, $snapshot['mode']);
        @rename($tmp, $path);
    }

    private function normalizeName(string $value): string
    {
        return trim($value);
    }

    private function isValidName(string $name): bool
    {
        if ($name === '' || strlen($name) > 128) {
            return false;
        }
        if (str_contains($name, '/') || str_contains($name, '\\')) {
            return false;
        }
        return preg_match('/^[A-Za-z0-9][A-Za-z0-9._-]*$/', $name) === 1;
    }

    private function ensureDir(string $dir): bool
    {
        return is_dir($dir) || @mkdir($dir, 0775, true);
    }

    private function isDirWritable(string $dir): bool
    {
        return is_dir($dir) && is_writable($dir);
    }

    private function cronDir(): string
    {
        $env = trim((string)getenv('ADMIN_PANEL_CRON_DIR'));
        return $env !== '' ? $env : self::DEFAULT_CRON_DIR;
    }

    private function supervisorDir(): string
    {
        $env = trim((string)getenv('ADMIN_PANEL_SUPERVISOR_DIR'));
        return $env !== '' ? $env : self::DEFAULT_SUPERVISOR_DIR;
    }

    private function runnerContainer(): string
    {
        $env = trim((string)getenv('ADMIN_PANEL_RUNNER_CONTAINER'));
        return $env !== '' ? $env : self::DEFAULT_RUNNER_CONTAINER;
    }

    private function toolsContainer(): string
    {
        $env = trim((string)getenv('ADMIN_PANEL_TOOLS_CONTAINER'));
        return $env !== '' ? $env : self::DEFAULT_TOOLS_CONTAINER;
    }

    private function supervisorCtlConf(): string
    {
        $env = trim((string)getenv('ADMIN_PANEL_RUNNER_SUPERVISOR_CONF'));
        return $env !== '' ? $env : self::DEFAULT_SUPERVISOR_CTL_CONF;
    }

    private function normalizeKind(string $kind): ?string
    {
        $k = strtolower(trim($kind));
        return in_array($k, ['cron', 'supervisor'], true) ? $k : null;
    }

    private function dirForKind(string $kind): string
    {
        return $kind === 'cron' ? $this->cronDir() : $this->supervisorDir();
    }

    /** @param array<string,mixed> $list @return array<string,mixed>|null */
    private function findItem(array $list, string $kind, string $name): ?array
    {
        $itemsByKind = $list['items'] ?? [];
        if (!is_array($itemsByKind)) {
            return null;
        }
        $items = $itemsByKind[$kind] ?? [];
        if (!is_array($items)) {
            return null;
        }
        foreach ($items as $item) {
            if (is_array($item) && (string)($item['name'] ?? '') === $name) {
                return $item;
            }
        }
        return null;
    }

    /** @return array<string,mixed> */
    private function reloadSupervisor(): array
    {
        $base = ['docker', 'exec', $this->runnerContainer(), 'supervisorctl', '-c', $this->supervisorCtlConf()];
        $reread = $this->runCommand(array_merge($base, ['reread']));
        if (!(bool)($reread['ok'] ?? false)) {
            return ['ok' => false, 'step' => 'reread', 'exit_code' => $reread['exit_code'] ?? 1, 'message' => trim((string)($reread['stderr'] ?? 'supervisor reread failed'))];
        }
        $update = $this->runCommand(array_merge($base, ['update']));
        if (!(bool)($update['ok'] ?? false)) {
            return ['ok' => false, 'step' => 'update', 'exit_code' => $update['exit_code'] ?? 1, 'message' => trim((string)($update['stderr'] ?? 'supervisor update failed'))];
        }
        $out = trim(((string)($reread['stdout'] ?? '')) . "\n" . ((string)($update['stdout'] ?? '')));
        return ['ok' => true, 'message' => $out !== '' ? $out : 'Supervisor reread/update completed.'];
    }

    /** @param list<string> $command @return array{ok:bool,stdout:string,stderr:string,exit_code:int,timed_out?:bool,output_limited?:bool} */
    private function runCommand(array $command): array
    {
        return ProcessRunner::run($command, 30, null, 262144);
    }

    private function appScanDir(): string
    {
        $env = trim((string)getenv('APP_SCAN_DIR'));
        return $env !== '' ? $env : self::DEFAULT_APP_SCAN_DIR;
    }

    private function composeProject(): string
    {
        foreach (['LDS_COMPOSE_PROJECT', 'COMPOSE_PROJECT_NAME'] as $key) {
            $value = trim((string)getenv($key));
            if ($value !== '') {
                return $value;
            }
        }
        $res = $this->runCommand(['docker', 'inspect', '--format', '{{ index .Config.Labels "com.docker.compose.project" }}', $this->toolsContainer()]);
        return (bool)($res['ok'] ?? false) ? trim((string)($res['stdout'] ?? '')) : '';
    }

    /** @return array<int,string> */
    private function listRunningContainers(): array
    {
        $project = $this->composeProject();
        if ($project === '') {
            return [];
        }
        $res = $this->runCommand(['docker', 'ps', '--filter', 'label=com.docker.compose.project=' . $project, '--format', '{{.Names}}']);
        if (!(bool)($res['ok'] ?? false)) {
            return [];
        }
        $out = trim((string)($res['stdout'] ?? ''));
        if ($out === '') {
            return [];
        }
        $rows = preg_split('/\R+/', $out) ?: [];
        $items = [];
        $seen = [];
        foreach ($rows as $row) {
            $name = trim((string)$row);
            if ($name === '' || isset($seen[$name])) {
                continue;
            }
            $seen[$name] = true;
            $items[] = $name;
        }
        sort($items, SORT_NATURAL | SORT_FLAG_CASE);
        return $items;
    }

    /** @param array<int,string> $containers @return array<int,string> */
    private function listPhpContainers(array $containers): array
    {
        $out = [];
        foreach ($containers as $name) {
            $n = strtolower(trim($name));
            if ($n !== '' && (preg_match('/^php[_-]/i', $name) === 1 || str_contains($n, 'php'))) {
                $out[] = $name;
            }
        }
        sort($out, SORT_NATURAL | SORT_FLAG_CASE);
        return array_values(array_unique($out));
    }

    /** @return array<int,string> */
    private function phpArgSuggestions(): array
    {
        $base = rtrim($this->appScanDir(), '/\\');
        $candidates = [];
        $add = static function (array &$arr, string $value): void {
            $v = trim($value);
            if ($v !== '' && !in_array($v, $arr, true)) {
                $arr[] = $v;
            }
        };

        if (is_file($base . '/artisan')) {
            $add($candidates, 'artisan schedule:run');
            $add($candidates, 'artisan queue:work --sleep=1 --tries=3');
            $add($candidates, 'artisan queue:restart');
        }
        if (is_file($base . '/bin/console')) {
            $add($candidates, 'bin/console messenger:consume async --time-limit=3600');
            $add($candidates, 'bin/console cache:clear');
        }
        if (is_file($base . '/yii')) {
            $add($candidates, 'yii queue/listen');
        }
        if (is_file($base . '/think')) {
            $add($candidates, 'think queue:work');
        }
        if ($candidates === []) {
            $candidates = [
                'artisan schedule:run',
                'artisan queue:work --sleep=1 --tries=3',
                'bin/console messenger:consume async --time-limit=3600',
            ];
        }
        return $candidates;
    }
}
