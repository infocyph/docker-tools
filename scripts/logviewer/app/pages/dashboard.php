<?php
declare(strict_types=1);

require_once __DIR__ . '/../bootstrap.php';

$activePage = 'dashboard';
$pageTitle  = 'Dashboard';

$domains     = nginx_domains_list($NGINX_VHOST_DIR);
$domainCount = count($domains);

// NEW: simple log file counts (total + by first-level directory/service)
$logCounts = log_file_counts_by_dirname($LOGVIEW_ROOTS);

require_once __DIR__ . '/_layout_top.php';
?>

  <div class="row g-3">
    <div class="col-12 col-lg-4">
      <div class="card lv-card">
        <div class="card-header lv-card-header d-flex align-items-center justify-content-between">
          <div class="fw-semibold">Domains</div>
          <span class="badge text-bg-secondary"><?= (int)$domainCount ?></span>
        </div>

        <div class="card-body">
          <?php if ($domainCount === 0): ?>
            <div class="lv-muted">No domains found.</div>
          <?php else: ?>
            <div class="d-flex flex-wrap gap-2">
              <?php foreach ($domains as $d): ?>
                <a class="btn btn-sm lv-btn" href="/?p=logs&domain=<?= urlencode($d) ?>">
                  <?= htmlspecialchars($d, ENT_QUOTES, 'UTF-8') ?>
                </a>
              <?php endforeach; ?>
            </div>
          <?php endif; ?>
        </div>
      </div>
    </div>

    <div class="col-12 col-lg-8">
      <div class="card lv-card">
        <div class="card-header lv-card-header d-flex align-items-center justify-content-between">
          <div class="fw-semibold">Log Stats Summary</div>
          <span class="badge text-bg-secondary"><?= (int)($logCounts['total'] ?? 0) ?> files</span>
        </div>

        <div class="card-body">
          <?php if ((int)($logCounts['total'] ?? 0) === 0): ?>
            <div class="lv-muted">No log files found.</div>
          <?php else: ?>
            <div class="d-flex flex-wrap gap-2">
              <?php foreach (($logCounts['by_dir'] ?? []) as $dir => $cnt): ?>
                <span class="btn btn-sm lv-btn" style="pointer-events:none;">
                <?= htmlspecialchars((string)$dir, ENT_QUOTES, 'UTF-8') ?>
                <span class="badge ms-1"><?= (int)$cnt ?></span>
              </span>
              <?php endforeach; ?>
            </div>
          <?php endif; ?>

          <div class="mt-3">
            <a class="btn btn-sm lv-btn" href="/?p=logs">Open Log Viewer</a>
          </div>
        </div>
      </div>
    </div>
  </div>

  <script src="/assets/js/dashboard.js"></script>
<?php require __DIR__ . '/_layout_bottom.php'; ?>