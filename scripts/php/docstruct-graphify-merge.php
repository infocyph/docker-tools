#!/usr/bin/env php
<?php
declare(strict_types=1);

const DOCSTRUCT_GRAPHIFY_ORIGIN = 'docker-tools.docstruct/v1';

/** @return never */
function mergeFail(string $message, int $code = 64): never
{
    fwrite(STDERR, "docstruct graphify-merge: {$message}\n");
    exit($code);
}

/** @return array<string,mixed> */
function mergeReadJson(string $path, string $label): array
{
    if (!is_file($path) || !is_readable($path)) {
        mergeFail("{$label} is not readable: {$path}", 66);
    }
    $raw = file_get_contents($path);
    if (!is_string($raw)) {
        mergeFail("unable to read {$label}: {$path}", 66);
    }
    try {
        $decoded = json_decode($raw, true, 512, JSON_THROW_ON_ERROR);
    } catch (JsonException $e) {
        mergeFail("{$label} is invalid JSON: " . $e->getMessage(), 65);
    }
    if (!is_array($decoded) || array_is_list($decoded)) {
        mergeFail("{$label} must be a JSON object", 65);
    }
    return $decoded;
}

function docstructSemanticSource(string $sourceFile): bool
{
    $path = parse_url($sourceFile, PHP_URL_PATH);
    if (!is_string($path) || $path === '') {
        $path = $sourceFile;
    }
    $ext = strtolower(pathinfo($path, PATHINFO_EXTENSION));
    return in_array($ext, ['md', 'markdown', 'rst', 'yaml', 'yml', 'json', 'toml', 'ini', 'cfg'], true);
}

function legacySemanticOwnedByDocstruct(array $node): bool
{
    $sourceFile = $node['source_file'] ?? null;
    if (!is_string($sourceFile) || !docstructSemanticSource($sourceFile)) {
        return false;
    }
    $fileType = strtolower((string)($node['file_type'] ?? ''));
    return in_array($fileType, ['document', 'paper', 'image', 'concept', 'rationale'], true);
}

function docstructOwnedNode(array $node): bool
{
    if (($node['docstruct_origin'] ?? null) === DOCSTRUCT_GRAPHIFY_ORIGIN) {
        return true;
    }

    $id = $node['id'] ?? null;
    if (!is_string($id) || !str_starts_with($id, 'docstruct_')) {
        return false;
    }

    $fileType = strtolower((string)($node['file_type'] ?? ''));
    return in_array($fileType, ['document', 'paper', 'image', 'concept', 'rationale'], true);
}

function docstructOwnedEdge(array $edge): bool
{
    return ($edge['docstruct_origin'] ?? null) === DOCSTRUCT_GRAPHIFY_ORIGIN;
}

/** @return array<string,mixed> */
function mergeGraphify(array $graph, array $fragment): array
{
    foreach (['nodes', 'edges', 'hyperedges'] as $key) {
        if (isset($fragment[$key]) && !is_array($fragment[$key])) {
            mergeFail("fragment {$key} must be an array", 65);
        }
    }

    $graphNodes = $graph['nodes'] ?? [];
    if (!is_array($graphNodes)) {
        mergeFail('graph nodes must be an array', 65);
    }

    $edgeKey = array_key_exists('links', $graph) && !array_key_exists('edges', $graph) ? 'links' : 'edges';
    $graphEdges = $graph[$edgeKey] ?? [];
    if (!is_array($graphEdges)) {
        mergeFail("graph {$edgeKey} must be an array", 65);
    }
    $graphHyperedges = $graph['hyperedges'] ?? [];
    if (!is_array($graphHyperedges)) {
        mergeFail('graph hyperedges must be an array', 65);
    }

    $removedIds = [];
    $keptNodes = [];
    $seenIds = [];

    foreach ($graphNodes as $node) {
        if (!is_array($node) || !is_string($node['id'] ?? null) || $node['id'] === '') {
            mergeFail('existing graph contains a node without a valid id', 65);
        }
        if (docstructOwnedNode($node) || legacySemanticOwnedByDocstruct($node)) {
            $removedIds[$node['id']] = true;
            continue;
        }
        if (isset($seenIds[$node['id']])) {
            mergeFail("existing graph contains duplicate node id: {$node['id']}", 65);
        }
        $seenIds[$node['id']] = true;
        $keptNodes[] = $node;
    }

    $fragmentNodes = $fragment['nodes'] ?? [];
    foreach ($fragmentNodes as $node) {
        if (!is_array($node) || !is_string($node['id'] ?? null) || $node['id'] === '') {
            mergeFail('fragment contains a node without a valid id', 65);
        }
        if (!str_starts_with($node['id'], 'docstruct_')
            || ($node['docstruct_origin'] ?? null) !== DOCSTRUCT_GRAPHIFY_ORIGIN) {
            mergeFail("fragment node is outside the reserved docstruct namespace: {$node['id']}", 65);
        }
        if (isset($seenIds[$node['id']])) {
            mergeFail("fragment node collides with an existing code/graph node: {$node['id']}", 65);
        }
        $seenIds[$node['id']] = true;
        $keptNodes[] = $node;
    }

    $keptEdges = [];
    $edgeSeen = [];
    foreach ($graphEdges as $edge) {
        if (!is_array($edge)) {
            continue;
        }
        $source = (string)($edge['source'] ?? '');
        $target = (string)($edge['target'] ?? '');
        if (docstructOwnedEdge($edge) || isset($removedIds[$source]) || isset($removedIds[$target])) {
            continue;
        }
        $key = implode('|', [$source, $target, (string)($edge['relation'] ?? ''), (string)($edge['source_file'] ?? '')]);
        if (isset($edgeSeen[$key])) {
            continue;
        }
        $edgeSeen[$key] = true;
        $keptEdges[] = $edge;
    }

    foreach (($fragment['edges'] ?? []) as $edge) {
        if (!is_array($edge)) {
            mergeFail('fragment edge must be an object', 65);
        }
        $source = (string)($edge['source'] ?? '');
        $target = (string)($edge['target'] ?? '');
        if (($edge['docstruct_origin'] ?? null) !== DOCSTRUCT_GRAPHIFY_ORIGIN) {
            mergeFail('fragment edge is missing the docstruct origin marker', 65);
        }
        if (!isset($seenIds[$source], $seenIds[$target])) {
            mergeFail("fragment edge references an unknown node: {$source} -> {$target}", 65);
        }
        $key = implode('|', [$source, $target, (string)($edge['relation'] ?? ''), (string)($edge['source_file'] ?? '')]);
        if (isset($edgeSeen[$key])) {
            continue;
        }
        $edgeSeen[$key] = true;
        $keptEdges[] = $edge;
    }

    $keptHyperedges = [];
    foreach ($graphHyperedges as $hyperedge) {
        if (!is_array($hyperedge)) {
            continue;
        }
        if (($hyperedge['docstruct_origin'] ?? null) === DOCSTRUCT_GRAPHIFY_ORIGIN) {
            continue;
        }
        $members = $hyperedge['members'] ?? [];
        if (is_array($members) && array_filter(
            $members,
            static fn(mixed $id): bool => is_string($id) && isset($removedIds[$id])
        )) {
            continue;
        }
        $keptHyperedges[] = $hyperedge;
    }
    foreach (($fragment['hyperedges'] ?? []) as $hyperedge) {
        if (!is_array($hyperedge)) {
            mergeFail('fragment hyperedge must be an object', 65);
        }
        $keptHyperedges[] = $hyperedge;
    }

    $graph['nodes'] = $keptNodes;
    $graph[$edgeKey] = $keptEdges;
    if ($edgeKey === 'links') {
        unset($graph['edges']);
    }
    if ($edgeKey === 'edges') {
        unset($graph['links']);
    }
    $graph['hyperedges'] = $keptHyperedges;

    if (isset($graph['input_tokens']) && is_numeric($graph['input_tokens'])) {
        $graph['input_tokens'] += (int)($fragment['input_tokens'] ?? 0);
    }
    if (isset($graph['output_tokens']) && is_numeric($graph['output_tokens'])) {
        $graph['output_tokens'] += (int)($fragment['output_tokens'] ?? 0);
    }

    return $graph;
}

/** @return array{graph:string,fragment:string,output:?string,pretty:bool} */
function parseMergeArgs(array $argv): array
{
    $graph = '';
    $fragment = '';
    $output = null;
    $pretty = true;

    for ($i = 1; $i < count($argv); $i++) {
        $arg = $argv[$i];
        if ($arg === '-h' || $arg === '--help') {
            echo "Usage: docstruct graphify-merge <graph.json> <fragment.json> [--output <file>] [--compact]\n";
            echo "Replaces only docker-tools docstruct-owned nodes/edges in a Graphify graph.\n";
            exit(0);
        }
        if ($arg === '--output') {
            $output = $argv[++$i] ?? mergeFail('--output requires a file');
            continue;
        }
        if ($arg === '--compact') {
            $pretty = false;
            continue;
        }
        if (str_starts_with($arg, '-')) {
            mergeFail("unknown option: {$arg}");
        }
        if ($graph === '') {
            $graph = $arg;
            continue;
        }
        if ($fragment === '') {
            $fragment = $arg;
            continue;
        }
        mergeFail('only graph and fragment input files may be supplied');
    }

    if ($graph === '' || $fragment === '') {
        mergeFail('graph and fragment input files are required');
    }

    return ['graph' => $graph, 'fragment' => $fragment, 'output' => $output, 'pretty' => $pretty];
}

function writeAtomic(string $path, string $content): void
{
    $dir = dirname($path);
    if (!is_dir($dir)) {
        mergeFail("output directory does not exist: {$dir}", 73);
    }
    $tmp = tempnam($dir, '.docstruct-merge.');
    if ($tmp === false) {
        mergeFail("unable to create temporary output in {$dir}", 73);
    }
    try {
        if (file_put_contents($tmp, $content) === false) {
            mergeFail("unable to write temporary output: {$tmp}", 73);
        }
        if (!rename($tmp, $path)) {
            mergeFail("unable to publish merged graph: {$path}", 73);
        }
    } finally {
        if (is_file($tmp)) {
            @unlink($tmp);
        }
    }
}

$options = parseMergeArgs($argv);
$graph = mergeReadJson($options['graph'], 'graph input');
$fragment = mergeReadJson($options['fragment'], 'fragment input');
$merged = mergeGraphify($graph, $fragment);

$flags = JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE;
if ($options['pretty']) {
    $flags |= JSON_PRETTY_PRINT;
}
$json = json_encode($merged, $flags | JSON_THROW_ON_ERROR) . "\n";

if ($options['output'] !== null) {
    writeAtomic($options['output'], $json);
} else {
    echo $json;
}
