<?php
declare(strict_types=1);

$path = (string)(parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH) ?: '/');
$modeFile = (string)(getenv('FAKE_LLM_MODE_FILE') ?: getenv('FAKE_OLLAMA_MODE_FILE') ?: '');
$captureFile = (string)(getenv('FAKE_LLM_CAPTURE_FILE') ?: getenv('FAKE_OLLAMA_CAPTURE_FILE') ?: '');
$mode = ($modeFile !== '' && is_file($modeFile)) ? trim((string)file_get_contents($modeFile)) : 'single';

header('Content-Type: application/json');

if ($path === '/v1/models') {
    if ($mode === 'models-503' || $mode === 'tags-503') {
        http_response_code(503);
        echo json_encode(['error' => ['message' => 'unavailable']], JSON_UNESCAPED_SLASHES);
        return;
    }
    if ($mode === 'malformed-models' || $mode === 'malformed-tags') {
        echo '{not-json';
        return;
    }
    if ($mode === 'ambiguous') {
        echo json_encode(['object' => 'list', 'data' => [
            ['id' => 'qwen2.5:3b', 'object' => 'model'],
            ['id' => 'llama3.2:3b', 'object' => 'model'],
        ]], JSON_UNESCAPED_SLASHES);
        return;
    }
    if ($mode === 'none') {
        echo json_encode(['object' => 'list', 'data' => []], JSON_UNESCAPED_SLASHES);
        return;
    }
    echo json_encode(['object' => 'list', 'data' => [
        ['id' => 'qwen2.5:3b', 'object' => 'model'],
    ]], JSON_UNESCAPED_SLASHES);
    return;
}

if ($path !== '/v1/chat/completions') {
    http_response_code(404);
    echo json_encode(['error' => ['message' => 'not found']], JSON_UNESCAPED_SLASHES);
    return;
}

$body = (string)file_get_contents('php://input');
if ($captureFile !== '') {
    file_put_contents($captureFile, base64_encode($body) . "\n", FILE_APPEND | LOCK_EX);
}
$request = json_decode($body, true);
if (!is_array($request)) {
    http_response_code(400);
    echo json_encode(['error' => ['message' => 'bad request']], JSON_UNESCAPED_SLASHES);
    return;
}

if ($mode === 'slow-generation') {
    sleep(2);
}
if ($mode === 'oversize-response') {
    echo json_encode([
        'choices' => [['message' => ['role' => 'assistant', 'content' => str_repeat('x', 9000)]]],
    ], JSON_UNESCAPED_SLASHES);
    return;
}
if ($mode === 'malformed-generation') {
    echo '{bad-json';
    return;
}

$messages = $request['messages'] ?? [];
$system = '';
foreach ($messages as $message) {
    if (($message['role'] ?? '') === 'system') {
        $system .= (string)($message['content'] ?? '');
    }
}
$jsonMode = str_contains($system, 'Return exactly one valid JSON value');

if (($request['stream'] ?? false) === true) {
    header('Content-Type: text/event-stream');
    echo 'data: ' . json_encode([
        'choices' => [['delta' => ['content' => 'hello ']]],
    ], JSON_UNESCAPED_SLASHES) . "\n\n";
    @ob_flush();
    flush();

    if ($mode === 'broken-stream') {
        echo "data: not-json\n\n";
        @ob_flush();
        flush();
        return;
    }

    echo 'data: ' . json_encode([
        'choices' => [['delta' => ['content' => 'world']]],
    ], JSON_UNESCAPED_SLASHES) . "\n\n";
    echo "data: [DONE]\n\n";
    @ob_flush();
    flush();
    return;
}

$content = $jsonMode ? json_encode(['ok' => true], JSON_UNESCAPED_SLASHES) : 'ok';
echo json_encode([
    'id' => 'chatcmpl-mock',
    'object' => 'chat.completion',
    'choices' => [['index' => 0, 'message' => ['role' => 'assistant', 'content' => $content]]],
], JSON_UNESCAPED_SLASHES);
