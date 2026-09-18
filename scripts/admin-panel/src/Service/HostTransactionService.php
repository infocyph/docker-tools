<?php
declare(strict_types=1);

namespace AdminPanel\Service;

use AdminPanel\Support\ProcessRunner;
use RecursiveDirectoryIterator;
use RecursiveIteratorIterator;
use RuntimeException;

final class HostTransactionService
{
    private const DEFAULT_VHOST_ROOT = '/etc/share/vhosts';
    private const DEFAULT_STATE_FILE = '/etc/share/state/env-store.json';
    private const DEFAULT_CERT_DIR = '/etc/mkcert';
    private const DEFAULT_EXPORT_DIR = '/etc/share/certs';
    private const DEFAULT_PROJECT = 'LocalDevStack';
    private const LOCK_FILE = '/run/host-manager.lock';

    private HostManagerService $hosts;

    public function __construct(?HostManagerService $hosts = null)
    {
        $this->hosts = $hosts ?? new HostManagerService();
    }

    /** @param array<string,mixed> $payload @return array<string,mixed> */
    public function addHost(array $payload): array
    {
        return $this->mutate(static fn(HostManagerService $service): array => $service->addHost($payload));
    }

    /** @param array<string,mixed> $payload @return array<string,mixed> */
    public function editHost(array $payload): array
    {
        return $this->mutate(static fn(HostManagerService $service): array => $service->editHost($payload));
    }

    /** @return array<string,mixed> */
    public function deleteHost(string $domain): array
    {
        return $this->mutate(static fn(HostManagerService $service): array => $service->deleteHost($domain));
    }

    /**
     * @param callable(HostManagerService):array<string,mixed> $operation
     * @return array<string,mixed>
     */
    private function mutate(callable $operation): array
    {
        $lock = @fopen(self::LOCK_FILE, 'c+');
        if (!is_resource($lock) || !@flock($lock, LOCK_EX | LOCK_NB)) {
            if (is_resource($lock)) {
                @fclose($lock);
            }
            return [
                'ok' => false,
                'error' => 'host_mutation_busy',
                'message' => 'Another host mutation is already in progress.',
            ];
        }

        $stage = rtrim(sys_get_temp_dir(), '/\\') . DIRECTORY_SEPARATOR . 'lds-host-stage-' . bin2hex(random_bytes(8));
        $envBefore = $this->captureEnvironment();
        $liveRoot = $this->vhostRoot();
        $liveState = $this->stateFile();
        $changes = [];
        $certSnapshot = [];
        $exportSnapshot = [];

        try {
            $this->createStage($stage, $liveRoot, $liveState);
            $this->prepareStageCommands($stage);
            $this->applyStageEnvironment($stage);

            $result = $operation($this->hosts);
            if (!(bool)($result['ok'] ?? false)) {
                $result['transaction'] = 'staged_no_live_change';
                return $result;
            }

            $changes = $this->buildChanges($stage . '/vhosts', $liveRoot);
            $stateChange = $this->buildSingleFileChange($stage . '/state/env-store.json', $liveState);
            if ($stateChange !== null) {
                $changes[] = $stateChange;
            }

            $this->restoreEnvironment($envBefore);
            $this->applyChanges($changes);

            $validation = $this->validateLiveWebServers();
            if (!(bool)($validation['ok'] ?? false)) {
                $this->rollbackChanges($changes);
                return [
                    'ok' => false,
                    'error' => 'host_runtime_validation_failed',
                    'message' => (string)($validation['message'] ?? 'Generated web-server configuration failed validation.'),
                    'validation' => $validation,
                    'transaction' => 'rolled_back',
                ];
            }

            $certSnapshot = $this->snapshotTree($this->certDir());
            $exportSnapshot = $this->snapshotTree($this->exportDir());
            $cert = ProcessRunner::run(['certify'], 120, null, 262144);
            if (!(bool)($cert['ok'] ?? false)) {
                $this->rollbackChanges($changes);
                $this->restoreTreeSnapshot($this->certDir(), $certSnapshot);
                $this->restoreTreeSnapshot($this->exportDir(), $exportSnapshot);
                return [
                    'ok' => false,
                    'error' => 'host_certify_failed',
                    'message' => 'Host mutation was rolled back because certificate refresh failed.',
                    'detail' => trim((string)($cert['stderr'] ?? '')),
                    'transaction' => 'rolled_back',
                ];
            }

            $liveList = $this->hosts->listHosts();
            $result['transaction'] = 'committed';
            $result['validation'] = $validation;
            if (isset($result['domain'])) {
                $result['host'] = $this->findHost($liveList, (string)$result['domain']);
            }
            $result['summary'] = $liveList['summary'] ?? ($result['summary'] ?? []);
            return $result;
        } catch (RuntimeException $e) {
            $this->restoreEnvironment($envBefore);
            if ($changes !== []) {
                $this->rollbackChanges($changes);
            }
            if ($certSnapshot !== []) {
                $this->restoreTreeSnapshot($this->certDir(), $certSnapshot);
            }
            if ($exportSnapshot !== []) {
                $this->restoreTreeSnapshot($this->exportDir(), $exportSnapshot);
            }
            return [
                'ok' => false,
                'error' => 'host_transaction_failed',
                'message' => $e->getMessage(),
                'transaction' => 'rolled_back',
            ];
        } finally {
            $this->restoreEnvironment($envBefore);
            $this->removeTree($stage);
            @flock($lock, LOCK_UN);
            @fclose($lock);
        }
    }

    /** @return array<string,string|null> */
    private function captureEnvironment(): array
    {
        $keys = [
            'PATH',
            'VHOST_ROOT', 'VHOST_NGINX_DIR', 'VHOST_APACHE_DIR', 'VHOST_FPM_DIR',
            'VHOST_DOCKER_COMPOSE_DIR', 'NGINX_DIR', 'APACHE_DIR', 'FPM_DIR', 'COMPOSE_DIR',
            'ENV_STORE_JSON', 'CERT_DIR', 'VHOST_DIR', 'EXPORT_DIR', 'LDS_USER_P12_ENABLED',
        ];
        $out = [];
        foreach ($keys as $key) {
            $value = getenv($key);
            $out[$key] = $value === false ? null : (string)$value;
        }
        return $out;
    }

    /** @param array<string,string|null> $values */
    private function restoreEnvironment(array $values): void
    {
        foreach ($values as $key => $value) {
            if ($value === null) {
                putenv($key);
            } else {
                putenv($key . '=' . $value);
            }
        }
    }

    private function prepareStageCommands(string $stage): void
    {
        $binDir = $stage . '/bin';
        if (!@mkdir($binDir, 0700, true) && !is_dir($binDir)) {
            throw new RuntimeException('Unable to create host staging command directory.');
        }

        foreach (['mkhost', 'rmhost', 'env-store'] as $command) {
            $source = '/usr/local/bin/' . $command;
            $target = $binDir . DIRECTORY_SEPARATOR . $command;
            if (!is_file($source) || !@symlink($source, $target)) {
                throw new RuntimeException('Required host-management command is unavailable: ' . $command);
            }
        }
    }

    private function applyStageEnvironment(string $stage): void
    {
        $vhosts = $stage . '/vhosts';
        putenv('PATH=' . $stage . '/bin:/usr/bin:/bin');
        putenv('VHOST_ROOT=' . $vhosts);
        putenv('VHOST_NGINX_DIR=' . $vhosts . '/nginx');
        putenv('VHOST_APACHE_DIR=' . $vhosts . '/apache');
        putenv('VHOST_FPM_DIR=' . $vhosts . '/fpm');
        putenv('VHOST_DOCKER_COMPOSE_DIR=' . $vhosts . '/docker-compose');
        putenv('NGINX_DIR=' . $vhosts . '/nginx');
        putenv('APACHE_DIR=' . $vhosts . '/apache');
        putenv('FPM_DIR=' . $vhosts . '/fpm');
        putenv('COMPOSE_DIR=' . $vhosts . '/docker-compose');
        putenv('ENV_STORE_JSON=' . $stage . '/state/env-store.json');
        putenv('CERT_DIR=' . $stage . '/certs');
        putenv('VHOST_DIR=' . $vhosts);
        putenv('EXPORT_DIR=' . $stage . '/exports');
        putenv('LDS_USER_P12_ENABLED=0');
    }

    private function createStage(string $stage, string $liveRoot, string $liveState): void
    {
        foreach (['vhosts/nginx', 'vhosts/apache', 'vhosts/fpm', 'vhosts/docker-compose', 'state', 'certs', 'exports'] as $dir) {
            if (!@mkdir($stage . '/' . $dir, 0700, true) && !is_dir($stage . '/' . $dir)) {
                throw new RuntimeException('Unable to create host staging directory.');
            }
        }

        foreach (['nginx', 'apache', 'fpm', 'docker-compose'] as $part) {
            $src = rtrim($liveRoot, '/\\') . DIRECTORY_SEPARATOR . $part;
            if (is_dir($src)) {
                $this->copyTree($src, $stage . '/vhosts/' . $part);
            }
        }

        if (is_file($liveState)) {
            $this->copyFile($liveState, $stage . '/state/env-store.json');
        }
    }

    /** @return list<array<string,mixed>> */
    private function buildChanges(string $stageRoot, string $liveRoot): array
    {
        $changes = [];
        foreach (['nginx', 'apache', 'fpm', 'docker-compose'] as $part) {
            $stageDir = $stageRoot . '/' . $part;
            $liveDir = rtrim($liveRoot, '/\\') . DIRECTORY_SEPARATOR . $part;
            $stageFiles = $this->fileMap($stageDir);
            $liveFiles = $this->fileMap($liveDir);
            $paths = array_values(array_unique(array_merge(array_keys($stageFiles), array_keys($liveFiles))));
            sort($paths, SORT_STRING);

            foreach ($paths as $relative) {
                $stageFile = $stageFiles[$relative] ?? null;
                $liveFile = $liveFiles[$relative] ?? null;
                if ($stageFile !== null && $liveFile !== null && hash_file('sha256', $stageFile) === hash_file('sha256', $liveFile)) {
                    continue;
                }
                $changes[] = $this->makeChange($stageFile, $liveDir . DIRECTORY_SEPARATOR . $relative);
            }
        }
        return $changes;
    }

    /** @return array<string,mixed>|null */
    private function buildSingleFileChange(string $stageFile, string $liveFile): ?array
    {
        if (!is_file($stageFile) && !is_file($liveFile)) {
            return null;
        }
        if (is_file($stageFile) && is_file($liveFile) && hash_file('sha256', $stageFile) === hash_file('sha256', $liveFile)) {
            return null;
        }
        return $this->makeChange(is_file($stageFile) ? $stageFile : null, $liveFile);
    }

    /** @return array<string,mixed> */
    private function makeChange(?string $stageFile, string $liveFile): array
    {
        $backup = $this->snapshotFile($liveFile);
        $replacement = $stageFile !== null ? $this->snapshotFile($stageFile) : null;
        return ['path' => $liveFile, 'backup' => $backup, 'replacement' => $replacement, 'applied' => false];
    }

    /** @return array{content:string,mode:int}|null */
    private function snapshotFile(string $path): ?array
    {
        if (!is_file($path)) {
            return null;
        }
        $content = @file_get_contents($path);
        if (!is_string($content)) {
            throw new RuntimeException('Unable to snapshot file: ' . $path);
        }
        $perms = @fileperms($path);
        return ['content' => $content, 'mode' => is_int($perms) ? ($perms & 0777) : 0644];
    }

    /** @param list<array<string,mixed>> $changes */
    private function applyChanges(array &$changes): void
    {
        foreach ($changes as $index => $change) {
            $path = (string)$change['path'];
            $replacement = $change['replacement'] ?? null;
            if ($replacement === null) {
                if (is_file($path) && !@unlink($path)) {
                    throw new RuntimeException('Unable to remove obsolete host configuration.');
                }
                $changes[$index]['applied'] = true;
                continue;
            }
            $this->atomicWrite($path, (string)$replacement['content'], (int)$replacement['mode']);
            $changes[$index]['applied'] = true;
        }
    }

    /** @param list<array<string,mixed>> $changes */
    private function rollbackChanges(array $changes): void
    {
        for ($index = count($changes) - 1; $index >= 0; --$index) {
            $change = $changes[$index];
            if (!(bool)($change['applied'] ?? false)) {
                continue;
            }
            $path = (string)$change['path'];
            $backup = $change['backup'] ?? null;
            if ($backup === null) {
                @unlink($path);
                continue;
            }
            try {
                $this->atomicWrite($path, (string)$backup['content'], (int)$backup['mode']);
            } catch (RuntimeException) {
                // Best-effort rollback; preserve the original failure for the caller.
            }
        }
    }

    private function atomicWrite(string $path, string $content, int $mode): void
    {
        $dir = dirname($path);
        if (!is_dir($dir) && !@mkdir($dir, 0775, true) && !is_dir($dir)) {
            throw new RuntimeException('Unable to create configuration directory: ' . $dir);
        }
        $tmp = @tempnam($dir, '.lds-atomic-');
        if (!is_string($tmp) || $tmp === '') {
            throw new RuntimeException('Unable to stage atomic configuration replacement.');
        }
        if (@file_put_contents($tmp, $content, LOCK_EX) === false) {
            @unlink($tmp);
            throw new RuntimeException('Unable to write staged configuration replacement.');
        }
        @chmod($tmp, $mode);
        if (!@rename($tmp, $path)) {
            @unlink($tmp);
            throw new RuntimeException('Unable to atomically replace configuration file.');
        }
    }

    /** @return array<string,mixed> */
    private function validateLiveWebServers(): array
    {
        $project = trim((string)getenv('COMPOSE_PROJECT_NAME'));
        if ($project === '') {
            $project = self::DEFAULT_PROJECT;
        }

        $checks = [];
        foreach ([
            ['service' => 'nginx', 'command' => ['nginx', '-t']],
            ['service' => 'apache', 'command' => ['httpd', '-t']],
        ] as $spec) {
            $container = $this->findProjectContainer($project, (string)$spec['service']);
            if ($container === null) {
                $checks[] = ['service' => $spec['service'], 'status' => 'not_running'];
                continue;
            }
            $command = array_merge(['docker', 'exec', $container], $spec['command']);
            $res = ProcessRunner::run($command, 20, null, 131072);
            if (!(bool)($res['ok'] ?? false)) {
                return [
                    'ok' => false,
                    'project' => $project,
                    'service' => $spec['service'],
                    'message' => trim((string)($res['stderr'] ?? '')) ?: ((string)$spec['service'] . ' configuration validation failed.'),
                    'checks' => $checks,
                ];
            }
            $checks[] = ['service' => $spec['service'], 'status' => 'valid'];
        }

        return ['ok' => true, 'project' => $project, 'checks' => $checks];
    }

    private function findProjectContainer(string $project, string $service): ?string
    {
        $res = ProcessRunner::run([
            'docker', 'ps',
            '--filter', 'label=com.docker.compose.project=' . $project,
            '--filter', 'label=com.docker.compose.service=' . $service,
            '--format', '{{.ID}}',
        ], 10, null, 32768);
        if (!(bool)($res['ok'] ?? false)) {
            return null;
        }
        $lines = preg_split('/\R+/', trim((string)($res['stdout'] ?? ''))) ?: [];
        $id = trim((string)($lines[0] ?? ''));
        return $id !== '' ? $id : null;
    }

    /** @return array<string,array{content:string,mode:int}> */
    private function snapshotTree(string $root): array
    {
        $snapshot = [];
        foreach ($this->fileMap($root) as $relative => $path) {
            $file = $this->snapshotFile($path);
            if ($file !== null) {
                $snapshot[$relative] = $file;
            }
        }
        return $snapshot;
    }

    /** @param array<string,array{content:string,mode:int}> $snapshot */
    private function restoreTreeSnapshot(string $root, array $snapshot): void
    {
        if (!is_dir($root)) {
            @mkdir($root, 0755, true);
        }
        foreach ($this->fileMap($root) as $path) {
            @unlink($path);
        }
        foreach ($snapshot as $relative => $file) {
            try {
                $this->atomicWrite(rtrim($root, '/\\') . DIRECTORY_SEPARATOR . $relative, $file['content'], $file['mode']);
            } catch (RuntimeException) {
                // Best-effort certificate rollback.
            }
        }
    }

    /** @return array<string,string> */
    private function fileMap(string $root): array
    {
        if (!is_dir($root)) {
            return [];
        }
        $map = [];
        $iterator = new RecursiveIteratorIterator(new RecursiveDirectoryIterator($root, RecursiveDirectoryIterator::SKIP_DOTS));
        foreach ($iterator as $file) {
            if (!$file->isFile()) {
                continue;
            }
            $path = $file->getPathname();
            $relative = ltrim(substr($path, strlen(rtrim($root, '/\\'))), '/\\');
            $map[$relative] = $path;
        }
        return $map;
    }

    private function copyTree(string $src, string $dst): void
    {
        foreach ($this->fileMap($src) as $relative => $file) {
            $target = rtrim($dst, '/\\') . DIRECTORY_SEPARATOR . $relative;
            $dir = dirname($target);
            if (!is_dir($dir) && !@mkdir($dir, 0700, true) && !is_dir($dir)) {
                throw new RuntimeException('Unable to clone host configuration tree.');
            }
            $this->copyFile($file, $target);
        }
    }

    private function copyFile(string $src, string $dst): void
    {
        $content = @file_get_contents($src);
        if (!is_string($content) || @file_put_contents($dst, $content, LOCK_EX) === false) {
            throw new RuntimeException('Unable to clone host configuration file.');
        }
        $perms = @fileperms($src);
        @chmod($dst, is_int($perms) ? ($perms & 0777) : 0644);
    }

    private function removeTree(string $root): void
    {
        if (!is_dir($root)) {
            return;
        }
        $iterator = new RecursiveIteratorIterator(
            new RecursiveDirectoryIterator($root, RecursiveDirectoryIterator::SKIP_DOTS),
            RecursiveIteratorIterator::CHILD_FIRST
        );
        foreach ($iterator as $file) {
            $path = $file->getPathname();
            $file->isDir() ? @rmdir($path) : @unlink($path);
        }
        @rmdir($root);
    }

    /** @param array<string,mixed> $list @return array<string,mixed>|null */
    private function findHost(array $list, string $domain): ?array
    {
        $items = $list['items'] ?? [];
        if (!is_array($items)) {
            return null;
        }
        foreach ($items as $item) {
            if (is_array($item) && strtolower((string)($item['domain'] ?? '')) === strtolower($domain)) {
                return $item;
            }
        }
        return null;
    }

    private function vhostRoot(): string
    {
        $root = trim((string)getenv('VHOST_ROOT'));
        return $root !== '' ? $root : self::DEFAULT_VHOST_ROOT;
    }

    private function stateFile(): string
    {
        $path = trim((string)getenv('ENV_STORE_JSON'));
        return $path !== '' ? $path : self::DEFAULT_STATE_FILE;
    }

    private function certDir(): string
    {
        $path = trim((string)getenv('CERT_DIR'));
        return $path !== '' ? $path : self::DEFAULT_CERT_DIR;
    }

    private function exportDir(): string
    {
        $path = trim((string)getenv('EXPORT_DIR'));
        return $path !== '' ? $path : self::DEFAULT_EXPORT_DIR;
    }
}
