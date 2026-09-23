#!/usr/bin/env php
<?php
declare(strict_types=1);

const DOCSTRUCT_SCHEMA = 'docker-tools.docstruct/v1';
const DOCSTRUCT_EXCLUDES = ['.git', '.hg', '.svn', 'vendor', 'node_modules', 'dist', 'build', 'coverage', 'graphify-out'];
const DOCSTRUCT_DEFAULT_MAX_FILE_BYTES = 2097152;
const DOCSTRUCT_DEFAULT_MAX_CORPUS_BYTES = 33554432;
const DOCSTRUCT_DEFAULT_MAX_FILES = 1000;
const DOCSTRUCT_DEFAULT_MAX_NODES = 20000;
const DOCSTRUCT_DEFAULT_MAX_REFERENCES = 50000;
const DOCSTRUCT_DEFAULT_PARSE_TIMEOUT = 15;

function fail(string $message, int $code = 64): never {
    fwrite(STDERR, "docstruct: {$message}\n");
    exit($code);
}

function envUint(string $name, int $default, int $min = 1): int {
    $raw = getenv($name);
    if ($raw === false || $raw === '') {
        return $default;
    }
    if (!preg_match('/^\\d+$/', $raw)) {
        fail("{$name} must be an unsigned integer", 64);
    }
    $value = (int)$raw;
    if ($value < $min) {
        fail("{$name} must be >= {$min}", 64);
    }
    return $value;
}

function parserTimeout(): int {
    return envUint('DOCSTRUCT_PARSE_TIMEOUT', DOCSTRUCT_DEFAULT_PARSE_TIMEOUT);
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
    $cmd = ['timeout', parserTimeout() . 's', 'pandoc', '--from=' . $from, '--to=json', '--wrap=none', $file];
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

function normalizeRelativeTarget(string $sourceFile, string $target): ?string {
    $target = str_replace('\\\\', '/', trim($target));
    if ($target === '') {
        return '';
    }

    $parts = explode('#', $target, 2);
    $pathPart = $parts[0];
    $fragment = $parts[1] ?? '';

    if ($pathPart === '') {
        $normalized = $sourceFile;
    } else {
        $base = dirname($sourceFile);
        $combined = ($base === '.' ? '' : $base . '/') . $pathPart;
        $segments = [];
        foreach (explode('/', $combined) as $segment) {
            if ($segment === '' || $segment === '.') {
                continue;
            }
            if ($segment === '..') {
                if ($segments === []) {
                    return null;
                }
                array_pop($segments);
                continue;
            }
            $segments[] = $segment;
        }
        $normalized = implode('/', $segments);
    }

    return $fragment !== '' ? $normalized . '#' . slug($fragment) : $normalized;
}

function resolveReferences(array &$nodes, array &$edges, array &$unresolved): void {
    $documentIds = [];
    $anchorIds = [];

    foreach ($nodes as $id => $node) {
        if (($node['type'] ?? '') === 'document') {
            $documentIds[(string)$node['source_file']] = $id;
        }
        if (str_contains($id, '#') && ($node['type'] ?? '') !== 'document') {
            [, $anchor] = explode('#', $id, 2);
            $anchorIds[$anchor][] = $id;
        }
    }

    $remaining = [];

    foreach ($unresolved as $reference) {
        $sourceFile = (string)($reference['source_file'] ?? '');
        $target = (string)($reference['target'] ?? '');
        $referenceType = (string)($reference['reference_type'] ?? '');
        $relation = (string)($reference['relation'] ?? 'references');
        $resolvedTarget = null;

        if ($referenceType === 'ref') {
            $key = slug($target);
            if (isset($anchorIds[$key]) && count($anchorIds[$key]) === 1) {
                $resolvedTarget = $anchorIds[$key][0];
            }
        } elseif (in_array($referenceType, ['class', 'func', 'meth', 'mod'], true)) {
            $remaining[] = $reference;
            continue;
        } else {
            $candidate = normalizeRelativeTarget($sourceFile, $target);
            if ($candidate === null) {
                $remaining[] = $reference + ['reason' => 'target_outside_root'];
                continue;
            }
            $parts = explode('#', $candidate, 2);
            $path = $parts[0];
            $fragment = $parts[1] ?? '';

            $candidates = [$path];
            if ($path !== '' && pathinfo($path, PATHINFO_EXTENSION) === '') {
                $candidates[] = $path . '.rst';
                $candidates[] = $path . '.md';
                $candidates[] = rtrim($path, '/') . '/index.rst';
                $candidates[] = rtrim($path, '/') . '/index.md';
            }

            foreach ($candidates as $candidatePath) {
                if (!isset($documentIds[$candidatePath])) {
                    continue;
                }
                if ($fragment !== '') {
                    $candidateId = $candidatePath . '#' . slug($fragment);
                    if (isset($nodes[$candidateId])) {
                        $resolvedTarget = $candidateId;
                        break;
                    }
                    continue;
                }
                $resolvedTarget = $documentIds[$candidatePath];
                break;
            }

            if ($resolvedTarget === null && $referenceType === 'doc') {
                foreach ($candidates as $candidatePath) {
                    if (isset($documentIds[$candidatePath])) {
                        $resolvedTarget = $documentIds[$candidatePath];
                        break;
                    }
                }
            }
        }

        if ($resolvedTarget === null) {
            $remaining[] = $reference;
            continue;
        }

        addEdge($edges, [
            'source' => (string)$reference['source'],
            'target' => $resolvedTarget,
            'relation' => $relation,
            'source_file' => $sourceFile,
            'reference_type' => $referenceType !== '' ? $referenceType : null,
            'evidence' => $reference['evidence'] ?? evidence($sourceFile),
        ]);
    }

    $unresolved = $remaining;
}

function structuredData(string $file, string $format): array {
    if ($format === 'json') {
        $raw = file_get_contents($file);
        if ($raw === false) {
            throw new RuntimeException('unable to read JSON file');
        }
        $decoded = json_decode($raw, true);
        if (!is_array($decoded)) {
            throw new RuntimeException('JSON root must be an object or array');
        }
        return $decoded;
    }

    if ($format === 'ini') {
        $decoded = parse_ini_file($file, true, INI_SCANNER_RAW);
        if (!is_array($decoded)) {
            throw new RuntimeException('unable to parse INI/config file');
        }
        return $decoded;
    }

    if (!command_exists('yq')) {
        throw new RuntimeException('yq is required for YAML/TOML extraction');
    }

    $inputFormat = $format === 'toml' ? 'toml' : 'yaml';
    $cmd = ['timeout', parserTimeout() . 's', 'yq', '-p=' . $inputFormat, '-o=json', '.', $file];
    $pipes = [];
    $proc = proc_open($cmd, [
        0 => ['file', '/dev/null', 'r'],
        1 => ['pipe', 'w'],
        2 => ['pipe', 'w'],
    ], $pipes);

    if (!is_resource($proc)) {
        throw new RuntimeException('unable to start yq');
    }

    $stdout = stream_get_contents($pipes[1]);
    $stderr = stream_get_contents($pipes[2]);
    fclose($pipes[1]);
    fclose($pipes[2]);
    $code = proc_close($proc);

    if ($code !== 0) {
        throw new RuntimeException(trim($stderr) !== '' ? trim($stderr) : "yq exited with {$code}");
    }

    $decoded = json_decode($stdout, true);
    if (!is_array($decoded)) {
        throw new RuntimeException('yq returned invalid structured JSON');
    }
    return $decoded;
}

function configNodeId(string $relative, string $path): string {
    return $relative . '#config-' . substr(hash('sha256', $path), 0, 16);
}

function sensitiveConfigPath(string $path): bool {
    return preg_match('/(?:^|[._-])(password|passwd|secret|token|credential|auth|private[_-]?key|api[_-]?key)(?:$|[._-])/i', $path) === 1;
}

function configReference(string $value): ?array {
    $value = trim($value);
    if ($value === '' || strlen($value) > 2048) {
        return null;
    }

    if (preg_match('~^https?://[^\s]+$~i', $value) === 1) {
        return ['target' => $value, 'reference_type' => 'url'];
    }

    if (preg_match('~^(?:\.?\.?/)?[^\s]+\.(?:md|markdown|rst|ya?ml|json|toml|ini|cfg)(?:#[A-Za-z0-9._:-]+)?$~i', $value) === 1) {
        return ['target' => $value, 'reference_type' => 'config_path'];
    }

    return null;
}

function extractConfigKeys(
    mixed $value,
    string $relative,
    string $documentId,
    array &$nodes,
    array &$edges,
    array &$unresolved,
    string $path = '',
    ?string $parentId = null
): void {
    if (!is_array($value)) {
        return;
    }

    foreach ($value as $key => $child) {
        $segment = is_int($key) ? '[' . $key . ']' : (string)$key;
        $childPath = $path === ''
            ? $segment
            : (is_int($key) ? $path . $segment : $path . '.' . $segment);

        if (!is_int($key)) {
            $id = configNodeId($relative, $childPath);
            addNode($nodes, [
                'id' => $id,
                'type' => 'config_key',
                'label' => (string)$key,
                'key_path' => $childPath,
                'source_file' => $relative,
                'evidence' => evidence($relative, null, 'document'),
            ]);
            addEdge($edges, [
                'source' => $parentId ?? $documentId,
                'target' => $id,
                'relation' => $parentId === null ? 'declares' : 'parent_of',
                'source_file' => $relative,
                'evidence' => evidence($relative, null, 'document'),
            ]);
            if (!is_array($child) && is_scalar($child) && !sensitiveConfigPath($childPath)) {
                $reference = configReference((string)$child);
                if (is_array($reference)) {
                    if ($reference['reference_type'] === 'url') {
                        addEdge($edges, [
                            'source' => $id,
                            'target' => $reference['target'],
                            'relation' => 'references',
                            'reference_type' => 'url',
                            'source_file' => $relative,
                            'evidence' => evidence($relative, null, 'document'),
                        ]);
                    } else {
                        $unresolved[] = [
                            'source' => $id,
                            'target' => $reference['target'],
                            'relation' => 'references',
                            'reference_type' => $reference['reference_type'],
                            'source_file' => $relative,
                            'evidence' => evidence($relative, null, 'document'),
                        ];
                    }
                }
            }

            extractConfigKeys($child, $relative, $documentId, $nodes, $edges, $unresolved, $childPath, $id);
            continue;
        }

        extractConfigKeys($child, $relative, $documentId, $nodes, $edges, $unresolved, $childPath, $parentId);
    }
}

function isPythonRequirementsManifest(string $path): bool {
    $normalized = str_replace('\\', '/', $path);
    $base = strtolower(basename($normalized));
    if (preg_match('/^(?:requirements|constraints)(?:[-_.][a-z0-9][a-z0-9._-]*)?\.txt$/i', $base) === 1) {
        return true;
    }

    $parent = strtolower(basename(dirname($normalized)));
    return $parent === 'requirements' && str_ends_with($base, '.txt');
}

function requirementLogicalLines(string $source): array {
    $physical = preg_split('/\R/u', $source) ?: [];
    $logical = [];
    $buffer = '';
    $startLine = 1;

    foreach ($physical as $index => $line) {
        $lineNo = $index + 1;
        $trimmedRight = rtrim($line);
        if ($buffer === '') {
            $startLine = $lineNo;
        }

        $continued = str_ends_with($trimmedRight, '\\');
        if ($continued) {
            $trimmedRight = rtrim(substr($trimmedRight, 0, -1));
        }

        $buffer .= ($buffer === '' ? '' : ' ') . trim($trimmedRight);
        if ($continued) {
            continue;
        }

        $logical[] = ['line' => $startLine, 'text' => trim($buffer)];
        $buffer = '';
    }

    if ($buffer !== '') {
        $logical[] = ['line' => $startLine, 'text' => trim($buffer)];
    }

    return $logical;
}

function requirementDependencyId(string $relative, string $package): string {
    return $relative . '#dependency-' . slug($package);
}

function extractPythonRequirements(
    string $relative,
    string $source,
    string $documentId,
    array &$nodes,
    array &$edges,
    array &$unresolved
): void {
    foreach (requirementLogicalLines($source) as $entry) {
        $lineNo = (int)$entry['line'];
        $line = trim((string)$entry['text']);
        if ($line === '' || str_starts_with($line, '#')) {
            continue;
        }

        $line = preg_replace('/\s+#.*$/u', '', $line) ?? $line;
        $line = trim($line);
        if ($line === '') {
            continue;
        }

        $target = null;
        $referenceType = null;
        if (preg_match('/^(?:-r|--requirement)(?:=|\s+)(\S+)$/i', $line, $match) === 1) {
            $target = trim($match[1], "'\"");
            $referenceType = 'requirement_include';
        } elseif (preg_match('/^(?:-c|--constraint)(?:=|\s+)(\S+)$/i', $line, $match) === 1) {
            $target = trim($match[1], "'\"");
            $referenceType = 'constraint_include';
        }

        if ($target !== null && $target !== '') {
            $unresolved[] = [
                'source' => $documentId,
                'target' => $target,
                'relation' => $referenceType === 'requirement_include' ? 'includes' : 'references',
                'reference_type' => $referenceType,
                'source_file' => $relative,
                'evidence' => evidence($relative, $lineNo, 'line'),
            ];
            continue;
        }

        // Options, editable paths and bare URL/VCS requirements are deliberately
        // not copied into the sidecar: they may contain credentials or tokens.
        if (str_starts_with($line, '-')
            || preg_match('~^(?:https?|file)://~i', $line) === 1
            || preg_match('~^(?:git|hg|svn|bzr)\+~i', $line) === 1
            || str_starts_with($line, '.')
            || str_starts_with($line, '/')) {
            continue;
        }

        if (preg_match('/^([A-Za-z0-9][A-Za-z0-9._-]*)/', $line, $match) !== 1) {
            continue;
        }

        $package = $match[1];
        $id = requirementDependencyId($relative, $package);
        addNode($nodes, [
            'id' => $id,
            'type' => 'dependency',
            'label' => $package,
            'package' => $package,
            'ecosystem' => 'python',
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
}

function supportedFormat(string $path): ?string {
    if (isPythonRequirementsManifest($path)) {
        return 'requirements';
    }

    $ext = strtolower(pathinfo($path, PATHINFO_EXTENSION));
    return match ($ext) {
        'md', 'markdown' => 'markdown',
        'rst' => 'rst',
        'yaml', 'yml' => 'yaml',
        'json' => 'json',
        'toml' => 'toml',
        'ini', 'cfg' => 'ini',
        default => null,
    };
}

function matchesAnyPattern(string $relative, array $patterns): bool {
    foreach ($patterns as $pattern) {
        if (fnmatch($pattern, $relative, FNM_PATHNAME) || fnmatch($pattern, basename($relative))) {
            return true;
        }
    }

    return false;
}

/** @param list<string> $paths
 *  @return array<string,true>
 */
function gitIgnoredPaths(string $root, array $paths): array {
    if ($paths === [] || !command_exists('git')) {
        return [];
    }

    $pipes = [];
    $proc = proc_open(
        ['git', '-C', $root, 'rev-parse', '--show-toplevel'],
        [0 => ['file', '/dev/null', 'r'], 1 => ['pipe', 'w'], 2 => ['pipe', 'w']],
        $pipes
    );
    if (!is_resource($proc)) {
        return [];
    }
    $repoRoot = trim((string)stream_get_contents($pipes[1]));
    stream_get_contents($pipes[2]);
    fclose($pipes[1]);
    fclose($pipes[2]);
    if (proc_close($proc) !== 0 || $repoRoot === '') {
        return [];
    }

    $repoRoot = rtrim(str_replace('\\', '/', $repoRoot), '/');
    $repoRelative = [];
    foreach ($paths as $path) {
        $normalized = str_replace('\\', '/', $path);
        if (!str_starts_with($normalized, $repoRoot . '/')) {
            continue;
        }
        $relative = substr($normalized, strlen($repoRoot) + 1);
        $repoRelative[$relative] = $path;
    }
    if ($repoRelative === []) {
        return [];
    }

    $pipes = [];
    $proc = proc_open(
        ['git', '-C', $repoRoot, 'check-ignore', '-z', '--stdin'],
        [0 => ['pipe', 'r'], 1 => ['pipe', 'w'], 2 => ['pipe', 'w']],
        $pipes
    );
    if (!is_resource($proc)) {
        return [];
    }

    fwrite($pipes[0], implode("\0", array_keys($repoRelative)) . "\0");
    fclose($pipes[0]);
    $stdout = (string)stream_get_contents($pipes[1]);
    stream_get_contents($pipes[2]);
    fclose($pipes[1]);
    fclose($pipes[2]);
    $code = proc_close($proc);
    if (!in_array($code, [0, 1], true)) {
        return [];
    }

    $ignored = [];
    foreach (array_filter(explode("\0", $stdout), static fn(string $value): bool => $value !== '') as $relative) {
        if (isset($repoRelative[$relative])) {
            $ignored[$repoRelative[$relative]] = true;
        }
    }

    return $ignored;
}

function discoverFiles(string $input, array $includes = [], array $excludes = [], bool $respectGitignore = true): array {
    $real = realpath($input);
    $maxFileBytes = envUint('DOCSTRUCT_MAX_FILE_BYTES', DOCSTRUCT_DEFAULT_MAX_FILE_BYTES);
    $maxCorpusBytes = envUint('DOCSTRUCT_MAX_CORPUS_BYTES', DOCSTRUCT_DEFAULT_MAX_CORPUS_BYTES);
    $maxFiles = envUint('DOCSTRUCT_MAX_FILES', DOCSTRUCT_DEFAULT_MAX_FILES);
    $corpusBytes = 0;
    if ($real === false) {
        fail("path not found: {$input}", 66);
    }

    if (is_file($real)) {
        if (supportedFormat($real) === null) {
            return [];
        }
        $relative = basename($real);
        if (($includes !== [] && !matchesAnyPattern($relative, $includes)) || matchesAnyPattern($relative, $excludes)) {
            return [];
        }
        $bytes = filesize($real);
        if ($bytes === false || $bytes > $maxFileBytes) {
            fail("file exceeds DOCSTRUCT_MAX_FILE_BYTES: {$input}", 65);
        }
        return [$real];
    }

    $candidates = [];
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
        if (supportedFormat($path) === null) {
            continue;
        }
        if (($includes !== [] && !matchesAnyPattern($relative, $includes)) || matchesAnyPattern($relative, $excludes)) {
            continue;
        }
        $candidates[] = $path;
    }

    $ignored = $respectGitignore ? gitIgnoredPaths($real, $candidates) : [];
    $files = [];
    foreach ($candidates as $path) {
        if (isset($ignored[$path])) {
            continue;
        }
        $relative = relPath($path, $real);
        $bytes = filesize($path);
        if ($bytes === false || $bytes > $maxFileBytes) {
            fail("file exceeds DOCSTRUCT_MAX_FILE_BYTES: {$relative}", 65);
        }
        $corpusBytes += $bytes;
        if ($corpusBytes > $maxCorpusBytes) {
            fail('corpus exceeds DOCSTRUCT_MAX_CORPUS_BYTES', 65);
        }
        $files[] = $path;
        if (count($files) > $maxFiles) {
            fail('corpus exceeds DOCSTRUCT_MAX_FILES', 65);
        }
    }

    sort($files, SORT_STRING);
    return $files;
}

function parseArgs(array $argv): array {
    $path = '.';
    $output = null;
    $pretty = true;
    $includes = [];
    $excludes = [];
    $respectGitignore = true;

    for ($i = 1; $i < count($argv); $i++) {
        $arg = $argv[$i];
        if ($arg === '-h' || $arg === '--help') {
            echo "Usage: docstruct [path] [--include <glob>] [--exclude <glob>] [--no-gitignore] [--output <file>] [--compact]\n";
            echo "Deterministically extract Markdown/RST/YAML/JSON/TOML/INI/Python-requirements structure as docker-tools.docstruct/v1 JSON.\n";
            echo "Repeat --include/--exclude to shape directory scans. .gitignore is respected by default when Git metadata is available.\n";
            echo "Limits: DOCSTRUCT_MAX_FILE_BYTES, DOCSTRUCT_MAX_CORPUS_BYTES, DOCSTRUCT_MAX_FILES, DOCSTRUCT_MAX_NODES, DOCSTRUCT_MAX_REFERENCES, DOCSTRUCT_PARSE_TIMEOUT.\n";
            exit(0);
        }
        if ($arg === '--output') {
            $output = $argv[++$i] ?? fail('--output requires a file');
            continue;
        }
        if ($arg === '--include') {
            $includes[] = $argv[++$i] ?? fail('--include requires a glob');
            continue;
        }
        if ($arg === '--exclude') {
            $excludes[] = $argv[++$i] ?? fail('--exclude requires a glob');
            continue;
        }
        if ($arg === '--no-gitignore') {
            $respectGitignore = false;
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

    return [
        'path' => $path,
        'output' => $output,
        'pretty' => $pretty,
        'includes' => $includes,
        'excludes' => $excludes,
        'respect_gitignore' => $respectGitignore,
    ];
}

$options = parseArgs($argv);
$input = $options['path'];
$output = $options['output'];
$pretty = $options['pretty'];

$inputReal = realpath($input);
if ($inputReal === false) {
    fail("path not found: {$input}", 66);
}
$root = is_dir($inputReal) ? $inputReal : dirname($inputReal);
$files = discoverFiles(
    $inputReal,
    $options['includes'],
    $options['excludes'],
    $options['respect_gitignore']
);
if (array_filter($files, static fn(string $file): bool => in_array(supportedFormat($file), ['markdown', 'rst'], true)) !== []
    && !command_exists('pandoc')) {
    fail('pandoc is required for Markdown/RST extraction but is not installed', 69);
}

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
        'parser' => match ($format) {
            'rst' => 'pandoc+rst-supplement',
            'markdown' => 'pandoc',
            'json' => 'php-json',
            'ini' => 'php-ini',
            'requirements' => 'php-requirements',
            default => 'yq',
        },
        'status' => 'ok',
        'warnings' => [],
    ];

    try {
        if (in_array($format, ['markdown', 'rst'], true)) {
            $ast = pandocAst($file, $format);
            extractPandoc($ast, $relative, $source, $format, $nodes, $edges, $unresolved);
            if ($format === 'rst') {
                extractRstSupplement($relative, $source, $nodes, $edges, $unresolved);
            }
        } elseif ($format === 'requirements') {
            extractPythonRequirements($relative, $source, $documentId, $nodes, $edges, $unresolved);
        } else {
            $structured = structuredData($file, $format);
            extractConfigKeys($structured, $relative, $documentId, $nodes, $edges, $unresolved);
        }
    } catch (Throwable $e) {
        $record['status'] = 'error';
        $record['warnings'][] = $e->getMessage();
        $warnings[] = ['source_file' => $relative, 'message' => $e->getMessage()];
    }

    $records[] = $record;
    if (count($nodes) > envUint('DOCSTRUCT_MAX_NODES', DOCSTRUCT_DEFAULT_MAX_NODES)) {
        fail('extracted structure exceeds DOCSTRUCT_MAX_NODES', 65);
    }
    if (count($edges) + count($unresolved) > envUint('DOCSTRUCT_MAX_REFERENCES', DOCSTRUCT_DEFAULT_MAX_REFERENCES)) {
        fail('extracted structure exceeds DOCSTRUCT_MAX_REFERENCES', 65);
    }
}

resolveReferences($nodes, $edges, $unresolved);
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
