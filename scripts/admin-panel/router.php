<?php
declare(strict_types=1);

$requestUri = (string)($_SERVER['REQUEST_URI'] ?? '/');
$requestPath = (string)(parse_url($requestUri, PHP_URL_PATH) ?? '/');
$decodedPath = '/' . ltrim(str_replace('\\', '/', rawurldecode($requestPath)), '/');

$docRoot = realpath(__DIR__);
$publicRoot = realpath(__DIR__ . '/public');
$target = realpath(__DIR__ . $decodedPath);
$isRootStatic = in_array($decodedPath, ['/favicon.ico', '/robots.txt'], true);

if (
    is_string($docRoot)
    && is_string($target)
    && str_starts_with($target, $docRoot)
    && is_file($target)
    && (
        ($isRootStatic)
        || (is_string($publicRoot) && str_starts_with($target, $publicRoot))
    )
) {
    return false;
}

require __DIR__ . '/index.php';
