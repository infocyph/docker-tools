<?php
declare(strict_types=1);

require __DIR__ . '/bootstrap.php';

$kernel = new \AdminPanel\App\Kernel(__DIR__);
$kernel->handle($_SERVER, $_GET);
