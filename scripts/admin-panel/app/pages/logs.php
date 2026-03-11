<?php
declare(strict_types=1);

$logFiles = [
    ['file' => 'nginx/error.log', 'level' => 'error', 'updated' => '2 min ago', 'size' => '18.4 MB'],
    ['file' => 'nginx/access.log', 'level' => 'info', 'updated' => 'just now', 'size' => '42.1 MB'],
    ['file' => 'php-fpm/www-error.log', 'level' => 'warn', 'updated' => '6 min ago', 'size' => '7.9 MB'],
    ['file' => 'queue/worker.log', 'level' => 'info', 'updated' => '1 min ago', 'size' => '11.2 MB'],
];
?>

<section class="ap-page-head">
  <div>
    <p class="ap-breadcrumb mb-1">Home / Logs</p>
    <h2 class="ap-page-title mb-1">Log Streams</h2>
    <p class="ap-page-sub mb-0">Quick access to service logs. Full stream tooling will be attached next.</p>
  </div>
  <div class="d-flex align-items-center gap-2 flex-wrap">
    <button class="btn ap-ghost-btn" type="button" disabled><i class="bi bi-arrow-repeat me-1"></i> Refresh</button>
    <button class="btn ap-primary-btn" type="button" disabled><i class="bi bi-download me-1"></i> Export</button>
  </div>
</section>

<section class="row g-3 mt-1">
  <div class="col-12 col-xxl-8">
    <article class="card ap-card h-100">
      <header class="card-header ap-card-head">
        <div>
          <h4 class="ap-card-title mb-1">Recent Log Files</h4>
          <p class="ap-card-sub mb-0">Mapped URL route: `/logs`</p>
        </div>
      </header>
      <div class="table-responsive">
        <table class="table ap-table mb-0">
          <thead>
          <tr>
            <th>File</th>
            <th>Level</th>
            <th>Updated</th>
            <th class="text-end">Size</th>
          </tr>
          </thead>
          <tbody>
          <?php foreach ($logFiles as $row): ?>
            <tr>
              <td class="fw-semibold"><?= htmlspecialchars($row['file'], ENT_QUOTES, 'UTF-8') ?></td>
              <td><?= htmlspecialchars(strtoupper($row['level']), ENT_QUOTES, 'UTF-8') ?></td>
              <td><?= htmlspecialchars($row['updated'], ENT_QUOTES, 'UTF-8') ?></td>
              <td class="text-end"><?= htmlspecialchars($row['size'], ENT_QUOTES, 'UTF-8') ?></td>
            </tr>
          <?php endforeach; ?>
          </tbody>
        </table>
      </div>
    </article>
  </div>

  <div class="col-12 col-xxl-4">
    <article class="card ap-card h-100">
      <header class="card-header ap-card-head">
        <div>
          <h4 class="ap-card-title mb-1">Status</h4>
          <p class="ap-card-sub mb-0">Router and navigation check</p>
        </div>
      </header>
      <div class="card-body">
        <ul class="ap-status-list list-unstyled mb-0">
          <li class="ap-status-row">
            <p class="ap-status-label mb-1">Route</p>
            <p class="ap-page-sub mb-0">`admin.localhost/logs`</p>
          </li>
          <li class="ap-status-row">
            <p class="ap-status-label mb-1">Template</p>
            <p class="ap-page-sub mb-0">`app/pages/logs.php`</p>
          </li>
          <li class="ap-status-row">
            <p class="ap-status-label mb-1">Data Source</p>
            <p class="ap-page-sub mb-0">Placeholder seed data</p>
          </li>
        </ul>
      </div>
    </article>
  </div>
</section>
