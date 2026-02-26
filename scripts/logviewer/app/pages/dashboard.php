<?php
declare(strict_types=1);

require_once __DIR__ . '/../bootstrap.php';

$activePage = 'dashboard';
$pageTitle  = 'Dashboard';

$domains      = nginx_domains_list($NGINX_VHOST_DIR);
$domainCount  = count($domains);

$logCounts    = log_file_counts_by_dirname($LOGVIEW_ROOTS);
$totalLogs    = (int)($logCounts['total'] ?? 0);
$serviceCount = count($logCounts['by_dir'] ?? []);

require_once __DIR__ . '/_layout_top.php';
?>

  <div class="row g-3">

    <!-- Status Capsules -->
    <div class="col-12">
      <div class="card lv-card">
        <div class="card-body">
          <div class="d-flex flex-wrap gap-3">

            <div class="lv-stat">
              <div class="lv-stat-label">Domains</div>
              <div class="lv-stat-value"><?= $domainCount ?></div>
            </div>

            <div class="lv-stat">
              <div class="lv-stat-label">Log Files</div>
              <div class="lv-stat-value"><?= $totalLogs ?></div>
            </div>

            <div class="lv-stat">
              <div class="lv-stat-label">Services</div>
              <div class="lv-stat-value"><?= $serviceCount ?></div>
            </div>

          </div>
        </div>
      </div>
    </div>

    <!-- 3 Column Layout -->

    <!-- Project Domains -->
    <div class="col-12 col-lg-4">
      <div class="card lv-card h-100">
        <div class="card-header lv-card-header fw-semibold">
          Project Domains
        </div>
        <div class="card-body p-0">
          <div class="lv-domain-list">
            <?php if (!$domains): ?>
              <div class="p-3 lv-muted">No domains found.</div>
            <?php else: ?>
              <?php foreach ($domains as $d): ?>
                <a class="lv-domain-item"
                   href="http://<?= htmlspecialchars($d) ?>"
                   target="_blank" rel="noopener">
                  <?= htmlspecialchars($d) ?>
                </a>
              <?php endforeach; ?>
            <?php endif; ?>
          </div>
        </div>
      </div>
    </div>

    <!-- System Domains -->
    <div class="col-12 col-lg-4">
      <div class="card lv-card h-100">
        <div class="card-header lv-card-header fw-semibold">
          System Containers
        </div>
        <div class="card-body p-0">
          <div class="lv-domain-list">
            <?php
            $systemDomains = [
              'admin.localhost',
              'webmail.localhost',
              'db.localhost',
              'ri.localhost',
              'me.localhost',
              'kibana.localhost',
            ];
            foreach ($systemDomains as $sd): ?>
              <a class="lv-domain-item"
                 href="http://<?= $sd ?>"
                 target="_blank" rel="noopener">
                <?= $sd ?>
              </a>
            <?php endforeach; ?>
          </div>
        </div>
      </div>
    </div>

    <!-- Log Services -->
    <div class="col-12 col-lg-4">
      <div class="card lv-card h-100">
        <div class="card-header lv-card-header fw-semibold">
          Log Services
        </div>
        <div class="card-body">

          <?php if (!$serviceCount): ?>
            <div class="lv-muted">No logs detected.</div>
          <?php else: ?>
            <div class="d-flex flex-column gap-2">
              <?php foreach ($logCounts['by_dir'] as $dir => $cnt): ?>
                <div class="d-flex justify-content-between align-items-center lv-service-row">
                  <div><?= htmlspecialchars($dir) ?></div>
                  <span class="badge bg-secondary"><?= $cnt ?></span>
                </div>
              <?php endforeach; ?>
            </div>
          <?php endif; ?>

          <div class="mt-3">
            <a class="btn btn-sm lv-btn w-100" href="/?p=logs">
              Open Log Viewer
            </a>
          </div>

        </div>
      </div>
    </div>

  </div>

  <script src="/assets/js/dashboard.js"></script>
<?php require __DIR__ . '/_layout_bottom.php'; ?>

