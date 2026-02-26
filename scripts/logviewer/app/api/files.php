<?php
declare(strict_types=1);

require_once __DIR__ . '/../bootstrap.php';

$files = list_files($LOGVIEW_ROOTS);

json_out([
  'ok'    => true,
  'files' => $files,
  'meta'  => [
    'total'        => count($files),
    'generated_at' => time(),
  ],
]);