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
            return ['ok' => false, 'error' => 'host_mutation_busy', 'message' => 'Another host mutation is already in progress.'];
        }

        $stage = rtrim(sys_get_temp_dir(), '/\\') . DIRECTORY_SEPARATOR . 'lds-host-stage-' . bin2hex(random_bytes(8));
        $envBefore = $this->captureEnvironment();
        $liveRoot = $this->vhostRoot();
        $liveState = $this->stateFile();
        $changes = [];

        try {
            $this->createStage($stage, $liveRoot, $liveState);
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

            $cert = ProcessRunner::run(['certify'], 120, null, 262144);
            if (!(bool)($cert['ok'] ?? false)) {
                $this->rollbackChanges($changes);
                return [
                    'ok' => false,
                    'error' => 'host_certify_failed',
                    'message' => 'Host mutation was rolled back because certificate refresh failed.',
                    'detail' => trim((string)($cert['stderr'] ?? '')),
                ];
            }

            $liveList = $this->hosts->listHosts();
            $result['transaction'] = 'committed';
            $result['host'] = isset($result['domain']) ? $this->findHost($liveList, (string)$result['domain']) : ($result['host'] ?? null);
            $result['summary'] = $liveList['summary'] ?? ($result['summary'] ?? []);
            return $result;
        } catch (RuntimeException $e) {
            $this->restoreEnvironment($envBefore);
            if ($changes !== []) {
                $this->rollbackChanges($changes);
            }
            return ['ok' => false, 'error' => 'host_transaction_failed', 'message' => $e->getMessage()];
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

    private function applyStageEnvironment(string $stage): void
    {
        $vhosts = $stage . '/vhosts';
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
        $backup = null;
        if (is_file($liveFile)) {
            $content = @file_get_contents($liveFile);
            if (!is_string($content)) {
                throw new RuntimeException('Unable to snapshot live host configuration.');
            }
            $perms = @fileperms($liveFile);
            $backup = ['content' => $content, 'mode' => is_int($perms) ? ($perms & 0777) : 0644];
        }

        $replacement = null;
        if ($stageFile !== null && is_file($stageFile)) {
            $content = @file_get_contents($stageFile);
            if (!is_string($content)) {
                throw new RuntimeException('Unable to read staged host configuration.');
            }
            $perms = @fileperms($stageFile);
            $replacement = ['content' => $content, 'mode' => is_int($perms) ? ($perms & 0777) : 0644];
        }

        return ['path' => $liveFile, 'backup' => $backup, 'replacement' => $replacement, 'applied' => false];
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

            $dir = dirname($path);
            if (!is_dir($dir) && !@mkdir($dir, 0775, true) && !is_dir($dir)) {
                throw new RuntimeException('Unable to create live host configuration directory.');
            }
            $tmp = @tempnam($dir, '.lds-host-commit-');
            if (!is_string($tmp) || $tmp === '') {
                throw new RuntimeException('Unable to stage live host configuration replacement.');
            }
            if (@file_put_contents($tmp, (string)$replacement['content'], LOCK_EX) === false) {
                @unlink($tmp);
                throw new RuntimeException('Unable to write live host configuration replacement.');
            }
            @chmod($tmp, (int)$replacement['mode']);
            if (!@rename($tmp, $path)) {
                @unlink($tmp);
                throw new RuntimeException('Unable to atomically replace live host configuration.');
            }
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
            $dir = dirname($path);
            if (!is_dir($dir)) {
                @mkdir($dir, 0775, true);
            }
            $tmp = @tempnam($dir, '.lds-host-rollback-');
            if (!is_string($tmp) || $tmp === '') {
                continue;
            }
            if (@file_put_contents($tmp, (string)$backup['content'], LOCK_EX) === false) {
                @unlink($tmp);
                continue;
            }
            @chmod($tmp, (int)$backup['mode']);
            @rename($tmp, $path);
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
}
