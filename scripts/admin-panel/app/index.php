<?php
declare(strict_types=1);

$page = isset($_GET['p']) ? (string)$_GET['p'] : 'dashboard';
$allowed = [
    'dashboard' => 'dashboard',
];
if (!isset($allowed[$page])) {
    $page = 'dashboard';
}

$activePage = $page;
$pageTitle = match ($page) {
    'dashboard' => 'Admin Panel',
    default => 'Admin Panel',
};

require __DIR__ . '/pages/_layout_top.php';
require __DIR__ . '/pages/' . $allowed[$page] . '.php';
require __DIR__ . '/pages/_layout_bottom.php';

