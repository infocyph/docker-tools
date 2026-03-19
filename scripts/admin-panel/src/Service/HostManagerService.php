<?php
declare(strict_types=1);

namespace AdminPanel\Service;

use AdminPanel\Support\ProcessRunner;

final class HostManagerService
{
    private const HOST_CREATE_TIMEOUT_SECONDS = 240;
    private const HOST_DELETE_TIMEOUT_SECONDS = 120;
    private const DEFAULT_NGINX_VHOST_DIR = '/etc/share/vhosts/nginx';
    private const DEFAULT_APACHE_VHOST_DIR = '/etc/share/vhosts/apache';
    private const DEFAULT_RUNTIME_VERSIONS_DB = '/etc/share/runtime-versions.json';
    private const DEFAULT_APP_SCAN_DIR = '/app';
    private const DEFAULT_MAX_VERSIONS = 16;
    private const MIN_PHP_VERSION = '5.5';

    /** @return array<string,mixed> */
    public function listHosts(): array
    {
        $nginxDir = $this->nginxVhostDir();
        $apacheDir = $this->apacheVhostDir();
        $items = [];
        if (is_dir($nginxDir)) {
            $files = glob(rtrim($nginxDir, '/\\') . DIRECTORY_SEPARATOR . '*.conf');
            if (is_array($files)) {
                foreach ($files as $filePath) {
                    if (!is_string($filePath) || !is_file($filePath)) {
                        continue;
                    }
                    $domain = basename($filePath, '.conf');
                    if (!$this->isValidDomain($domain)) {
                        continue;
                    }
                    $meta = $this->extractMetadata($filePath);
                    $appType = $this->resolveAppType($meta);
                    $serverType = strtolower(trim((string)($meta['server'] ?? 'nginx')));
                    if ($serverType !== 'apache' && $serverType !== 'nginx') {
                        $serverType = is_file(rtrim($apacheDir, '/\\') . DIRECTORY_SEPARATOR . $domain . '.conf') ? 'apache' : 'nginx';
                    }
                    $protocol = $this->detectProtocol($filePath);
                    $phpVersion = trim((string)($meta['php_version'] ?? ''));
                    $nodeVersion = trim((string)($meta['node_version'] ?? ''));
                    $proxyHost = trim((string)($meta['proxy_host'] ?? ''));
                    $proxyIp = trim((string)($meta['proxy_ip'] ?? ''));
                    $runtime = '-';
                    if ($appType === 'php' && $phpVersion !== '') {
                        $runtime = 'PHP ' . $phpVersion;
                    } elseif ($appType === 'node' && $nodeVersion !== '') {
                        $runtime = 'Node ' . $nodeVersion;
                    } elseif ($appType === 'proxyip' && $proxyHost !== '') {
                        $runtime = $proxyHost . ($proxyIp !== '' ? (' @ ' . $proxyIp) : '');
                    }
                    $generatedAt = trim((string)($meta['generated_at'] ?? ''));
                    $mtime = @filemtime($filePath);
                    $updatedAt = $generatedAt !== '' ? $generatedAt : ($mtime !== false ? gmdate('Y-m-d\TH:i:s\Z', (int)$mtime) : gmdate('Y-m-d\TH:i:s\Z'));
                    $items[] = [
                        'domain' => $domain,
                        'app_type' => $appType,
                        'server_type' => $serverType,
                        'protocol' => $protocol,
                        'doc_root' => trim((string)($meta['docroot'] ?? '/app')),
                        'runtime' => $runtime,
                        'php_version' => $phpVersion,
                        'node_version' => $nodeVersion,
                        'proxy_host' => $proxyHost,
                        'proxy_ip' => $proxyIp,
                        'proxy_http_port' => trim((string)($meta['proxy_http_port'] ?? '80')),
                        'proxy_https_port' => trim((string)($meta['proxy_https_port'] ?? '443')),
                        'updated_at' => $updatedAt,
                        'meta' => $meta,
                    ];
                }
            }
        }
        usort($items, static fn(array $a, array $b): int => strcmp((string)($a['domain'] ?? ''), (string)($b['domain'] ?? '')));
        $summary = ['hosts' => count($items), 'php' => 0, 'node' => 0, 'proxyip' => 0, 'unknown' => 0];
        foreach ($items as $item) {
            $key = (string)($item['app_type'] ?? 'unknown');
            if (!array_key_exists($key, $summary)) {
                $key = 'unknown';
            }
            $summary[$key] = (int)$summary[$key] + 1;
        }
        return ['ok' => true, 'generated_at' => gmdate('Y-m-d\TH:i:s\Z'), 'summary' => $summary, 'items' => $items];
    }

    /** @return array<string,mixed> */
    public function formOptions(): array
    {
        $runtime = $this->loadRuntimeVersionsData();
        return [
            'php_runtime' => $this->buildPhpRuntimeOptions($runtime),
            'node_runtime' => $this->buildNodeRuntimeOptions($runtime),
            'doc_root' => $this->buildDocRootOptions(),
            'meta' => [
                'runtime_versions_db' => $this->runtimeVersionsDbPath(),
                'app_scan_dir' => $this->appScanDir(),
                'max_versions' => $this->maxVersions(),
            ],
        ];
    }

    /** @param array<string,mixed> $payload @return array<string,mixed> */
    public function addHost(array $payload): array
    {
        $built = $this->buildMkhostAnswers($payload);
        if (!(bool)($built['ok'] ?? false)) {
            return $built;
        }
        $res = $this->runCommand(['mkhost'], self::HOST_CREATE_TIMEOUT_SECONDS, (string)$built['stdin']);
        if (!$res['ok']) {
            return ['ok' => false, 'error' => 'host_add_failed', 'message' => $res['stderr'] !== '' ? $res['stderr'] : 'mkhost failed', 'exit_code' => $res['exit_code']];
        }
        $list = $this->listHosts();
        return [
            'ok' => true,
            'message' => 'Host added. Run `lds reboot` to apply changes.',
            'reboot_required' => true,
            'reboot_command' => 'lds reboot',
            'domain' => $built['domain'],
            'host' => $this->findHost($list, (string)$built['domain']),
            'summary' => $list['summary'] ?? [],
        ];
    }

    /** @param array<string,mixed> $payload @return array<string,mixed> */
    public function editHost(array $payload): array
    {
        $original = strtolower(trim((string)($payload['original_domain'] ?? '')));
        if (!$this->isValidDomain($original)) {
            return ['ok' => false, 'error' => 'validation_original_domain', 'message' => 'A valid original_domain is required for edit.'];
        }
        $rm = $this->runCommand(['rmhost', $original], self::HOST_DELETE_TIMEOUT_SECONDS, "y\n");
        if (!$rm['ok'] && $rm['exit_code'] !== 2) {
            return ['ok' => false, 'error' => 'host_edit_delete_failed', 'message' => $rm['stderr'] !== '' ? $rm['stderr'] : 'rmhost failed before update', 'exit_code' => $rm['exit_code']];
        }
        $addPayload = $payload;
        unset($addPayload['original_domain']);
        $added = $this->addHost($addPayload);
        if (!(bool)($added['ok'] ?? false)) {
            $added['error'] = 'host_edit_add_failed';
            return $added;
        }
        $added['message'] = 'Host updated. Run `lds reboot` to apply changes.';
        $added['reboot_required'] = true;
        $added['reboot_command'] = 'lds reboot';
        return $added;
    }

    /** @return array<string,mixed> */
    public function deleteHost(string $domain): array
    {
        $domain = strtolower(trim($domain));
        if (!$this->isValidDomain($domain)) {
            return ['ok' => false, 'error' => 'validation_domain', 'message' => 'A valid domain is required.'];
        }
        $res = $this->runCommand(['rmhost', $domain], self::HOST_DELETE_TIMEOUT_SECONDS, "y\n");
        if (!$res['ok']) {
            return ['ok' => false, 'error' => 'host_delete_failed', 'message' => $res['stderr'] !== '' ? $res['stderr'] : 'rmhost failed', 'exit_code' => $res['exit_code']];
        }
        $list = $this->listHosts();
        return ['ok' => true, 'message' => 'Host deleted.', 'domain' => $domain, 'summary' => $list['summary'] ?? []];
    }

    /** @param array<string,mixed> $payload @return array<string,mixed> */
    private function buildMkhostAnswers(array $payload): array
    {
        $domain = strtolower(trim((string)($payload['domain'] ?? '')));
        if (!$this->isValidDomain($domain)) {
            return ['ok' => false, 'error' => 'validation_domain', 'message' => 'Invalid domain format.'];
        }
        $appType = strtolower(trim((string)($payload['app_type'] ?? 'php')));
        if (!in_array($appType, ['php', 'node', 'proxyip'], true)) {
            $appType = 'php';
        }
        $protocol = strtolower(trim((string)($payload['protocol'] ?? 'both')));
        if (!in_array($protocol, ['http', 'https', 'both'], true)) {
            $protocol = 'both';
        }
        $redirectHttps = $this->toBool($payload['redirect_https'] ?? true);
        $bodySizeMb = max(1, min(4096, (int)($payload['body_size_mb'] ?? 10)));
        $streaming = $this->toBool($payload['streaming'] ?? false);
        $mtls = $this->toBool($payload['mtls'] ?? false);
        $opts = $this->formOptions();
        $answers = [];

        if ($appType === 'php') {
            $rt = $this->resolvePhpRuntimeSelection($payload, $opts['php_runtime'] ?? []);
            if (!(bool)($rt['ok'] ?? false)) return $rt;
            $dr = $this->resolveDocRootSelection($payload, $opts['doc_root'] ?? []);
            if (!(bool)($dr['ok'] ?? false)) return $dr;
            $serverType = strtolower(trim((string)($payload['server_type'] ?? 'nginx')));
            if ($serverType !== 'apache' && $serverType !== 'nginx') $serverType = 'nginx';
            $answers[] = '1';
            $answers[] = $domain;
            foreach (($rt['answers'] ?? []) as $part) $answers[] = (string)$part;
            $answers[] = $serverType === 'apache' ? '2' : '1';
            $answers[] = $this->protocolPromptValue($protocol);
            if ($protocol === 'both') $answers[] = $redirectHttps ? 'y' : 'n';
            foreach (($dr['answers'] ?? []) as $part) $answers[] = (string)$part;
            $answers[] = 'n';
            $answers[] = (string)$bodySizeMb;
            $answers[] = $streaming ? 'y' : 'n';
            if ($protocol !== 'http') $answers[] = $mtls ? 'y' : 'n';
            $answers[] = 'y';
        } elseif ($appType === 'node') {
            $rt = $this->resolveNodeRuntimeSelection($payload, $opts['node_runtime'] ?? []);
            if (!(bool)($rt['ok'] ?? false)) return $rt;
            $dr = $this->resolveDocRootSelection($payload, $opts['doc_root'] ?? []);
            if (!(bool)($dr['ok'] ?? false)) return $dr;
            $nodeCommand = trim((string)($payload['node_command'] ?? ''));
            $answers[] = '2';
            $answers[] = $domain;
            foreach (($rt['answers'] ?? []) as $part) $answers[] = (string)$part;
            if ($nodeCommand !== '') { $answers[] = 'y'; $answers[] = str_replace(["\r", "\n"], ' ', $nodeCommand); } else { $answers[] = 'n'; }
            $answers[] = $this->protocolPromptValue($protocol);
            if ($protocol === 'both') $answers[] = $redirectHttps ? 'y' : 'n';
            foreach (($dr['answers'] ?? []) as $part) $answers[] = (string)$part;
            $answers[] = (string)$bodySizeMb;
            $answers[] = $streaming ? 'y' : 'n';
            if ($protocol !== 'http') $answers[] = $mtls ? 'y' : 'n';
            $answers[] = 'y';
        } else {
            $proxyHost = trim((string)($payload['proxy_host'] ?? ''));
            $proxyIp = trim((string)($payload['proxy_ip'] ?? ''));
            if (!$this->isValidProxyHost($proxyHost)) return ['ok' => false, 'error' => 'validation_proxy_host', 'message' => 'proxy_host must contain at least one dot and include only letters, numbers, dot, underscore, or hyphen.'];
            if (!$this->isValidIpAddress($proxyIp)) return ['ok' => false, 'error' => 'validation_proxy_ip', 'message' => 'proxy_ip must be a valid IPv4 or IPv6 address.'];
            $proxyHttpPort = (int)($payload['proxy_http_port'] ?? 80); if ($proxyHttpPort < 1 || $proxyHttpPort > 65535) $proxyHttpPort = 80;
            $proxyHttpsPort = (int)($payload['proxy_https_port'] ?? 443); if ($proxyHttpsPort < 1 || $proxyHttpsPort > 65535) $proxyHttpsPort = 443;
            $proxyWebsocket = $this->toBool($payload['proxy_websocket'] ?? false);
            $proxyRewrite = $this->toBool($payload['proxy_rewrite'] ?? true);
            $proxySubfilter = $this->toBool($payload['proxy_subfilter'] ?? false);
            $proxyCsp = $this->toBool($payload['proxy_csp'] ?? false);
            $parentCookieDomain = trim((string)($payload['parent_cookie_domain'] ?? ''));
            $answers[] = '3'; $answers[] = $domain; $answers[] = $proxyHost; $answers[] = $proxyIp;
            $answers[] = $this->protocolPromptValue($protocol);
            if ($protocol === 'both') $answers[] = $redirectHttps ? 'y' : 'n';
            if ($protocol === 'http') $answers[] = (string)$proxyHttpPort;
            elseif ($protocol === 'https' || ($protocol === 'both' && $redirectHttps)) $answers[] = (string)$proxyHttpsPort;
            else $answers[] = $proxyHttpPort . ',' . $proxyHttpsPort;
            $answers[] = (string)$bodySizeMb;
            $answers[] = $streaming ? 'y' : 'n';
            $answers[] = $proxyWebsocket ? 'y' : 'n';
            $answers[] = $proxyRewrite ? 'y' : 'n';
            if ($proxyRewrite) $answers[] = $parentCookieDomain;
            $answers[] = $proxySubfilter ? 'y' : 'n';
            $answers[] = $proxyCsp ? 'y' : 'n';
            if ($protocol !== 'http') $answers[] = $mtls ? 'y' : 'n';
            $answers[] = 'y';
        }
        return ['ok' => true, 'domain' => $domain, 'stdin' => implode("\n", $answers) . "\n"];
    }

    /** @param array<string,mixed> $payload @param array<int,array<string,mixed>> $options @return array<string,mixed> */
    private function resolvePhpRuntimeSelection(array $payload, array $options): array
    {
        $index = $this->normalizeSelectionIndex($payload['php_runtime_index'] ?? null);
        $custom = trim((string)($payload['php_version_custom'] ?? $payload['php_version'] ?? ''));
        if ($index === null && $custom !== '') {
            foreach ($options as $opt) if (is_array($opt) && (string)($opt['kind'] ?? '') !== 'custom' && (string)($opt['value'] ?? '') === $custom) $index = (int)($opt['index'] ?? 0);
            if ($index === null) $index = 0;
        }
        if ($index === null) return ['ok' => true, 'answers' => ['']];
        $selected = $this->findOptionByIndex($options, $index);
        if ($selected === null) return ['ok' => false, 'error' => 'validation_php_runtime', 'message' => 'Invalid PHP runtime selection.'];
        if ((string)($selected['kind'] ?? '') === 'custom') {
            if (!$this->isValidCustomPhpVersion($custom)) return ['ok' => false, 'error' => 'validation_php_version', 'message' => 'Custom PHP version must be >= 5.5 and present in runtime-versions.json (e.g. 8.4).'];
            return ['ok' => true, 'answers' => ['0', $custom]];
        }
        $selectedVersion = trim((string)($selected['value'] ?? ''));
        if (!$this->isPhpVersionAtLeastMin($selectedVersion)) {
            return ['ok' => false, 'error' => 'validation_php_version', 'message' => 'Selected PHP version is below the minimum supported version (5.5).'];
        }
        return ['ok' => true, 'answers' => [(string)$index]];
    }

    /** @param array<string,mixed> $payload @param array<int,array<string,mixed>> $options @return array<string,mixed> */
    private function resolveNodeRuntimeSelection(array $payload, array $options): array
    {
        $index = $this->normalizeSelectionIndex($payload['node_runtime_index'] ?? null);
        $custom = trim((string)($payload['node_version_custom'] ?? $payload['node_version'] ?? ''));
        if ($index === null && $custom !== '') {
            foreach ($options as $opt) if (is_array($opt) && (string)($opt['kind'] ?? '') !== 'custom' && (string)($opt['value'] ?? '') === $custom) $index = (int)($opt['index'] ?? 0);
            if ($index === null) $index = 0;
        }
        if ($index === null) return ['ok' => true, 'answers' => ['']];
        $selected = $this->findOptionByIndex($options, $index);
        if ($selected === null) return ['ok' => false, 'error' => 'validation_node_runtime', 'message' => 'Invalid Node runtime selection.'];
        if ((string)($selected['kind'] ?? '') === 'custom') {
            if (!$this->isValidCustomNodeVersion($custom)) return ['ok' => false, 'error' => 'validation_node_version', 'message' => 'Custom Node major must be in runtime-versions.json (e.g. 24).'];
            return ['ok' => true, 'answers' => ['0', $custom]];
        }
        return ['ok' => true, 'answers' => [(string)$index]];
    }

    /** @param array<string,mixed> $payload @param array<int,array<string,mixed>> $options @return array<string,mixed> */
    private function resolveDocRootSelection(array $payload, array $options): array
    {
        $index = $this->normalizeSelectionIndex($payload['doc_root_index'] ?? null);
        $custom = $this->normalizeRelPath((string)($payload['doc_root_custom'] ?? $payload['doc_root'] ?? '/app'));
        if ($index === null && $custom !== '') {
            foreach ($options as $opt) if (is_array($opt) && (string)($opt['kind'] ?? '') !== 'custom' && (string)($opt['value'] ?? '') === $custom) $index = (int)($opt['index'] ?? 0);
            if ($index === null) $index = 0;
        }
        if ($index === null) $index = 0;
        $selected = $this->findOptionByIndex($options, $index);
        if ($selected === null) return ['ok' => false, 'error' => 'validation_doc_root', 'message' => 'Invalid doc-root selection.'];
        if ((string)($selected['kind'] ?? '') === 'custom') return ['ok' => true, 'answers' => ['0', $custom]];
        return ['ok' => true, 'answers' => [(string)$index]];
    }

    /** @param mixed $value */
    private function normalizeSelectionIndex(mixed $value): ?int
    {
        if (is_int($value)) return $value;
        $raw = trim((string)$value);
        if ($raw === '' || !preg_match('/^[0-9]+$/', $raw)) return null;
        return (int)$raw;
    }

    /** @param array<int,array<string,mixed>> $options @return array<string,mixed>|null */
    private function findOptionByIndex(array $options, int $index): ?array
    {
        foreach ($options as $opt) if (is_array($opt) && (int)($opt['index'] ?? -1) === $index) return $opt;
        return null;
    }

    /** @param array<string,mixed>|null $runtime @return array<int,array<string,mixed>> */
    private function buildPhpRuntimeOptions(?array $runtime): array
    {
        $max = $this->maxVersions();
        $options = [['index' => 0, 'kind' => 'custom', 'value' => '', 'group' => 'custom', 'label' => 'Custom Version (>= 5.5)']];
        $i = 0;
        $active = $runtime['php']['active'] ?? [];
        if (is_array($active)) {
            foreach ($active as $row) {
                if (!is_array($row) || $i >= $max) continue;
                $version = trim((string)($row['version'] ?? ''));
                if ($version === '') continue;
                if (!$this->isPhpVersionAtLeastMin($version)) continue;
                ++$i;
                $options[] = ['index' => $i, 'kind' => 'php', 'value' => $version, 'group' => 'active', 'label' => $version . ' ' . $this->fmtRange((string)($row['debut'] ?? 'unknown'), (string)($row['eol'] ?? 'unknown'))];
            }
        }
        $deprecated = $runtime['php']['deprecated'] ?? [];
        if (is_array($deprecated)) {
            foreach ($deprecated as $row) {
                if (!is_array($row) || $i >= $max) continue;
                $version = trim((string)($row['version'] ?? ''));
                if ($version === '') continue;
                if (!$this->isPhpVersionAtLeastMin($version)) continue;
                ++$i;
                $options[] = ['index' => $i, 'kind' => 'php', 'value' => $version, 'group' => 'deprecated', 'label' => $version . ' ' . $this->fmtEolTilde((string)($row['eol'] ?? 'unknown'))];
            }
        }
        return $options;
    }

    /** @param array<string,mixed>|null $runtime @return array<int,array<string,mixed>> */
    private function buildNodeRuntimeOptions(?array $runtime): array
    {
        $max = $this->maxVersions();
        $current = trim((string)($runtime['node']['tags']['current'] ?? ''));
        $lts = trim((string)($runtime['node']['tags']['lts'] ?? ''));
        $options = [
            ['index' => 0, 'kind' => 'custom', 'value' => '', 'group' => 'custom', 'label' => 'Custom Version'],
            ['index' => 1, 'kind' => 'tag', 'value' => 'current', 'group' => 'tag', 'label' => 'CURRENT' . ($current !== '' ? (' (v' . $current . ')') : '')],
            ['index' => 2, 'kind' => 'tag', 'value' => 'lts', 'group' => 'tag', 'label' => 'LTS' . ($lts !== '' ? (' (v' . $lts . ')') : '')],
        ];
        $i = 2;
        $slotsLeft = $max - 3;
        $active = $runtime['node']['active'] ?? [];
        if (is_array($active)) {
            foreach ($active as $row) {
                if (!is_array($row) || $slotsLeft <= 0) continue;
                $version = trim((string)($row['version'] ?? ''));
                if ($version === '') continue;
                ++$i; --$slotsLeft;
                $label = 'v' . $version . ' ' . $this->fmtRange((string)($row['debut'] ?? 'unknown'), (string)($row['eol'] ?? 'unknown'));
                if ($this->toBool($row['lts'] ?? false)) $label .= ' LTS';
                $options[] = ['index' => $i, 'kind' => 'node', 'value' => $version, 'group' => 'active', 'label' => $label];
            }
        }
        $deprecated = $runtime['node']['deprecated'] ?? [];
        if (is_array($deprecated)) {
            foreach ($deprecated as $row) {
                if (!is_array($row) || $slotsLeft <= 0) continue;
                $version = trim((string)($row['version'] ?? ''));
                if ($version === '') continue;
                ++$i; --$slotsLeft;
                $options[] = ['index' => $i, 'kind' => 'node', 'value' => $version, 'group' => 'deprecated', 'label' => 'v' . $version . ' ' . $this->fmtEolTilde((string)($row['eol'] ?? 'unknown'))];
            }
        }
        return $options;
    }

    /** @return array<int,array<string,mixed>> */
    private function buildDocRootOptions(): array
    {
        $base = $this->appScanDir();
        $paths = [];
        if (is_dir($base . DIRECTORY_SEPARATOR . 'public')) $paths[] = '/public';
        if (is_dir($base)) {
            $entries = @scandir($base);
            if (is_array($entries)) {
                foreach ($entries as $name) {
                    $name = trim((string)$name);
                    if ($name === '' || $name === '.' || $name === '..' || str_starts_with($name, '.')) continue;
                    $full = $base . DIRECTORY_SEPARATOR . $name;
                    if (!is_dir($full)) continue;
                    $paths[] = '/' . $name;
                    if (is_dir($full . DIRECTORY_SEPARATOR . 'public')) $paths[] = '/' . $name . '/public';
                }
            }
        }
        $uniq = []; $seen = [];
        foreach ($paths as $p) if (!isset($seen[$p])) { $seen[$p] = true; $uniq[] = $p; }
        usort($uniq, static function (string $a, string $b): int {
            $ga = str_ends_with($a, '/public') ? substr($a, 0, -7) : $a;
            $gb = str_ends_with($b, '/public') ? substr($b, 0, -7) : $b;
            $c = strcasecmp($ga, $gb); if ($c !== 0) return $c;
            $da = substr_count($a, '/'); $db = substr_count($b, '/'); if ($da !== $db) return $da <=> $db;
            return strcasecmp($a, $b);
        });
        $opts = [['index' => 0, 'kind' => 'custom', 'value' => '', 'label' => '<Custom Path>']];
        $i = 0;
        foreach ($uniq as $p) { ++$i; $opts[] = ['index' => $i, 'kind' => 'path', 'value' => $p, 'label' => $p]; }
        return $opts;
    }

    private function isValidCustomPhpVersion(string $version): bool
    {
        if (!preg_match('/^[0-9]+\.[0-9]+$/', $version)) return false;
        if (!$this->isPhpVersionAtLeastMin($version)) return false;
        $runtime = $this->loadRuntimeVersionsData();
        $all = $runtime['php']['all'] ?? [];
        if (!is_array($all) || $all === []) return false;
        foreach ($all as $row) {
            if (!is_array($row)) continue;
            $candidate = trim((string)($row['version'] ?? ''));
            if ($candidate === $version && $this->isPhpVersionAtLeastMin($candidate)) return true;
        }
        return false;
    }

    private function isValidCustomNodeVersion(string $version): bool
    {
        if (!preg_match('/^[0-9]+$/', $version)) return false;
        $runtime = $this->loadRuntimeVersionsData();
        $all = $runtime['node']['all'] ?? [];
        if (!is_array($all) || $all === []) return false;
        foreach ($all as $row) if (is_array($row) && (string)($row['version'] ?? '') === $version) return true;
        return false;
    }

    private function isPhpVersionAtLeastMin(string $version): bool
    {
        $version = trim($version);
        if (!preg_match('/^([0-9]+)\.([0-9]+)$/', $version, $m)) {
            return false;
        }
        $major = (int)$m[1];
        $minor = (int)$m[2];
        [$minMajor, $minMinor] = $this->phpMinVersionParts();
        if ($major > $minMajor) {
            return true;
        }
        if ($major < $minMajor) {
            return false;
        }
        return $minor >= $minMinor;
    }

    /** @return array{0:int,1:int} */
    private function phpMinVersionParts(): array
    {
        if (preg_match('/^([0-9]+)\.([0-9]+)$/', self::MIN_PHP_VERSION, $m)) {
            return [(int)$m[1], (int)$m[2]];
        }
        return [5, 5];
    }

    private function maxVersions(): int
    {
        $raw = trim((string)getenv('MAX_VERSIONS'));
        if ($raw === '' || !preg_match('/^[0-9]+$/', $raw)) return self::DEFAULT_MAX_VERSIONS;
        return max(1, min(200, (int)$raw));
    }

    private function runtimeVersionsDbPath(): string
    {
        $env = trim((string)getenv('RUNTIME_VERSIONS_DB'));
        return $env !== '' ? $env : self::DEFAULT_RUNTIME_VERSIONS_DB;
    }

    private function appScanDir(): string
    {
        $env = trim((string)getenv('APP_SCAN_DIR'));
        return $env !== '' ? $env : self::DEFAULT_APP_SCAN_DIR;
    }

    /** @return array<string,mixed>|null */
    private function loadRuntimeVersionsData(): ?array
    {
        $path = $this->runtimeVersionsDbPath();
        if (!is_file($path)) return null;
        $raw = @file_get_contents($path);
        if (!is_string($raw) || trim($raw) === '') return null;
        $decoded = json_decode($raw, true);
        return is_array($decoded) ? $decoded : null;
    }

    private function normalizeRelPath(string $path): string
    {
        $path = trim($path);
        if ($path === '') $path = '/app';
        if ($path[0] !== '/') $path = '/' . $path;
        while (str_contains($path, '//')) $path = str_replace('//', '/', $path);
        if ($path !== '/' && str_ends_with($path, '/')) $path = substr($path, 0, -1);
        return $path;
    }

    private function fmtRange(string $debut, string $eol): string
    {
        $debut = trim($debut); $eol = trim($eol);
        if ($debut === '' || strtolower($debut) === 'null') $debut = 'unknown';
        if ($eol === '' || strtolower($eol) === 'null') $eol = 'unknown';
        return '(' . $debut . ' to ' . $eol . ')';
    }

    private function fmtEolTilde(string $eol): string
    {
        $eol = trim($eol);
        if ($eol === '' || strtolower($eol) === 'null') $eol = 'unknown';
        return '(~' . $eol . ')';
    }

    /** @param array<string,mixed> $list @return array<string,mixed>|null */
    private function findHost(array $list, string $domain): ?array
    {
        $items = $list['items'] ?? [];
        if (!is_array($items)) return null;
        foreach ($items as $item) if (is_array($item) && strtolower((string)($item['domain'] ?? '')) === strtolower($domain)) return $item;
        return null;
    }

    private function protocolPromptValue(string $protocol): string
    {
        if ($protocol === 'http') return '1';
        if ($protocol === 'https') return '2';
        return '3';
    }

    private function resolveAppType(array $meta): string
    {
        $app = strtolower(trim((string)($meta['app'] ?? '')));
        if (in_array($app, ['php', 'node', 'proxyip'], true)) return $app;
        if (isset($meta['php_version'])) return 'php';
        if (isset($meta['node_version'])) return 'node';
        if (isset($meta['proxy_host']) || isset($meta['proxy_ip'])) return 'proxyip';
        return 'unknown';
    }

    /** @return array<string,string> */
    private function extractMetadata(string $filePath): array
    {
        $meta = [];
        $lines = @file($filePath, FILE_IGNORE_NEW_LINES);
        if (!is_array($lines)) return $meta;
        foreach ($lines as $line) {
            $line = trim((string)$line);
            if ($line === '') continue;
            if (!str_starts_with($line, '# LDS-META:')) { if (!str_starts_with($line, '#')) break; continue; }
            $raw = trim(substr($line, strlen('# LDS-META:')));
            if ($raw === '' || !str_contains($raw, '=')) continue;
            [$key, $value] = explode('=', $raw, 2);
            $key = trim($key);
            if ($key === '') continue;
            $meta[$key] = trim($value);
        }
        return $meta;
    }

    private function detectProtocol(string $filePath): string
    {
        $content = @file_get_contents($filePath);
        if (!is_string($content) || $content === '') return 'unknown';
        $has443 = preg_match('/\blisten\s+(\[::\]:)?443\b/i', $content) === 1;
        $has80 = preg_match('/\blisten\s+(\[::\]:)?80\b/i', $content) === 1;
        if ($has80 && $has443) return 'both';
        if ($has443) return 'https';
        if ($has80) return 'http';
        return 'unknown';
    }

    private function toBool(mixed $value): bool
    {
        if (is_bool($value)) return $value;
        if (is_int($value)) return $value !== 0;
        return in_array(strtolower(trim((string)$value)), ['1', 'true', 'yes', 'y', 'on'], true);
    }

    private function isValidIpAddress(string $value): bool
    {
        $value = trim($value);
        if ($value === '') {
            return false;
        }

        if (preg_match('/^([0-9]{1,3}\.){3}[0-9]{1,3}$/', $value) === 1) {
            $parts = explode('.', $value);
            if (count($parts) !== 4) {
                return false;
            }
            foreach ($parts as $part) {
                if (!preg_match('/^[0-9]+$/', $part)) {
                    return false;
                }
                $n = (int)$part;
                if ($n < 0 || $n > 255) {
                    return false;
                }
            }
            return true;
        }

        return preg_match('/^[0-9a-fA-F:]+$/', $value) === 1 && str_contains($value, ':');
    }

    private function isValidProxyHost(string $value): bool
    {
        $value = trim($value);
        if ($value === '') {
            return false;
        }
        if (preg_match('/^[A-Za-z0-9._-]+$/', $value) !== 1) {
            return false;
        }
        return str_contains($value, '.');
    }

    private function isValidDomain(string $domain): bool
    {
        return preg_match('/^([a-zA-Z0-9]([-a-zA-Z0-9]{0,61}[a-zA-Z0-9])?\.)+(localhost|local|test|loc|[a-zA-Z]{2,})$/', $domain) === 1;
    }

    private function nginxVhostDir(): string
    {
        $env = trim((string)getenv('VHOST_NGINX_DIR'));
        return $env !== '' ? $env : self::DEFAULT_NGINX_VHOST_DIR;
    }

    private function apacheVhostDir(): string
    {
        $env = trim((string)getenv('VHOST_APACHE_DIR'));
        return $env !== '' ? $env : self::DEFAULT_APACHE_VHOST_DIR;
    }

    /** @param list<string> $command @return array{ok:bool,stdout:string,stderr:string,exit_code:int,timed_out?:bool} */
    private function runCommand(array $command, int $timeoutSeconds, ?string $stdin = null): array
    {
        return ProcessRunner::run($command, $timeoutSeconds, $stdin);
    }
}
