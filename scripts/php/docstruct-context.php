#!/usr/bin/env php
<?php
declare(strict_types=1);

const DOCSTRUCT_CONTEXT_SCHEMA = 'docker-tools.docstruct-context/v1';
const DOCSTRUCT_CONTEXT_BASE_SCHEMA = 'docker-tools.docstruct/v1';
const DOCSTRUCT_CONTEXT_DEFAULT_FILE_BYTES = 16384;
const DOCSTRUCT_CONTEXT_DEFAULT_TOTAL_BYTES = 262144;

/** @return never */
function contextFail(string $message, int $code = 64): never
{
    fwrite(STDERR, "docstruct context: {$message}\n");
    exit($code);
}

function contextLimit(string $name, int $default): int
{
    $raw = getenv($name);
    if ($raw === false || $raw === '') {
        return $default;
    }
    if (!preg_match('/^\d+$/', $raw) || (int)$raw < 1) {
        contextFail("{$name} must be a positive integer");
    }

    return (int)$raw;
}

/** @return array{raw:string,data:array<string,mixed>} */
function contextReadSidecar(string $path): array
{
    if (!is_file($path) || !is_readable($path)) {
        contextFail("sidecar is not readable: {$path}", 66);
    }
    $raw = file_get_contents($path);
    if (!is_string($raw)) {
        contextFail("unable to read sidecar: {$path}", 66);
    }

    try {
        $data = json_decode($raw, true, 512, JSON_THROW_ON_ERROR);
    } catch (JsonException $exception) {
        contextFail('sidecar is invalid JSON: ' . $exception->getMessage(), 65);
    }

    if (!is_array($data) || ($data['schema'] ?? null) !== DOCSTRUCT_CONTEXT_BASE_SCHEMA) {
        contextFail('sidecar is not docker-tools.docstruct/v1', 65);
    }

    return ['raw' => $raw, 'data' => $data];
}

function contextUnderRoot(string $root, string $relative): ?string
{
    if (
        $relative === ''
        || str_contains(str_replace('\\', '/', $relative), "../")
        || str_starts_with(str_replace('\\', '/', $relative), '/')
        || preg_match('/^[A-Za-z]:[\\\/]/', $relative) === 1
    ) {
        return null;
    }

    $candidate = $root . DIRECTORY_SEPARATOR . str_replace('/', DIRECTORY_SEPARATOR, $relative);
    if (is_link($candidate)) {
        return null;
    }
    $real = realpath($candidate);
    if ($real === false || !is_file($real)) {
        return null;
    }

    $rootNormalized = rtrim(str_replace('\\', '/', $root), '/');
    $realNormalized = str_replace('\\', '/', $real);
    if (!str_starts_with($realNormalized, $rootNormalized . '/')) {
        return null;
    }

    return $real;
}

function contextTruncate(string $contents, int $limit): array
{
    if (strlen($contents) <= $limit) {
        return [$contents, false];
    }

    if (function_exists('mb_strcut')) {
        return [mb_strcut($contents, 0, $limit, 'UTF-8'), true];
    }

    $slice = substr($contents, 0, $limit);
    while ($slice !== '' && preg_match('//u', $slice) !== 1) {
        $slice = substr($slice, 0, -1);
    }

    return [$slice, true];
}

/** @return array{input:string,pretty:bool} */
function contextArgs(array $argv): array
{
    $input = '';
    $pretty = true;

    for ($i = 1; $i < count($argv); $i++) {
        $arg = $argv[$i];
        if ($arg === '-h' || $arg === '--help') {
            echo "Usage: docstruct context <docstruct.json> [--compact]\n";
            echo "Build bounded Markdown/RST review passages without exposing config scalar values.\n";
            echo "Limits: DOCSTRUCT_REVIEW_ROOT, DOCSTRUCT_REVIEW_FILE_BYTES, DOCSTRUCT_REVIEW_TOTAL_BYTES.\n";
            exit(0);
        }
        if ($arg === '--compact') {
            $pretty = false;
            continue;
        }
        if (str_starts_with($arg, '-')) {
            contextFail("unknown option: {$arg}");
        }
        if ($input !== '') {
            contextFail('only one docstruct input file may be supplied');
        }
        $input = $arg;
    }

    if ($input === '') {
        contextFail('a docstruct JSON input is required');
    }

    return ['input' => $input, 'pretty' => $pretty];
}

$options = contextArgs($argv);
$sidecar = contextReadSidecar($options['input']);
$doc = $sidecar['data'];
$root = realpath((string)($doc['root'] ?? ''));
if ($root === false || !is_dir($root)) {
    contextFail('sidecar root is unavailable; regenerate docstruct from the mounted workspace', 65);
}

$allowedRootInput = getenv('DOCSTRUCT_REVIEW_ROOT');
if ($allowedRootInput === false || trim($allowedRootInput) === '') {
    $allowedRootInput = getcwd() ?: '';
}
$allowedRoot = realpath($allowedRootInput);
if ($allowedRoot === false || !is_dir($allowedRoot)) {
    contextFail('DOCSTRUCT_REVIEW_ROOT/current workspace is unavailable', 65);
}
$rootNormalized = rtrim(str_replace('\\', '/', $root), '/');
$allowedNormalized = rtrim(str_replace('\\', '/', $allowedRoot), '/');
if ($rootNormalized !== $allowedNormalized && !str_starts_with($rootNormalized, $allowedNormalized . '/')) {
    contextFail('sidecar root is outside the allowed review workspace', 77);
}

$fileLimit = contextLimit('DOCSTRUCT_REVIEW_FILE_BYTES', DOCSTRUCT_CONTEXT_DEFAULT_FILE_BYTES);
$totalLimit = contextLimit('DOCSTRUCT_REVIEW_TOTAL_BYTES', DOCSTRUCT_CONTEXT_DEFAULT_TOTAL_BYTES);
$totalBytes = 0;
$passages = [];

foreach (($doc['files'] ?? []) as $file) {
    if (!is_array($file) || ($file['status'] ?? null) !== 'ok') {
        continue;
    }
    $format = (string)($file['format'] ?? '');
    if (!in_array($format, ['markdown', 'rst'], true)) {
        continue;
    }

    $relative = (string)($file['path'] ?? '');
    $absolute = contextUnderRoot($root, $relative);
    if ($absolute === null) {
        contextFail("source is unavailable or outside the sidecar root: {$relative}", 65);
    }
    $contents = file_get_contents($absolute);
    if (!is_string($contents)) {
        contextFail("unable to read source: {$relative}", 66);
    }

    $expectedHash = (string)($file['sha256'] ?? '');
    if ($expectedHash === '' || !hash_equals($expectedHash, hash('sha256', $contents))) {
        contextFail("source changed since extraction: {$relative}; regenerate docstruct", 65);
    }

    $remaining = $totalLimit - $totalBytes;
    if ($remaining <= 0) {
        break;
    }
    $limit = min($fileLimit, $remaining);
    [$excerpt, $truncated] = contextTruncate($contents, $limit);
    $bytes = strlen($excerpt);
    $totalBytes += $bytes;

    $passages[] = [
        'source_file' => $relative,
        'format' => $format,
        'content' => $excerpt,
        'bytes' => $bytes,
        'truncated' => $truncated || strlen($contents) > $bytes,
    ];
}

$result = [
    'schema' => DOCSTRUCT_CONTEXT_SCHEMA,
    'base_schema' => DOCSTRUCT_CONTEXT_BASE_SCHEMA,
    'base_sha256' => hash('sha256', rtrim($sidecar['raw'], "\n")),
    'structure' => $doc,
    'passages' => $passages,
    'stats' => [
        'passage_files' => count($passages),
        'passage_bytes' => $totalBytes,
        'file_limit_bytes' => $fileLimit,
        'total_limit_bytes' => $totalLimit,
    ],
];

$flags = JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE;
if ($options['pretty']) {
    $flags |= JSON_PRETTY_PRINT;
}
echo json_encode($result, $flags | JSON_THROW_ON_ERROR) . "\n";
