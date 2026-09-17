<?php
declare(strict_types=1);

$path = (string)(parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH) ?: '/');
$modeFile = (string)(getenv('FAKE_OLLAMA_MODE_FILE') ?: '');
$captureFile = (string)(getenv('FAKE_OLLAMA_CAPTURE_FILE') ?: '');
$mode = ($modeFile !== '' && is_file($modeFile)) ? trim((string)file_get_contents($modeFile)) : 'single';

header('Content-Type: application/json');

if ($path === '/api/tags') {
    if ($mode === 'tags-503') {
        http_response_code(503);
        echo json_encode(['error' => 'unavailable'], JSON_UNESCAPED_SLASHES);
        return;
    }
    if ($mode === 'malformed-tags') {
        echo '{not-json';
        return;
    }
    if ($mode === 'ambiguous') {
        echo json_encode(['models' => [['name' => 'qwen2.5:3b'], ['name' => 'llama3.2:3b']]], JSON_UNESCAPED_SLASHES);
        return;
    }
    if ($mode === 'none') {
        echo json_encode(['models' => []], JSON_UNESCAPED_SLASHES);
        return;
    }
    echo json_encode(['models' => [['name' => 'qwen2.5:3b']]], JSON_UNESCAPED_SLASHES);
    return;
}

if ($path !== '/api/generate') {
    http_response_code(404);
    echo json_encode(['error' => 'not found'], JSON_UNESCAPED_SLASHES);
    return;
}

$body = (string)file_get_contents('php://input');
if ($captureFile !== '') {
    file_put_contents($captureFile, base64_encode($body) . "\n", FILE_APPEND | LOCK_EX);
}
$request = json_decode($body, true);
if (!is_array($request)) {
    http_response_code(400);
    echo json_encode(['error' => 'bad request'], JSON_UNESCAPED_SLASHES);
    return;
}

if ($mode === 'slow-generation') {
    sleep(2);
}
if ($mode === 'oversize-response') {
    echo json_encode(['response' => str_repeat('x', 9000), 'done' => true], JSON_UNESCAPED_SLASHES);
    return;
}
if ($mode === 'malformed-generation') {
    echo '{bad-json';
    return;
}

if (($request['stream'] ?? false) === true) {
    echo json_encode(['response' => 'hello ', 'done' => false], JSON_UNESCAPED_SLASHES) . "\n";
    @ob_flush();
    flush();
    if ($mode === 'broken-stream') {
        echo "not-json\n";
        @ob_flush();
        flush();
        return;
    }
    echo json_encode(['response' => 'world', 'done' => true], JSON_UNESCAPED_SLASHES) . "\n";
    @ob_flush();
    flush();
    return;
}

if (($request['format'] ?? '') === 'json') {
    echo json_encode(['response' => json_encode(['ok' => true], JSON_UNESCAPED_SLASHES), 'done' => true], JSON_UNESCAPED_SLASHES);
    return;
}

echo json_encode(['response' => 'ok', 'done' => true], JSON_UNESCAPED_SLASHES);
