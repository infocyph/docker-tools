<?php
declare(strict_types=1);

$kpis = [
    ['label' => 'Total Revenue', 'value' => '$48,920', 'delta' => '+12.4%', 'state' => 'up', 'icon' => 'bi-cash-stack'],
    ['label' => 'Subscriptions', 'value' => '1,284', 'delta' => '+8.1%', 'state' => 'up', 'icon' => 'bi-stars'],
    ['label' => 'Active Users', 'value' => '9,742', 'delta' => '+3.7%', 'state' => 'up', 'icon' => 'bi-people'],
    ['label' => 'Churn Rate', 'value' => '2.9%', 'delta' => '-0.5%', 'state' => 'down', 'icon' => 'bi-arrow-repeat'],
];

$topPages = [
    ['page' => '/dashboard', 'views' => 14520, 'bounce' => '22.1%'],
    ['page' => '/billing', 'views' => 9032, 'bounce' => '31.8%'],
    ['page' => '/analytics', 'views' => 8411, 'bounce' => '24.5%'],
    ['page' => '/profile', 'views' => 5780, 'bounce' => '27.4%'],
    ['page' => '/notifications', 'views' => 4135, 'bounce' => '19.0%'],
];

$activeUsers = [
    ['name' => 'Sadia Rahman', 'plan' => 'Growth', 'status' => 'online'],
    ['name' => 'Hasan Alvi', 'plan' => 'Starter', 'status' => 'online'],
    ['name' => 'Ishita Ghosh', 'plan' => 'Enterprise', 'status' => 'away'],
    ['name' => 'Tahsin Noor', 'plan' => 'Growth', 'status' => 'online'],
];

$recentOrders = [
    ['id' => '#INV-9012', 'customer' => 'Brisk Labs', 'amount' => '$1,920', 'status' => 'Paid', 'date' => 'Mar 10, 2026'],
    ['id' => '#INV-9011', 'customer' => 'Nexa Cloud', 'amount' => '$780', 'status' => 'Pending', 'date' => 'Mar 10, 2026'],
    ['id' => '#INV-9010', 'customer' => 'Lumen Works', 'amount' => '$2,300', 'status' => 'Paid', 'date' => 'Mar 09, 2026'],
    ['id' => '#INV-9009', 'customer' => 'Helix Studio', 'amount' => '$540', 'status' => 'Overdue', 'date' => 'Mar 09, 2026'],
];

$acquisition = [
    ['name' => 'Organic Search', 'share' => 38],
    ['name' => 'Direct', 'share' => 24],
    ['name' => 'Paid Ads', 'share' => 20],
    ['name' => 'Referrals', 'share' => 18],
];
?>

<section class="ap-dash-head">
  <div>
    <h2 class="ap-page-title mb-1">Analytics Dashboard</h2>
    <p class="ap-page-sub mb-0">Priority view aligned to analytics first, SaaS widgets second.</p>
  </div>
  <div class="d-flex align-items-center gap-2 flex-wrap">
    <div class="btn-group ap-filter-group" role="group" aria-label="Time range">
      <button type="button" class="btn active">12 months</button>
      <button type="button" class="btn">30 days</button>
      <button type="button" class="btn">7 days</button>
      <button type="button" class="btn">24 hours</button>
    </div>
    <button class="btn ap-ghost-btn" type="button" disabled><i class="bi bi-download me-1"></i> Export</button>
  </div>
</section>

<section class="row g-3 mt-1">
  <?php foreach ($kpis as $kpi): ?>
    <div class="col-12 col-sm-6 col-xxl-3">
      <article class="card ap-widget-card h-100">
        <div class="card-body">
          <div class="d-flex justify-content-between align-items-start">
            <div>
              <p class="ap-widget-label mb-1"><?= htmlspecialchars($kpi['label'], ENT_QUOTES, 'UTF-8') ?></p>
              <h3 class="ap-widget-value mb-1"><?= htmlspecialchars($kpi['value'], ENT_QUOTES, 'UTF-8') ?></h3>
              <p class="ap-widget-delta ap-<?= htmlspecialchars($kpi['state'], ENT_QUOTES, 'UTF-8') ?> mb-0">
                <?= htmlspecialchars($kpi['delta'], ENT_QUOTES, 'UTF-8') ?>
              </p>
            </div>
            <div class="ap-widget-icon">
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
    <article class="card ap-widget-card h-100">
      <header class="card-header ap-widget-head">
        <div>
          <h4 class="ap-widget-title mb-1">Revenue Analytics</h4>
          <p class="ap-widget-sub mb-0">Monthly revenue and subscription trend</p>
        </div>
      </header>
      <div class="card-body">
        <div class="ap-chart-wrap">
          <canvas id="apRevenueChart" height="130" aria-label="Revenue chart"></canvas>
        </div>
      </div>
    </article>
  </div>

  <div class="col-12 col-xxl-4">
    <article class="card ap-widget-card h-100">
      <header class="card-header ap-widget-head">
        <div>
          <h4 class="ap-widget-title mb-1">Top Channels</h4>
          <p class="ap-widget-sub mb-0">Acquisition source split</p>
        </div>
      </header>
      <div class="card-body">
        <div class="ap-chart-wrap ap-chart-donut">
          <canvas id="apChannelChart" height="200" aria-label="Top channels chart"></canvas>
        </div>
      </div>
    </article>
  </div>
</section>

<section class="row g-3 mt-1">
  <div class="col-12 col-xl-6">
    <article class="card ap-widget-card h-100">
      <header class="card-header ap-widget-head">
        <div>
          <h4 class="ap-widget-title mb-1">Top Pages</h4>
          <p class="ap-widget-sub mb-0">Traffic and bounce behavior</p>
        </div>
      </header>
      <div class="table-responsive">
        <table class="table ap-table mb-0">
          <thead>
            <tr>
              <th>Page</th>
              <th class="text-end">Views</th>
              <th class="text-end">Bounce</th>
            </tr>
          </thead>
          <tbody>
            <?php foreach ($topPages as $row): ?>
              <tr>
                <td class="fw-semibold"><?= htmlspecialchars($row['page'], ENT_QUOTES, 'UTF-8') ?></td>
                <td class="text-end"><?= number_format((int)$row['views']) ?></td>
                <td class="text-end"><?= htmlspecialchars($row['bounce'], ENT_QUOTES, 'UTF-8') ?></td>
              </tr>
            <?php endforeach; ?>
          </tbody>
        </table>
      </div>
    </article>
  </div>

  <div class="col-12 col-xl-3">
    <article class="card ap-widget-card h-100">
      <header class="card-header ap-widget-head">
        <div>
          <h4 class="ap-widget-title mb-1">Active Users</h4>
          <p class="ap-widget-sub mb-0">Live session overview</p>
        </div>
      </header>
      <div class="card-body pt-2">
        <ul class="ap-user-list list-unstyled mb-0">
          <?php foreach ($activeUsers as $user): ?>
            <li>
              <span>
                <strong><?= htmlspecialchars($user['name'], ENT_QUOTES, 'UTF-8') ?></strong><br/>
                <small><?= htmlspecialchars($user['plan'], ENT_QUOTES, 'UTF-8') ?></small>
              </span>
              <span class="ap-status <?= $user['status'] === 'online' ? 'online' : 'away' ?>">
                <?= htmlspecialchars($user['status'], ENT_QUOTES, 'UTF-8') ?>
              </span>
            </li>
          <?php endforeach; ?>
        </ul>
      </div>
    </article>
  </div>

  <div class="col-12 col-xl-3">
    <article class="card ap-widget-card h-100">
      <header class="card-header ap-widget-head">
        <div>
          <h4 class="ap-widget-title mb-1">Device Sessions</h4>
          <p class="ap-widget-sub mb-0">SaaS segment widget</p>
        </div>
      </header>
      <div class="card-body">
        <div class="ap-chart-wrap ap-chart-donut">
          <canvas id="apDeviceChart" height="220" aria-label="Device sessions chart"></canvas>
        </div>
      </div>
    </article>
  </div>
</section>

<section class="row g-3 mt-1">
  <div class="col-12 col-xl-4">
    <article class="card ap-widget-card h-100">
      <header class="card-header ap-widget-head">
        <div>
          <h4 class="ap-widget-title mb-1">Acquisition Breakdown</h4>
          <p class="ap-widget-sub mb-0">SaaS funnel support widget</p>
        </div>
      </header>
      <div class="card-body">
        <?php foreach ($acquisition as $item): ?>
          <div class="ap-progress-row">
            <span><?= htmlspecialchars($item['name'], ENT_QUOTES, 'UTF-8') ?></span>
            <span><?= (int)$item['share'] ?>%</span>
          </div>
          <div class="progress ap-progress mb-3">
            <div class="progress-bar" style="width: <?= (int)$item['share'] ?>%"></div>
          </div>
        <?php endforeach; ?>
      </div>
    </article>
  </div>

  <div class="col-12 col-xl-8">
    <article class="card ap-widget-card h-100">
      <header class="card-header ap-widget-head">
        <div>
          <h4 class="ap-widget-title mb-1">Recent Orders</h4>
          <p class="ap-widget-sub mb-0">SaaS billing stream (seed data)</p>
        </div>
      </header>
      <div class="table-responsive">
        <table class="table ap-table mb-0">
          <thead>
            <tr>
              <th>Invoice</th>
              <th>Customer</th>
              <th>Amount</th>
              <th>Status</th>
              <th>Date</th>
            </tr>
          </thead>
          <tbody>
            <?php foreach ($recentOrders as $row): ?>
              <tr>
                <td class="fw-semibold"><?= htmlspecialchars($row['id'], ENT_QUOTES, 'UTF-8') ?></td>
                <td><?= htmlspecialchars($row['customer'], ENT_QUOTES, 'UTF-8') ?></td>
                <td><?= htmlspecialchars($row['amount'], ENT_QUOTES, 'UTF-8') ?></td>
                <td>
                  <span class="badge ap-order-badge ap-order-<?= strtolower($row['status']) ?>">
                    <?= htmlspecialchars($row['status'], ENT_QUOTES, 'UTF-8') ?>
                  </span>
                </td>
                <td><?= htmlspecialchars($row['date'], ENT_QUOTES, 'UTF-8') ?></td>
              </tr>
            <?php endforeach; ?>
          </tbody>
        </table>
      </div>
    </article>
  </div>
</section>

