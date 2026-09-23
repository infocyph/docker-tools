#!/usr/bin/env php
<?php
declare(strict_types=1);

const DOCSTRUCT_SCHEMA = 'docker-tools.docstruct/v1';
const DOCSTRUCT_EXCLUDES = ['.git', '.hg', '.svn', 'vendor', 'node_modules', 'dist', 'build', 'coverage', 'graphify-out'];

function fail(string $message, int $code = 64): never {
    fwrite(STDERR, "docstruct: {$message}\n");
    exit($code);
}

function isList(array $value): bool {
    return array_is_list($value);
}

function relPath(string $path, string $root): string {
    $path = str_replace('\\', '/', $path);
    $root = rtrim(str_replace('\\', '/', $root), '/');
    if ($path === $root) {
        return basename($path);
    }
    if (str_starts_with($path, $root . '/')) {
        return substr($path, strlen($root) + 1);
    }
    return $path;
}

function slug(string $text): string {
    $text = trim(mb_strtolower($text));
    $text = preg_replace('/[^\pL\pN]+/u', '-', $text) ?? '';
    $text = trim($text, '-');
    return $text !== '' ? $text : 'section';
}

function inlineText(mixed $value): string {
    if (!is_array($value)) {
        return is_string($value) ? $value : '';
    }

    if (isset($value['t'])) {
        $type = $value['t'];
        $content = $value['c'] ?? null;
        if (in_array($type, ['Str', 'Code'], true)) {
            if ($type === 'Code' && is_array($content)) {
                return (string)($content[1] ?? '');
            }
            return is_string($content) ? $content : '';
        }
        if ($type === 'Space' || $type === 'SoftBreak' || $type === 'LineBreak') {
            return ' ';
        }
        if (is_array($content)) {
            return inlineText($content);
        }
        return '';
    }

    $parts = [];
    foreach ($value as $item) {
        $piece = inlineText($item);
        if ($piece !== '') {
            $parts[] = $piece;
        }
    }
    return trim(preg_replace('/\s+/u', ' ', implode('', $parts)) ?? '');
}

function walkAst(mixed $value, callable $callback): void {
    if (!is_array($value)) {
        return;
    }

    if (isset($value['t'])) {
        $callback($value);
    }

    foreach ($value as $child) {
        if (is_array($child)) {
            walkAst($child, $callback);
        }
    }
}

function pandocAst(string $file, string $format): array {
    $from = $format === 'markdown' ? 'gfm' : 'rst';
    $cmd = ['pandoc', '--from=' . $from, '--to=json', '--wrap=none', $file];
    $pipes = [];
    $proc = proc_open($cmd, [
        0 => ['file', '/dev/null', 'r'],
        1 => ['pipe', 'w'],
        2 => ['pipe', 'w'],
    ], $pipes);

    if (!is_resource($proc)) {
        throw new RuntimeException('unable to start pandoc');
    }

    $stdout = stream_get_contents($pipes[1]);
    $stderr = stream_get_contents($pipes[2]);
    fclose($pipes[1]);
    fclose($pipes[2]);
    $code = proc_close($proc);

    if ($code !== 0) {
        throw new RuntimeException(trim($stderr) !== '' ? trim($stderr) : "pandoc exited with {$code}");
    }

    $decoded = json_decode($stdout, true);
    if (!is_array($decoded)) {
        throw new RuntimeException('pandoc returned invalid JSON');
    }
    return $decoded;
}

function addNode(array &$nodes, array $node): void {
    $nodes[$node['id']] = $node;
}

function addEdge(array &$edges, array $edge): void {
    $key = implode('|', [$edge['source'], $edge['target'], $edge['relation'], $edge['source_file'] ?? '']);
    $edges[$key] = $edge;
}

function evidence(string $sourceFile, ?int $line = null, string $precision = 'document'): array {
    $result = ['source_file' => $sourceFile, 'precision' => $precision];
    if ($line !== null) {
        $result['line_start'] = $line;
        $result['line_end'] = $line;
    }
    return $result;
}

function lineForText(array $lines, string $text, int $start = 0): ?int {
    $needle = trim($text);
    if ($needle === '') {
        return null;
    }
    for ($i = $start; $i < count($lines); $i++) {
        if (str_contains(trim($lines[$i]), $needle)) {
            return $i + 1;
        }
    }
    return null;
}

function extractPandoc(
    array $ast,
    string $relative,
    string $source,
    string $format,
    array &$nodes,
    array &$edges,
    array &$unresolved
): void {
    $lines = preg_split('/\R/u', $source) ?: [];
    $documentId = $relative . '#document';

    walkAst($ast, function (array $node) use (
        $relative,
        $lines,
        $documentId,
        &$nodes,
        &$edges,
        &$unresolved
    ): void {
        $type = $node['t'] ?? '';
        $content = $node['c'] ?? null;

        if ($type === 'Header' && is_array($content)) {
            $level = (int)($content[0] ?? 1);
            $attr = is_array($content[1] ?? null) ? $content[1] : [];
            $title = inlineText($content[2] ?? []);
            $anchor = (string)($attr[0] ?? '');
            if ($anchor === '') {
                $anchor = slug($title);
            }
            $id = $relative . '#' . $anchor;
            $line = lineForText($lines, $title);
            addNode($nodes, [
                'id' => $id,
                'type' => 'section',
                'label' => $title,
                'level' => $level,
                'source_file' => $relative,
                'evidence' => evidence($relative, $line, $line ? 'line' : 'document'),
            ]);
            addEdge($edges, [
                'source' => $documentId,
                'target' => $id,
                'relation' => 'contains',
                'source_file' => $relative,
                'evidence' => evidence($relative, $line, $line ? 'line' : 'document'),
            ]);
            return;
        }

        if ($type === 'Link' && is_array($content)) {
            $targetSpec = $content[2] ?? null;
            if (!is_array($targetSpec)) {
                return;
            }
            $target = (string)($targetSpec[0] ?? '');
            $label = inlineText($content[1] ?? []);
            if ($target === '') {
                return;
            }

            $line = lineForText($lines, $target);
            $edge = [
                'source' => $documentId,
                'target' => $target,
                'relation' => 'links_to',
                'source_file' => $relative,
                'label' => $label,
                'evidence' => evidence($relative, $line, $line ? 'line' : 'document'),
            ];

            if (preg_match('~^(?:https?|mailto):~i', $target)) {
                addEdge($edges, $edge);
            } else {
                $unresolved[] = [
                    'source' => $documentId,
                    'target' => $target,
                    'relation' => 'links_to',
                    'source_file' => $relative,
                    'evidence' => $edge['evidence'],
                ];
            }
            return;
        }

        if ($type === 'CodeBlock' && is_array($content)) {
            $attr = is_array($content[0] ?? null) ? $content[0] : [];
            $classes = is_array($attr[1] ?? null) ? $attr[1] : [];
            $language = (string)($classes[0] ?? '');
            $code = (string)($content[1] ?? '');
            $hash = substr(hash('sha256', $code), 0, 12);
            $id = $relative . '#code-' . $hash;
            $line = $code !== '' ? lineForText($lines, strtok($code, "\n") ?: '') : null;
            addNode($nodes, [
                'id' => $id,
                'type' => 'code_block',
                'label' => $language !== '' ? $language . ' code block' : 'code block',
                'language' => $language,
                'source_file' => $relative,
                'evidence' => evidence($relative, $line, $line ? 'line' : 'document'),
            ]);
            addEdge($edges, [
                'source' => $documentId,
                'target' => $id,
                'relation' => 'contains',
                'source_file' => $relative,
                'evidence' => evidence($relative, $line, $line ? 'line' : 'document'),
            ]);
        }
    });
}

function extractRstSupplement(
    string $relative,
    string $source,
    array &$nodes,
    array &$edges,
    array &$unresolved
): void {
    $lines = preg_split('/\R/u', $source) ?: [];
    $documentId = $relative . '#document';
    $count = count($lines);

    for ($i = 0; $i < $count; $i++) {
        $line = $lines[$i];
        $lineNo = $i + 1;

        if (preg_match('/^\s*\.\.\s+_([^:]+):\s*$/u', $line, $m)) {
            $anchor = trim($m[1]);
            $id = $relative . '#' . slug($anchor);
            addNode($nodes, [
                'id' => $id,
                'type' => 'link_target',
                'label' => $anchor,
                'source_file' => $relative,
                'evidence' => evidence($relative, $lineNo, 'line'),
            ]);
            addEdge($edges, [
                'source' => $documentId,
                'target' => $id,
                'relation' => 'declares',
                'source_file' => $relative,
                'evidence' => evidence($relative, $lineNo, 'line'),
            ]);
        }

        if (preg_match('/^\s*\.\.\s+([a-zA-Z0-9_-]+)::\s*(.*?)\s*$/u', $line, $m)) {
            $directive = strtolower($m[1]);
            $argument = trim($m[2]);
            $id = $relative . '#directive-' . $lineNo . '-' . slug($directive);
            addNode($nodes, [
                'id' => $id,
                'type' => 'directive',
                'label' => $directive,
                'directive' => $directive,
                'argument' => $argument,
                'source_file' => $relative,
                'evidence' => evidence($relative, $lineNo, 'line'),
            ]);
            addEdge($edges, [
                'source' => $documentId,
                'target' => $id,
                'relation' => 'contains',
                'source_file' => $relative,
                'evidence' => evidence($relative, $lineNo, 'line'),
            ]);

            if ($directive === 'include' && $argument !== '') {
                $unresolved[] = [
                    'source' => $documentId,
                    'target' => $argument,
                    'relation' => 'includes',
                    'source_file' => $relative,
                    'evidence' => evidence($relative, $lineNo, 'line'),
                ];
            }

            if ($directive === 'toctree') {
                for ($j = $i + 1; $j < $count; $j++) {
                    $entry = $lines[$j];
                    if (trim($entry) === '') {
                        continue;
                    }
                    if (!preg_match('/^\s+(.+)$/u', $entry, $entryMatch)) {
                        break;
                    }
                    $target = trim($entryMatch[1]);
                    if ($target === '' || str_starts_with($target, ':')) {
                        continue;
                    }
                    $unresolved[] = [
                        'source' => $documentId,
                        'target' => $target,
                        'relation' => 'references',
                        'reference_type' => 'toctree',
                        'source_file' => $relative,
                        'evidence' => evidence($relative, $j + 1, 'line'),
                    ];
                }
            }
        }

        if (preg_match_all('/:(doc|ref|class|func|meth|mod):\x60([^\x60]+)\x60/u', $line, $matches, PREG_SET_ORDER)) {
            foreach ($matches as $match) {
                $unresolved[] = [
                    'source' => $documentId,
                    'target' => trim($match[2]),
                    'relation' => 'references',
                    'reference_type' => strtolower($match[1]),
                    'source_file' => $relative,
                    'evidence' => evidence($relative, $lineNo, 'line'),
                ];
            }
        }
    }
}

function supportedFormat(string $path): ?string {
    $ext = strtolower(pathinfo($path, PATHINFO_EXTENSION));
    return match ($ext) {
        'md', 'markdown' => 'markdown',
        'rst' => 'rst',
        default => null,
    };
}

function discoverFiles(string $input): array {
    $real = realpath($input);
    if ($real === false) {
        fail("path not found: {$input}", 66);
    }

    if (is_file($real)) {
        return supportedFormat($real) !== null ? [$real] : [];
    }

    $files = [];
    $iterator = new RecursiveIteratorIterator(
        new RecursiveDirectoryIterator($real, FilesystemIterator::SKIP_DOTS),
        RecursiveIteratorIterator::LEAVES_ONLY
    );

    foreach ($iterator as $info) {
        if (!$info->isFile() || $info->isLink()) {
            continue;
        }
        $path = $info->getPathname();
        $relative = relPath($path, $real);
        $segments = explode('/', str_replace('\\', '/', $relative));
        if (array_intersect($segments, DOCSTRUCT_EXCLUDES)) {
            continue;
        }
        if (supportedFormat($path) !== null) {
            $files[] = $path;
        }
    }

    sort($files, SORT_STRING);
    return $files;
}

function parseArgs(array $argv): array {
    $path = '.';
    $output = null;
    $pretty = true;

    for ($i = 1; $i < count($argv); $i++) {
        $arg = $argv[$i];
        if ($arg === '-h' || $arg === '--help') {
            echo "Usage: docstruct [path] [--output <file>] [--compact]\n";
            echo "Deterministically extract Markdown/RST structure as docker-tools.docstruct/v1 JSON.\n";
            exit(0);
        }
        if ($arg === '--output') {
            $output = $argv[++$i] ?? fail('--output requires a file');
            continue;
        }
        if ($arg === '--compact') {
            $pretty = false;
            continue;
        }
        if (str_starts_with($arg, '-')) {
            fail("unknown option: {$arg}");
        }
        $path = $arg;
    }

    return [$path, $output, $pretty];
}

[$input, $output, $pretty] = parseArgs($argv);

if (!command_exists('pandoc')) {
    fail('pandoc is required but not installed', 69);
}

$inputReal = realpath($input);
if ($inputReal === false) {
    fail("path not found: {$input}", 66);
}
$root = is_dir($inputReal) ? $inputReal : dirname($inputReal);
$files = discoverFiles($inputReal);

$records = [];
$nodes = [];
$edges = [];
$unresolved = [];
$warnings = [];

foreach ($files as $file) {
    $relative = relPath($file, $root);
    $format = supportedFormat($file);
    if ($format === null) {
        continue;
    }

    $source = file_get_contents($file);
    if ($source === false) {
        $warnings[] = ['source_file' => $relative, 'message' => 'unable to read file'];
        continue;
    }

    $documentId = $relative . '#document';
    addNode($nodes, [
        'id' => $documentId,
        'type' => 'document',
        'label' => basename($relative),
        'format' => $format,
        'source_file' => $relative,
        'evidence' => evidence($relative, null, 'document'),
    ]);

    $record = [
        'path' => $relative,
        'format' => $format,
        'sha256' => hash('sha256', $source),
        'bytes' => strlen($source),
        'parser' => $format === 'rst' ? 'pandoc+rst-supplement' : 'pandoc',
        'status' => 'ok',
        'warnings' => [],
    ];

    try {
        $ast = pandocAst($file, $format);
        extractPandoc($ast, $relative, $source, $format, $nodes, $edges, $unresolved);
        if ($format === 'rst') {
            extractRstSupplement($relative, $source, $nodes, $edges, $unresolved);
        }
    } catch (Throwable $e) {
        $record['status'] = 'error';
        $record['warnings'][] = $e->getMessage();
        $warnings[] = ['source_file' => $relative, 'message' => $e->getMessage()];
    }

    $records[] = $record;
}

ksort($nodes, SORT_STRING);
ksort($edges, SORT_STRING);
usort($unresolved, fn(array $a, array $b): int =>
    [$a['source_file'], $a['relation'], $a['target']] <=> [$b['source_file'], $b['relation'], $b['target']]
);

$result = [
    'schema' => DOCSTRUCT_SCHEMA,
    'root' => $root,
    'files' => $records,
    'nodes' => array_values($nodes),
    'edges' => array_values($edges),
    'unresolved_references' => $unresolved,
    'warnings' => $warnings,
    'stats' => [
        'files' => count($records),
        'nodes' => count($nodes),
        'edges' => count($edges),
        'unresolved_references' => count($unresolved),
    ],
];

$flags = JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE;
if ($pretty) {
    $flags |= JSON_PRETTY_PRINT;
}
$json = json_encode($result, $flags);
if ($json === false) {
    fail('unable to encode output JSON', 70);
}
$json .= "\n";

if ($output !== null) {
    $written = file_put_contents($output, $json);
    if ($written === false) {
        fail("unable to write output: {$output}", 73);
    }
} else {
    echo $json;
}

function command_exists(string $command): bool {
    $paths = explode(PATH_SEPARATOR, getenv('PATH') ?: '');
    foreach ($paths as $path) {
        if ($path !== '' && is_executable(rtrim($path, DIRECTORY_SEPARATOR) . DIRECTORY_SEPARATOR . $command)) {
            return true;
        }
    }
    return false;
}
