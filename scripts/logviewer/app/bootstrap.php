<?php
declare(strict_types=1);

require_once __DIR__ . '/../src/Core/Errors.php';
require_once __DIR__ . '/../src/Core/App.php';

use LogViewer\Core\App;

return App::bootstrap(dirname(__DIR__));
