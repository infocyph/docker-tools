<?php

declare(strict_types=1);

require_once __DIR__ . '/../bootstrap.php';

$activePage = 'dashboard';
$pageTitle  = 'Dashboard';

$domains      = nginx_domains_list($NGINX_VHOST_DIR);
$domainCount  = count($domains);

$logCounts    = log_file_counts_by_dirname($LOGVIEW_ROOTS);
$logFileTotal = (int)($logCounts['total'] ?? 0);
$serviceCount = count((array)($logCounts['by_dir'] ?? []));

$systemDomains = [
  'admin.localhost',
  'webmail.localhost',
  'db.localhost',
  'ri.localhost',
  'me.localhost',
  'kibana.localhost',
];

require_once __DIR__ . '/_layout_top.php';
?>

  <div class="row g-3">

    <!-- Top Status Tiles -->
    <div class="col-12">
      <div class="card lv-card">
        <div class="card-body">
          <div class="d-flex flex-wrap gap-3">

            <div class="lv-stat">
              <div class="lv-muted small">Domains</div>
              <div class="lv-stat-value"><?= (int)$domainCount ?></div>
            </div>

            <div class="lv-stat">
              <div class="lv-muted small">Log Files</div>
              <div class="lv-stat-value"><?= (int)$logFileTotal ?></div>
            </div>

            <div class="lv-stat">
              <div class="lv-muted small">Services</div>
              <div class="lv-stat-value"><?= (int)$serviceCount ?></div>
            </div>

          </div>
        </div>
      </div>
    </div>

    <!-- Project Domains -->
    <div class="col-12 col-lg-4">
      <div class="card lv-card h-100">
        <div class="card-header lv-card-header d-flex align-items-center justify-content-between">
          <div class="fw-semibold">Project Domains</div>
          <span class="badge text-bg-secondary"><?= (int)$domainCount ?></span>
        </div>

        <div class="card-body p-0">
          <?php if ($domainCount === 0): ?>
            <div class="p-3 lv-muted">No domains found.</div>
          <?php else: ?>
            <div class="lv-domain-list">
              <?php foreach ($domains as $d): ?>
                <a class="lv-domain-item"
                   href="http://<?= htmlspecialchars($d, ENT_QUOTES, 'UTF-8') ?>"
                   target="_blank"
                   rel="noopener">
                  <?= htmlspecialchars($d, ENT_QUOTES, 'UTF-8') ?>
                </a>
              <?php endforeach; ?>
            </div>
          <?php endif; ?>
        </div>
      </div>
    </div>

    <!-- System Containers -->
    <div class="col-12 col-lg-4">
      <div class="card lv-card h-100">
        <div class="card-header lv-card-header d-flex align-items-center justify-content-between">
          <div class="fw-semibold">System Containers</div>
          <span class="badge text-bg-secondary"><?= (int)count($systemDomains) ?></span>
        </div>

        <div class="card-body p-0">
          <div class="lv-domain-list">
            <?php foreach ($systemDomains as $d): ?>
              <a class="lv-domain-item"
                 href="http://<?= htmlspecialchars($d, ENT_QUOTES, 'UTF-8') ?>"
                 target="_blank"
                 rel="noopener">
                <?= htmlspecialchars($d, ENT_QUOTES, 'UTF-8') ?>
              </a>
            <?php endforeach; ?>
          </div>
        </div>
      </div>
    </div>

    <!-- Log Services -->
    <div class="col-12 col-lg-4">
      <div class="card lv-card h-100">
        <div class="card-header lv-card-header d-flex align-items-center justify-content-between">
          <div class="fw-semibold">Log Services</div>
          <span class="badge text-bg-secondary"><?= (int)$serviceCount ?></span>
        </div>

        <div class="card-body p-0">
          <?php if ($serviceCount === 0): ?>
            <div class="p-3 lv-muted">No log services found.</div>
          <?php else: ?>
            <div class="lv-domain-list">
              <?php foreach (($logCounts['by_dir'] ?? []) as $dir => $cnt): ?>
                <div class="d-flex align-items-center justify-content-between px-3 py-2 border-bottom"
                     style="border-color: var(--lv-card-border) !important;">
                  <div><?= htmlspecialchars((string)$dir, ENT_QUOTES, 'UTF-8') ?></div>
                  <span class="badge text-bg-secondary"><?= (int)$cnt ?></span>
                </div>
              <?php endforeach; ?>
            </div>
          <?php endif; ?>
        </div>

        <div class="card-footer lv-card-footer">
          <a class="btn btn-sm lv-btn w-100" href="/?p=logs">Open Log Viewer</a>
        </div>
      </div>
    </div>

  </div>

  <script src="/assets/js/dashboard.js"></script>
<?php require_once __DIR__ . '/_layout_bottom.php'; ?>

