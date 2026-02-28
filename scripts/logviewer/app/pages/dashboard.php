<?php

declare(strict_types=1);
require __DIR__ . '/_layout_top.php';
?>

  <div class="row g-3">

    <!-- Top status -->
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

        <?php if ($domainCount === 0): ?>
          <div class="card-body lv-muted">No domains found.</div>
        <?php else: ?>
          <div class="list-group list-group-flush">
            <?php foreach ($domains as $d): ?>
              <a class="list-group-item list-group-item-action"
                 href="http://<?= htmlspecialchars($d, ENT_QUOTES, 'UTF-8') ?>"
                 target="_blank"
                 rel="noopener"
                 style="background: transparent; color: inherit;">
                <?= htmlspecialchars($d, ENT_QUOTES, 'UTF-8') ?>
              </a>
            <?php endforeach; ?>
          </div>
        <?php endif; ?>
      </div>
    </div>

    <!-- System Containers -->
    <div class="col-12 col-lg-4">
      <div class="card lv-card h-100">
        <div class="card-header lv-card-header d-flex align-items-center justify-content-between">
          <div class="fw-semibold">System Containers</div>
          <span class="badge text-bg-secondary"><?= (int)count($systemDomains) ?></span>
        </div>

        <div class="list-group list-group-flush">
          <?php foreach ($systemDomains as $name => $d): ?>
            <a class="list-group-item list-group-item-action"
               href="http://<?= htmlspecialchars($d, ENT_QUOTES, 'UTF-8') ?>"
               target="_blank"
               rel="noopener"
               style="background: transparent; color: inherit;">
              <?= htmlspecialchars($name, ENT_QUOTES, 'UTF-8') ?>
            </a>
          <?php endforeach; ?>
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

        <?php if ($serviceCount === 0): ?>
          <div class="card-body lv-muted">No log services found.</div>
        <?php else: ?>
          <div class="list-group list-group-flush">
            <?php foreach (($logCounts['by_dir'] ?? []) as $dir => $cnt): ?>
              <div class="list-group-item d-flex align-items-center justify-content-between"
                   style="background: transparent; color: inherit;">
                <div><?= htmlspecialchars((string)$dir, ENT_QUOTES, 'UTF-8') ?></div>
                <span class="badge text-bg-secondary"><?= (int)$cnt ?></span>
              </div>
            <?php endforeach; ?>
          </div>
        <?php endif; ?>

        <div class="card-footer lv-card-footer">
          <a class="btn btn-sm lv-btn w-100" href="/?p=logs">Open Log Viewer</a>
        </div>
      </div>
    </div>

  </div>

  <script src="/assets/js/dashboard.js"></script>
<?php require __DIR__ . '/_layout_bottom.php'; ?>
