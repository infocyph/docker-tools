<?php
declare(strict_types=1);
?>

<section class="ap-page-head">
  <div>
    <p class="ap-breadcrumb mb-1">Home / Live Stats</p>
    <h2 class="ap-page-title mb-1">Live Stack Telemetry</h2>
  </div>
  <div class="d-flex align-items-center gap-2 flex-wrap">
    <button id="apLiveRefreshBtn" class="btn ap-ghost-btn" type="button"><i class="bi bi-arrow-repeat me-1"></i> Refresh</button>
    <span id="apLiveUpdatedAt" class="ap-live-meta">Loading...</span>
  </div>
</section>

<section class="row g-3 mt-1" id="apLiveStatsPage">
  <div class="col-12 col-md-6 col-xl-3">
    <article class="card ap-card ap-kpi-card h-100">
      <div class="card-body">
        <p class="ap-kpi-label mb-1">Running / Total</p>
        <h3 class="ap-kpi-value mb-0" id="apLiveRunning">-</h3>
      </div>
    </article>
  </div>
  <div class="col-12 col-md-6 col-xl-3">
    <article class="card ap-card ap-kpi-card h-100">
      <div class="card-body">
        <p class="ap-kpi-label mb-1">Healthy / Unhealthy / No Health</p>
        <h3 class="ap-kpi-value mb-0" id="apLiveHealth">-</h3>
      </div>
    </article>
  </div>
  <div class="col-12 col-md-6 col-xl-2">
    <article class="card ap-card ap-kpi-card h-100">
      <div class="card-body">
        <p class="ap-kpi-label mb-1">URLs</p>
        <h3 class="ap-kpi-value mb-0" id="apLiveUrls">-</h3>
      </div>
    </article>
  </div>
  <div class="col-12 col-md-6 col-xl-2">
    <article class="card ap-card ap-kpi-card h-100">
      <div class="card-body">
        <p class="ap-kpi-label mb-1">Ports</p>
        <h3 class="ap-kpi-value mb-0" id="apLivePorts">-</h3>
      </div>
    </article>
  </div>
  <div class="col-12 col-md-6 col-xl-2">
    <article class="card ap-card ap-kpi-card h-100">
      <div class="card-body">
        <p class="ap-kpi-label mb-1">Problems</p>
        <h3 class="ap-kpi-value mb-0" id="apLiveProblems">-</h3>
      </div>
    </article>
  </div>
  <div class="col-12 col-md-6 col-xl-3">
    <article class="card ap-card ap-kpi-card h-100">
      <div class="card-body">
        <p class="ap-kpi-label mb-1">System Checks</p>
        <h3 class="ap-kpi-value mb-1" id="apLiveSystemChecks">-</h3>
        <p class="ap-kpi-meta mb-2">Total checks</p>
        <div class="ap-kpi-capsules" id="apLiveSystemChecksCaps"></div>
      </div>
    </article>
  </div>
  <div class="col-12 col-md-6 col-xl-3">
    <article class="card ap-card ap-kpi-card h-100">
      <div class="card-body">
        <p class="ap-kpi-label mb-1">Project Checks</p>
        <h3 class="ap-kpi-value mb-1" id="apLiveProjectChecks">-</h3>
        <p class="ap-kpi-meta mb-2">Total checks</p>
        <div class="ap-kpi-capsules" id="apLiveProjectChecksCaps"></div>
      </div>
    </article>
  </div>
</section>

<section class="row g-3 mt-1">
  <div class="col-12">
    <article class="card ap-card h-100">
      <header class="card-header ap-card-head">
        <div>
          <h4 class="ap-card-title mb-1">URLs</h4>
          <p class="ap-card-sub mb-0">Resolved endpoints and probe status</p>
        </div>
      </header>
      <div class="card-body">
        <div class="table-responsive">
          <table class="table ap-table mb-0">
            <thead><tr><th>URL</th><th class="text-end">Status</th><th class="text-end">Time</th></tr></thead>
            <tbody id="apLiveUrlProbeRows">
            <tr><td colspan="3" class="text-center ap-page-sub py-4">Loading...</td></tr>
            </tbody>
          </table>
        </div>
      </div>
    </article>
  </div>
</section>

<section class="row g-3 mt-1">
  <div class="col-12">
    <article class="card ap-card">
      <header class="card-header ap-card-head">
        <div>
          <h4 class="ap-card-title mb-1">Problems</h4>
          <p class="ap-card-sub mb-0">Problems and recent errors</p>
        </div>
      </header>
      <div class="card-body">
        <ul class="ap-live-list list-unstyled mb-0" id="apLiveIssueFeed"></ul>
      </div>
    </article>
  </div>
</section>

<section class="row g-3 mt-1">
  <div class="col-12">
    <article class="card ap-card h-100">
      <header class="card-header ap-card-head">
        <div>
          <h4 class="ap-card-title mb-1">Stats</h4>
          <p class="ap-card-sub mb-0">Grouped CPU, memory, net I/O, block I/O by container (normalized for readability)</p>
        </div>
      </header>
      <div class="card-body">
        <div class="ap-chart-wrap">
          <canvas id="apLiveStatsChart" height="220" aria-label="Stats chart"></canvas>
        </div>
      </div>
    </article>
  </div>
</section>

<section class="row g-3 mt-1">
  <div class="col-12 col-xl-6">
    <article class="card ap-card h-100">
      <header class="card-header ap-card-head">
        <div>
          <h4 class="ap-card-title mb-1">Disk</h4>
          <p class="ap-card-sub mb-0">Docker disk usage distribution (<code>sections.disk.items</code>)</p>
        </div>
      </header>
      <div class="card-body">
        <div class="ap-chart-wrap ap-chart-sm">
          <canvas id="apLiveDiskChart" height="180" aria-label="Disk chart"></canvas>
        </div>
      </div>
    </article>
  </div>
  <div class="col-12 col-xl-6">
    <article class="card ap-card h-100">
      <header class="card-header ap-card-head">
        <div>
          <h4 class="ap-card-title mb-1">Volumes</h4>
          <p class="ap-card-sub mb-0">Largest named volumes (<code>sections.volumes.items</code>)</p>
        </div>
      </header>
      <div class="card-body">
        <div class="ap-chart-wrap">
          <canvas id="apLiveVolumeChart" height="180" aria-label="Volume chart"></canvas>
        </div>
      </div>
    </article>
  </div>
</section>

<section class="row g-3 mt-1">
  <div class="col-12">
    <article class="card ap-card h-100">
      <header class="card-header ap-card-head">
        <div>
          <h4 class="ap-card-title mb-1">Project Health Snapshot</h4>
          <p class="ap-card-sub mb-0">System tests, project checks, mounts, and drift indicators in one place</p>
        </div>
      </header>
      <div class="card-body">
        <div class="row g-3">
          <div class="col-12">
            <h5 class="ap-card-title mb-2 ap-title-with-state"><span>System Tests</span><span id="apLiveSystemTestsStateIcon"></span></h5>
            <div class="table-responsive">
              <table class="table ap-table mb-0">
                <thead><tr><th>Test</th><th class="text-end">State</th><th>Detail</th></tr></thead>
                <tbody id="apLiveSystemTestsRows">
                <tr><td colspan="3" class="text-center ap-page-sub py-4">Loading...</td></tr>
                </tbody>
              </table>
            </div>
          </div>
          <div class="col-12 col-xl-4">
            <h5 class="ap-card-title mb-2 ap-title-with-state"><span>Containers</span><span id="apLiveProjectContainersStateIcon"></span></h5>
            <ul class="ap-live-list list-unstyled mb-0" id="apLiveProjectContainersList"></ul>
          </div>
          <div class="col-12 col-xl-4">
            <h5 class="ap-card-title mb-2 ap-title-with-state"><span>Artifacts</span><span id="apLiveProjectArtifactsStateIcon"></span></h5>
            <ul class="ap-live-list list-unstyled mb-0" id="apLiveProjectArtifactsList"></ul>
          </div>
          <div class="col-12 col-xl-4">
            <h5 class="ap-card-title mb-2 ap-title-with-state"><span>Project Mounts Check</span><span id="apLiveProjectMountsStateIcon"></span></h5>
            <ul class="ap-live-list list-unstyled mb-0" id="apLiveProjectMountList"></ul>
          </div>
        </div>
      </div>
    </article>
  </div>
</section>

<section class="row g-3 mt-1">
  <div class="col-12">
    <article class="card ap-card h-100">
      <header class="card-header ap-card-head">
        <div>
          <h4 class="ap-card-title mb-1">Container Runtime Matrix</h4>
          <p class="ap-card-sub mb-0">Container identity, health, ports, CPU/memory usage, and network connectivity</p>
        </div>
      </header>
      <div class="table-responsive">
        <table class="table ap-table mb-0">
          <thead id="apLiveNetworkMatrixHead">
          <tr><th>Container / Service</th><th>State</th><th>Ports</th><th class="text-end">CPU %</th><th class="text-end">Mem Usage</th><th class="text-end">Networks</th></tr>
          </thead>
          <tbody id="apLiveNetworkMatrixRows">
          <tr><td colspan="6" class="text-center ap-page-sub py-4">Loading...</td></tr>
          </tbody>
        </table>
      </div>
    </article>
  </div>
</section>

<div id="apLiveError" class="ap-live-error d-none mt-3"></div>
