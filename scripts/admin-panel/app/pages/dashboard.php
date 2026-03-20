<?php
declare(strict_types=1);

$kpis = [
    ['label' => 'Monthly Revenue', 'value' => '$87,460', 'delta' => '+11.3%', 'state' => 'up', 'icon' => 'bi-cash-coin'],
    ['label' => 'Active Projects', 'value' => '126', 'delta' => '+7', 'state' => 'up', 'icon' => 'bi-kanban'],
    ['label' => 'Containers Healthy', 'value' => '23 / 24', 'delta' => '95.8%', 'state' => 'up', 'icon' => 'bi-hdd-network'],
    ['label' => 'Error Rate', 'value' => '0.43%', 'delta' => '-0.12%', 'state' => 'down', 'icon' => 'bi-exclamation-triangle'],
];

$trafficSources = [
    ['name' => 'Proxy Requests', 'value' => '46%'],
    ['name' => 'Direct App Hits', 'value' => '28%'],
    ['name' => 'CLI Triggers', 'value' => '17%'],
    ['name' => 'Scheduled Jobs', 'value' => '9%'],
];

$recentDeployments = [
    ['id' => '#DEP-2104', 'service' => 'nginx-router', 'owner' => 'platform', 'status' => 'Completed', 'time' => '3 min ago'],
    ['id' => '#DEP-2103', 'service' => 'php-fpm-main', 'owner' => 'runtime', 'status' => 'Processing', 'time' => '12 min ago'],
    ['id' => '#DEP-2102', 'service' => 'worker-queue', 'owner' => 'jobs', 'status' => 'Failed', 'time' => '28 min ago'],
    ['id' => '#DEP-2101', 'service' => 'redis-cache', 'owner' => 'platform', 'status' => 'Completed', 'time' => '53 min ago'],
];

$healthRows = [
    ['service' => 'Nginx', 'status' => 'Healthy', 'uptime' => '99.99%', 'load' => 92],
    ['service' => 'PHP-FPM', 'status' => 'Healthy', 'uptime' => '99.82%', 'load' => 76],
    ['service' => 'MySQL', 'status' => 'Healthy', 'uptime' => '99.91%', 'load' => 68],
    ['service' => 'Redis', 'status' => 'Warning', 'uptime' => '98.45%', 'load' => 54],
];

$timeline = [
    ['time' => '19:04', 'text' => 'Project profile switched to `team-a` by admin.'],
    ['time' => '18:42', 'text' => 'Container `worker-queue` restarted after memory threshold warning.'],
    ['time' => '18:13', 'text' => 'Vhost map refreshed from `sites-enabled` (12 domains).'],
    ['time' => '17:57', 'text' => 'New log archive generated for `api.error.log`.'],
];
?>

<section class="ap-page-head">
  <div>
    <p class="ap-breadcrumb mb-1">Home / Dashboard</p>
    <h2 class="ap-page-title mb-1">Operations Overview</h2>
    <p class="ap-page-sub mb-0">TailAdmin-style summary shell for LDS runtime and deployment health.</p>
  </div>
  <div class="d-flex align-items-center gap-2 flex-wrap">
    <button class="btn ap-ghost-btn" type="button" disabled><i class="bi bi-calendar3 me-1"></i> Last 30 Days</button>
    <button class="btn ap-primary-btn" type="button" disabled><i class="bi bi-plus-lg me-1"></i> New Deployment</button>
  </div>
</section>

<section class="row g-3 mt-1">
  <?php foreach ($kpis as $kpi): ?>
    <div class="col-12 col-sm-6 col-xxl-3">
      <article class="card ap-card ap-kpi-card h-100">
        <div class="card-body">
          <div class="d-flex justify-content-between align-items-start">
            <div>
              <p class="ap-kpi-label mb-1"><?= htmlspecialchars($kpi['label'], ENT_QUOTES, 'UTF-8') ?></p>
              <h3 class="ap-kpi-value mb-1"><?= htmlspecialchars($kpi['value'], ENT_QUOTES, 'UTF-8') ?></h3>
              <p class="ap-kpi-meta mb-0">
                <span class="ap-kpi-trend ap-<?= htmlspecialchars($kpi['state'], ENT_QUOTES, 'UTF-8') ?>">
                  <?= $kpi['state'] === 'up' ? '<i class="bi bi-arrow-up-right"></i>' : '<i class="bi bi-arrow-down-right"></i>' ?>
                </span>
                <?= htmlspecialchars($kpi['delta'], ENT_QUOTES, 'UTF-8') ?>
              </p>
            </div>
            <div class="ap-kpi-icon">
              <i class="bi <?= htmlspecialchars($kpi['icon'], ENT_QUOTES, 'UTF-8') ?>"></i>
            </div>
          </div>
        </div>
      </article>
    </div>
  <?php endforeach; ?>
</section>

<section class="row g-3 mt-1">
  <div class="col-12 col-xxl-8">
    <article class="card ap-card h-100">
      <header class="card-header ap-card-head">
        <div>
          <h4 class="ap-card-title mb-1">Revenue Analytics</h4>
          <p class="ap-card-sub mb-0">Monthly flow from all service tiers</p>
        </div>
        <button class="btn ap-ghost-btn btn-sm" type="button" disabled>View Report</button>
      </header>
      <div class="card-body">
        <div class="ap-chart-wrap">
          <canvas id="apRevenueChart" height="128" aria-label="Revenue chart"></canvas>
        </div>
      </div>
    </article>
  </div>

  <div class="col-12 col-xxl-4">
    <article class="card ap-card h-100">
      <header class="card-header ap-card-head">
        <div>
          <h4 class="ap-card-title mb-1">Traffic Sources</h4>
          <p class="ap-card-sub mb-0">Live routing entry points</p>
        </div>
      </header>
      <div class="card-body">
        <div class="ap-chart-wrap ap-chart-sm">
          <canvas id="apTrafficChart" height="188" aria-label="Traffic sources chart"></canvas>
        </div>
        <ul class="ap-legend-list list-unstyled mb-0 mt-3">
          <?php foreach ($trafficSources as $item): ?>
            <li>
              <span class="ap-legend-label"><?= htmlspecialchars($item['name'], ENT_QUOTES, 'UTF-8') ?></span>
              <strong class="ap-legend-value"><?= htmlspecialchars($item['value'], ENT_QUOTES, 'UTF-8') ?></strong>
            </li>
          <?php endforeach; ?>
        </ul>
      </div>
    </article>
  </div>
</section>

<section class="row g-3 mt-1">
  <div class="col-12 col-xxl-8">
    <article class="card ap-card h-100">
      <header class="card-header ap-card-head">
        <div>
          <h4 class="ap-card-title mb-1">Recent Deployments</h4>
          <p class="ap-card-sub mb-0">Latest build and rollout queue events</p>
        </div>
      </header>
      <div class="table-responsive">
        <table class="table ap-table mb-0">
          <thead>
            <tr>
              <th>Deployment</th>
              <th>Service</th>
              <th>Owner</th>
              <th>Status</th>
              <th class="text-end">Time</th>
            </tr>
          </thead>
          <tbody>
          <?php foreach ($recentDeployments as $row): ?>
            <tr>
              <td class="fw-semibold"><?= htmlspecialchars($row['id'], ENT_QUOTES, 'UTF-8') ?></td>
              <td><?= htmlspecialchars($row['service'], ENT_QUOTES, 'UTF-8') ?></td>
              <td><?= htmlspecialchars($row['owner'], ENT_QUOTES, 'UTF-8') ?></td>
              <td>
                <?php $statusClass = strtolower((string)$row['status']); ?>
                <span class="ap-badge ap-badge-<?= htmlspecialchars($statusClass, ENT_QUOTES, 'UTF-8') ?>">
                  <?= htmlspecialchars($row['status'], ENT_QUOTES, 'UTF-8') ?>
                </span>
              </td>
              <td class="text-end"><?= htmlspecialchars($row['time'], ENT_QUOTES, 'UTF-8') ?></td>
            </tr>
          <?php endforeach; ?>
          </tbody>
        </table>
      </div>
    </article>
  </div>

  <div class="col-12 col-xxl-4">
    <div class="row g-3">
      <div class="col-12">
        <article class="card ap-card h-100">
          <header class="card-header ap-card-head">
            <div>
              <h4 class="ap-card-title mb-1">Order Status</h4>
              <p class="ap-card-sub mb-0">Automation job outcomes</p>
            </div>
          </header>
          <div class="card-body">
            <div class="ap-chart-wrap ap-chart-sm">
              <canvas id="apOrderStatusChart" height="170" aria-label="Order status chart"></canvas>
            </div>
          </div>
        </article>
      </div>

      <div class="col-12">
        <article class="card ap-card h-100">
          <header class="card-header ap-card-head">
            <div>
              <h4 class="ap-card-title mb-1">Service Health</h4>
              <p class="ap-card-sub mb-0">Current host and workload reliability</p>
            </div>
          </header>
          <div class="card-body">
            <ul class="ap-status-list list-unstyled mb-0">
              <?php foreach ($healthRows as $row): ?>
                <li class="ap-status-row">
                  <div class="d-flex justify-content-between align-items-end mb-2">
                    <div>
                      <p class="ap-status-label mb-0"><?= htmlspecialchars($row['service'], ENT_QUOTES, 'UTF-8') ?></p>
                      <small class="ap-status-kicker"><?= htmlspecialchars($row['status'], ENT_QUOTES, 'UTF-8') ?></small>
                    </div>
                    <strong><?= htmlspecialchars($row['uptime'], ENT_QUOTES, 'UTF-8') ?></strong>
                  </div>
                  <div class="ap-progress">
                    <span class="ap-progress-bar" style="width: <?= (int)$row['load'] ?>%"></span>
                  </div>
                </li>
              <?php endforeach; ?>
            </ul>
          </div>
        </article>
      </div>
    </div>
  </div>
</section>

<section class="row g-3 mt-1">
  <div class="col-12">
    <article class="card ap-card">
      <header class="card-header ap-card-head">
        <div>
          <h4 class="ap-card-title mb-1">Activity Timeline</h4>
          <p class="ap-card-sub mb-0">Last platform actions in this session</p>
        </div>
      </header>
      <div class="card-body">
        <ul class="ap-timeline list-unstyled mb-0">
          <?php foreach ($timeline as $item): ?>
            <li class="ap-timeline-item">
              <span class="ap-timeline-dot"></span>
              <div>
                <p class="ap-timeline-time mb-1"><?= htmlspecialchars($item['time'], ENT_QUOTES, 'UTF-8') ?></p>
                <p class="ap-timeline-text mb-0"><?= htmlspecialchars($item['text'], ENT_QUOTES, 'UTF-8') ?></p>
              </div>
            </li>
          <?php endforeach; ?>
        </ul>
      </div>
    </article>
  </div>
</section>
