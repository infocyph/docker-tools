#!/usr/bin/env php
<?php
declare(strict_types=1);

const DOCSTRUCT_GRAPHIFY_SCHEMA = 'docker-tools.docstruct/v1';
const DOCSTRUCT_REVIEW_SCHEMA = 'docker-tools.docstruct-review/v1';

/** @return never */
function graphifyFail(string $message, int $code = 64): never
{
    fwrite(STDERR, "docstruct graphify: {$message}\n");
    exit($code);
}

/** @return array<string,mixed> */
function readJsonObject(string $path, string $label): array
{
    if (!is_file($path) || !is_readable($path)) {
        graphifyFail("{$label} is not readable: {$path}", 66);
    }

    $raw = file_get_contents($path);
    if (!is_string($raw)) {
        graphifyFail("unable to read {$label}: {$path}", 66);
    }

    try {
        $decoded = json_decode($raw, true, 512, JSON_THROW_ON_ERROR);
    } catch (JsonException $exception) {
        graphifyFail("{$label} is invalid JSON: " . $exception->getMessage(), 65);
    }

    if (!is_array($decoded) || array_is_list($decoded)) {
        graphifyFail("{$label} must be a JSON object", 65);
    }

    return $decoded;
}

function graphifySlug(string $value): string
{
    $value = strtolower($value);
    $value = preg_replace('/[^a-z0-9]+/', '_', $value) ?? '';
    $value = trim($value, '_');

    return $value !== '' ? $value : 'item';
}

function graphifyStem(string $sourceFile): string
{
    $normalized = str_replace('\\', '/', $sourceFile);
    $withoutExtension = preg_replace('/\.[^\.\/]+$/', '', $normalized) ?? $normalized;

    return graphifySlug($withoutExtension);
}

function graphifyId(string $sourceFile, string $entity): string
{
    $id = 'docstruct_' . graphifyStem($sourceFile) . '_' . graphifySlug($entity);
    if (strlen($id) <= 240) {
        return $id;
    }

    return substr($id, 0, 223) . '_' . substr(hash('sha256', $id), 0, 16);
}

/** @param array<string,mixed> $evidence */
function graphifyLocation(array $evidence): ?string
{
    $start = $evidence['line_start'] ?? null;
    $end = $evidence['line_end'] ?? null;
    if (!is_int($start) || $start < 1) {
        return null;
    }
    if (is_int($end) && $end > $start) {
        return sprintf('L%d-L%d', $start, $end);
    }

    return 'L' . $start;
}

function absoluteSource(string $root, string $relative): string
{
    $relative = str_replace('\\', '/', $relative);
    if ($relative === '') {
        graphifyFail('source_file cannot be empty', 65);
    }
    if (str_starts_with($relative, '/') || preg_match('~^[A-Za-z]:[\\\\/]~', $relative) === 1) {
        return $relative;
    }

    return rtrim(str_replace('\\', '/', $root), '/') . '/' . ltrim($relative, '/');
}

/** @param array<string,mixed> $node
 *  @return array<string,mixed>|null
 */
function mechanicalNode(array $node, string $root): ?array
{
    $type = (string)($node['type'] ?? '');
    if (!in_array($type, ['document', 'section', 'link_target', 'dependency'], true)) {
        return null;
    }

    $source = (string)($node['source_file'] ?? '');
    $label = trim((string)($node['label'] ?? ''));
    if ($source === '' || $label === '') {
        return null;
    }

    $entity = $type === 'document'
        ? 'document'
        : ((string)preg_replace('/^.*#/', '', (string)($node['id'] ?? '')) ?: $label);

    return [
        'id' => graphifyId($source, $entity),
        'label' => $label,
        'file_type' => 'document',
        'source_file' => absoluteSource($root, $source),
        'source_location' => graphifyLocation(is_array($node['evidence'] ?? null) ? $node['evidence'] : []),
        'source_url' => null,
        'captured_at' => null,
        'author' => null,
        'contributor' => null,
        'docstruct_origin' => DOCSTRUCT_GRAPHIFY_SCHEMA,
    ];
}

/** @return array{0:string,1:float} */
function reviewConfidence(float $confidence): array
{
    if ($confidence >= 0.90) {
        return ['INFERRED', 0.95];
    }
    if ($confidence >= 0.80) {
        return ['INFERRED', 0.85];
    }
    if ($confidence >= 0.70) {
        return ['INFERRED', 0.75];
    }
    if ($confidence >= 0.60) {
        return ['INFERRED', 0.65];
    }
    if ($confidence >= 0.50) {
        return ['INFERRED', 0.55];
    }

    return ['AMBIGUOUS', max(0.10, min(0.30, $confidence))];
}

function reviewFileType(string $type): string
{
    return match ($type) {
        'document', 'paper', 'image', 'rationale', 'concept' => $type,
        default => 'concept',
    };
}

function allowedReviewRelation(string $relation): bool
{
    return in_array($relation, [
        'references',
        'contains',
        'conceptually_related_to',
        'shares_data_with',
        'semantically_similar_to',
        'rationale_for',
    ], true);
}

/**
 * Canonicalize the docstruct fragment to Graphify's loaded-graph identity rule.
 *
 * Graphify's build_from_json() treats a located non-AST node as canonical by
 * (source_file, label) and rewires later semantic twins onto that node. A raw
 * fragment that keeps several such nodes is therefore larger on disk than it is
 * after Graphify loads it, which trips Graphify's shrink guard during label.
 *
 * @param array<string,array<string,mixed>> $nodes
 * @param array<string,array<string,mixed>> $edges
 * @return array{0:array<string,array<string,mixed>>,1:array<string,array<string,mixed>>}
 */
function canonicalizeGraphifyLocatedIdentity(array $nodes, array $edges): array
{
    ksort($nodes, SORT_STRING);

    $canonicalByKey = [];
    foreach ($nodes as $id => $node) {
        $sourceFile = trim((string)($node['source_file'] ?? ''));
        $label = trim((string)($node['label'] ?? ''));
        $location = trim((string)($node['source_location'] ?? ''));
        if ($sourceFile === '' || $label === '' || $location === '') {
            continue;
        }

        $key = $sourceFile . "\0" . $label;
        $canonicalByKey[$key] ??= $id;
    }

    if ($canonicalByKey === []) {
        return [$nodes, $edges];
    }

    $remap = [];
    foreach ($nodes as $id => $node) {
        $sourceFile = trim((string)($node['source_file'] ?? ''));
        $label = trim((string)($node['label'] ?? ''));
        if ($sourceFile === '' || $label === '') {
            continue;
        }

        $key = $sourceFile . "\0" . $label;
        $canonical = $canonicalByKey[$key] ?? null;
        if (is_string($canonical) && $canonical !== $id) {
            $remap[$id] = $canonical;
            unset($nodes[$id]);
        }
    }

    if ($remap === []) {
        return [$nodes, $edges];
    }

    $rewired = [];
    foreach ($edges as $edge) {
        $source = (string)($edge['source'] ?? '');
        $target = (string)($edge['target'] ?? '');
        if (isset($remap[$source])) {
            $source = $remap[$source];
        }
        if (isset($remap[$target])) {
            $target = $remap[$target];
        }

        $edge['source'] = $source;
        $edge['target'] = $target;
        $key = implode('|', [
            $source,
            $target,
            (string)($edge['relation'] ?? ''),
            (string)($edge['source_file'] ?? ''),
        ]);
        $rewired[$key] = $edge;
    }

    return [$nodes, $rewired];
}

/** @param array<string,mixed> $doc
 *  @param array<string,mixed>|null $review
 *  @return array<string,mixed>
 */
function buildGraphifyFragment(array $doc, ?array $review, ?string $sourceRootOverride = null): array
{
    if (($doc['schema'] ?? null) !== DOCSTRUCT_GRAPHIFY_SCHEMA) {
        graphifyFail('input is not docker-tools.docstruct/v1', 65);
    }

    $root = $sourceRootOverride ?? (string)($doc['root'] ?? '');
    if ($root === '') {
        graphifyFail('Graphify source root is missing', 65);
    }
    if (!str_starts_with(str_replace('\\', '/', $root), '/') && preg_match('~^[A-Za-z]:[\\\\/]~', $root) !== 1) {
        graphifyFail('Graphify source root must be absolute', 65);
    }

    $filePaths = [];
    foreach (($doc['files'] ?? []) as $file) {
        if (is_array($file) && is_string($file['path'] ?? null)) {
            $filePaths[$file['path']] = true;
        }
    }

    $nodes = [];
    $nodeMap = [];
    foreach (($doc['nodes'] ?? []) as $node) {
        if (!is_array($node) || !is_string($node['id'] ?? null)) {
            continue;
        }
        $converted = mechanicalNode($node, $root);
        if ($converted === null) {
            continue;
        }
        $nodeMap[$node['id']] = $converted['id'];
        $nodes[$converted['id']] = $converted;
    }

    $documentBySource = [];
    foreach (($doc['nodes'] ?? []) as $node) {
        if (
            is_array($node)
            && ($node['type'] ?? null) === 'document'
            && is_string($node['id'] ?? null)
            && is_string($node['source_file'] ?? null)
            && isset($nodeMap[$node['id']])
        ) {
            $documentBySource[$node['source_file']] = $nodeMap[$node['id']];
        }
    }

    $edges = [];
    foreach (($doc['edges'] ?? []) as $edge) {
        if (!is_array($edge)) {
            continue;
        }
        $sourceId = is_string($edge['source'] ?? null) ? $edge['source'] : '';
        $targetId = is_string($edge['target'] ?? null) ? $edge['target'] : '';
        $sourceFile = is_string($edge['source_file'] ?? null) ? $edge['source_file'] : '';
        $relation = is_string($edge['relation'] ?? null) ? $edge['relation'] : '';

        $mappedSource = $nodeMap[$sourceId] ?? ($documentBySource[$sourceFile] ?? null);
        $mappedTarget = $nodeMap[$targetId] ?? null;
        if ($mappedSource === null || $mappedTarget === null) {
            continue;
        }

        $graphifyRelation = $relation === 'contains' ? 'contains' : 'references';
        $key = implode('|', [$mappedSource, $mappedTarget, $graphifyRelation, $sourceFile]);
        $edges[$key] = [
            'source' => $mappedSource,
            'target' => $mappedTarget,
            'relation' => $graphifyRelation,
            'confidence' => 'EXTRACTED',
            'confidence_score' => 1.0,
            'source_file' => absoluteSource($root, $sourceFile),
            'source_location' => graphifyLocation(is_array($edge['evidence'] ?? null) ? $edge['evidence'] : []),
            'weight' => 1.0,
            'docstruct_origin' => DOCSTRUCT_GRAPHIFY_SCHEMA,
        ];
    }

    if ($review !== null) {
        if (($review['schema'] ?? null) !== DOCSTRUCT_REVIEW_SCHEMA) {
            graphifyFail('review input is not docker-tools.docstruct-review/v1', 65);
        }

        $rawDoc = file_get_contents((string)($GLOBALS['docstructInputPath'] ?? ''));
        if (!is_string($rawDoc)) {
            graphifyFail('unable to re-read docstruct input for review hash validation', 66);
        }
        $actualHash = hash('sha256', rtrim($rawDoc, "\n"));
        if (($review['base_sha256'] ?? null) !== $actualHash) {
            graphifyFail('review patch does not belong to this docstruct artifact', 65);
        }

        $patch = $review['patch'] ?? null;
        if (!is_array($patch)) {
            graphifyFail('review patch object is missing', 65);
        }

        $reviewMap = [];
        foreach (($patch['add_nodes'] ?? []) as $node) {
            if (!is_array($node)) {
                continue;
            }
            $source = (string)($node['source_file'] ?? '');
            $label = trim((string)($node['label'] ?? ''));
            $reviewId = (string)($node['id'] ?? '');
            if ($source === '' || $label === '' || $reviewId === '' || !isset($filePaths[$source])) {
                graphifyFail('review node is missing a valid id/label/source_file', 65);
            }

            $id = graphifyId($source, $label);
            $reviewMap[$reviewId] = $id;
            $fileType = reviewFileType((string)($node['type'] ?? 'concept'));
            $out = [
                'id' => $id,
                'label' => $label,
                'file_type' => $fileType,
                'source_file' => absoluteSource($root, $source),
                'source_location' => null,
                'source_url' => null,
                'captured_at' => null,
                'author' => null,
                'contributor' => null,
                'docstruct_origin' => DOCSTRUCT_GRAPHIFY_SCHEMA,
            ];
            $reason = trim((string)($node['reason'] ?? ''));
            if ($reason !== '') {
                $out['rationale'] = $reason;
            }
            $nodes[$id] = $out;
        }

        $allMap = $nodeMap + $reviewMap;
        foreach (($patch['add_edges'] ?? []) as $edge) {
            if (!is_array($edge)) {
                continue;
            }
            $source = (string)($edge['source'] ?? '');
            $target = (string)($edge['target'] ?? '');
            $relation = (string)($edge['relation'] ?? '');
            $sourceFile = (string)($edge['source_file'] ?? '');
            $confidence = (float)($edge['confidence'] ?? 0.0);
            if (
                !isset($allMap[$source], $allMap[$target], $filePaths[$sourceFile])
                || !allowedReviewRelation($relation)
            ) {
                graphifyFail('review edge cannot be represented safely in Graphify fragment', 65);
            }
            [$confidenceClass, $confidenceScore] = reviewConfidence($confidence);
            $key = implode('|', [$allMap[$source], $allMap[$target], $relation, $sourceFile]);
            $edges[$key] = [
                'source' => $allMap[$source],
                'target' => $allMap[$target],
                'relation' => $relation,
                'confidence' => $confidenceClass,
                'confidence_score' => $confidenceScore,
                'source_file' => absoluteSource($root, $sourceFile),
                'source_location' => null,
                'weight' => 1.0,
                'docstruct_origin' => DOCSTRUCT_GRAPHIFY_SCHEMA,
            ];
        }

        if (($patch['corrections'] ?? []) !== [] || ($patch['unresolved'] ?? []) !== []) {
            fwrite(
                STDERR,
                "docstruct graphify: review corrections/unresolved items remain in the review artifact; they are not silently converted into Graphify facts\n"
            );
        }
    }

    [$nodes, $edges] = canonicalizeGraphifyLocatedIdentity($nodes, $edges);
    ksort($nodes, SORT_STRING);
    ksort($edges, SORT_STRING);

    return [
        'nodes' => array_values($nodes),
        'edges' => array_values($edges),
        'hyperedges' => [],
        'input_tokens' => 0,
        'output_tokens' => 0,
    ];
}

/** @return array{input:string,review:?string,output:?string,source_root:?string,pretty:bool} */
function parseGraphifyArgs(array $argv): array
{
    $input = '';
    $review = null;
    $output = null;
    $sourceRoot = null;
    $pretty = true;

    for ($i = 1; $i < count($argv); $i++) {
        $arg = $argv[$i];
        if ($arg === '-h' || $arg === '--help') {
            echo "Usage: docstruct graphify <docstruct.json> [--review <docstruct-review.json>] [--source-root <host-root>] [--output <file>] [--compact]\n";
            exit(0);
        }
        if ($arg === '--review') {
            $review = $argv[++$i] ?? graphifyFail('--review requires a file');
            continue;
        }
        if ($arg === '--output') {
            $output = $argv[++$i] ?? graphifyFail('--output requires a file');
            continue;
        }
        if ($arg === '--source-root') {
            $sourceRoot = $argv[++$i] ?? graphifyFail('--source-root requires a path');
            if ($sourceRoot === '') {
                graphifyFail('--source-root cannot be empty');
            }
            continue;
        }
        if ($arg === '--compact') {
            $pretty = false;
            continue;
        }
        if (str_starts_with($arg, '-')) {
            graphifyFail("unknown option: {$arg}");
        }
        if ($input !== '') {
            graphifyFail('only one docstruct input file may be supplied');
        }
        $input = $arg;
    }

    if ($input === '') {
        graphifyFail('a docstruct JSON input is required');
    }

    return ['input' => $input, 'review' => $review, 'output' => $output, 'source_root' => $sourceRoot, 'pretty' => $pretty];
}

$options = parseGraphifyArgs($argv);
$GLOBALS['docstructInputPath'] = $options['input'];
$doc = readJsonObject($options['input'], 'docstruct input');
$review = $options['review'] !== null ? readJsonObject($options['review'], 'review input') : null;
$fragment = buildGraphifyFragment($doc, $review, $options['source_root']);

$flags = JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE;
if ($options['pretty']) {
    $flags |= JSON_PRETTY_PRINT;
}
$json = json_encode($fragment, $flags | JSON_THROW_ON_ERROR) . "\n";

if ($options['output'] !== null) {
    if (file_put_contents($options['output'], $json) === false) {
        graphifyFail("unable to write output: {$options['output']}", 73);
    }
} else {
    echo $json;
}
