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
</section>

<section class="row g-3 mt-1">
  <div class="col-12 col-lg-6">
    <article class="card ap-card h-100">
      <header class="card-header ap-card-head">
        <div>
          <h4 class="ap-card-title mb-1">Checks Summary</h4>
          <p class="ap-card-sub mb-0">System + project check overview</p>
        </div>
      </header>
      <div class="card-body">
        <ul class="ap-live-list list-unstyled mb-3" id="apLiveChecksSummary"></ul>
        <ul class="ap-live-list list-unstyled mb-0" id="apLiveChecksDetails"></ul>
      </div>
    </article>
  </div>
  <div class="col-12 col-lg-6">
    <article class="card ap-card h-100">
      <header class="card-header ap-card-head">
        <div>
          <h4 class="ap-card-title mb-1">URLs</h4>
          <p class="ap-card-sub mb-0">Resolved endpoints</p>
        </div>
      </header>
      <div class="card-body">
        <ul class="ap-live-list list-unstyled mb-0" id="apLiveUrlList"></ul>
      </div>
    </article>
  </div>
</section>

<section class="row g-3 mt-1">
  <div class="col-12 col-xl-4">
    <article class="card ap-card h-100">
      <header class="card-header ap-card-head">
        <div>
          <h4 class="ap-card-title mb-1">Internal Ports</h4>
          <p class="ap-card-sub mb-0">Values from <code>core.ports</code></p>
        </div>
      </header>
      <div class="card-body">
        <ul class="ap-live-list list-unstyled mb-0" id="apLivePortList"></ul>
      </div>
    </article>
  </div>
  <div class="col-12 col-xl-4">
    <article class="card ap-card h-100">
      <header class="card-header ap-card-head">
        <div>
          <h4 class="ap-card-title mb-1">Service Ports</h4>
          <p class="ap-card-sub mb-0">Ports mapped per container</p>
        </div>
      </header>
      <div class="card-body">
        <ul class="ap-live-list list-unstyled mb-0" id="apLivePortContainerList"></ul>
      </div>
    </article>
  </div>
  <div class="col-12 col-xl-4">
    <article class="card ap-card h-100">
      <header class="card-header ap-card-head">
        <div>
          <h4 class="ap-card-title mb-1">Drifts</h4>
          <p class="ap-card-sub mb-0">Summary and detailed drift outputs</p>
        </div>
      </header>
      <div class="card-body">
        <ul class="ap-live-list list-unstyled mb-0" id="apLiveDriftList"></ul>
        <div class="row g-3 mt-1">
          <div class="col-12 col-md-4">
            <h5 class="ap-card-title mb-2">Orphan Containers</h5>
            <ul class="ap-live-list list-unstyled mb-0" id="apLiveDriftOrphans"></ul>
          </div>
          <div class="col-12 col-md-4">
            <h5 class="ap-card-title mb-2">Labeled Volumes</h5>
            <ul class="ap-live-list list-unstyled mb-0" id="apLiveDriftLabeledVolumes"></ul>
          </div>
          <div class="col-12 col-md-4">
            <h5 class="ap-card-title mb-2">Unused Labeled Volumes</h5>
            <ul class="ap-live-list list-unstyled mb-0" id="apLiveDriftUnusedVolumes"></ul>
          </div>
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
          <p class="ap-card-sub mb-0">Current reported problems list</p>
        </div>
      </header>
      <div class="card-body">
        <ul class="ap-live-list list-unstyled mb-0" id="apLiveProblemList"></ul>
      </div>
    </article>
  </div>
</section>

<section class="row g-3 mt-1">
  <div class="col-12 col-xl-6">
    <article class="card ap-card h-100">
      <header class="card-header ap-card-head">
        <div>
          <h4 class="ap-card-title mb-1">System Tests</h4>
          <p class="ap-card-sub mb-0">Checks: <code>system.tests</code></p>
        </div>
      </header>
      <div class="table-responsive">
        <table class="table ap-table mb-0">
          <thead><tr><th>Test</th><th class="text-end">State</th><th>Detail</th></tr></thead>
          <tbody id="apLiveSystemTestsRows">
          <tr><td colspan="3" class="text-center ap-page-sub py-4">Loading...</td></tr>
          </tbody>
        </table>
      </div>
    </article>
  </div>
  <div class="col-12 col-xl-6">
    <article class="card ap-card h-100">
      <header class="card-header ap-card-head">
        <div>
          <h4 class="ap-card-title mb-1">Project Containers Check</h4>
          <p class="ap-card-sub mb-0">Checks: <code>project.tests.containers</code></p>
        </div>
      </header>
      <div class="card-body">
        <ul class="ap-live-list list-unstyled mb-0" id="apLiveProjectContainersList"></ul>
      </div>
    </article>
  </div>
</section>

<section class="row g-3 mt-1">
  <div class="col-12 col-xl-6">
    <article class="card ap-card h-100">
      <header class="card-header ap-card-head">
        <div>
          <h4 class="ap-card-title mb-1">Project Artifacts Check</h4>
          <p class="ap-card-sub mb-0">Checks: <code>project.tests.artifacts</code></p>
        </div>
      </header>
      <div class="card-body">
        <ul class="ap-live-list list-unstyled mb-0" id="apLiveProjectArtifactsList"></ul>
      </div>
    </article>
  </div>
  <div class="col-12 col-xl-6">
    <article class="card ap-card h-100">
      <header class="card-header ap-card-head">
        <div>
          <h4 class="ap-card-title mb-1">Project Mounts Check</h4>
          <p class="ap-card-sub mb-0">Checks: <code>project.tests.mounts</code></p>
        </div>
      </header>
      <div class="table-responsive">
        <table class="table ap-table mb-0">
          <thead><tr><th>Key</th><th>Path</th><th class="text-end">State</th><th>Flag</th></tr></thead>
          <tbody id="apLiveProjectMountRows">
          <tr><td colspan="4" class="text-center ap-page-sub py-4">Loading...</td></tr>
          </tbody>
        </table>
      </div>
    </article>
  </div>
</section>

<section class="row g-3 mt-1">
  <div class="col-12 col-xxl-8">
    <article class="card ap-card h-100">
      <header class="card-header ap-card-head">
        <div>
          <h4 class="ap-card-title mb-1">Top CPU Consumers</h4>
          <p class="ap-card-sub mb-0">Top 5 by CPU usage</p>
        </div>
      </header>
      <div class="card-body">
        <div class="ap-chart-wrap">
          <canvas id="apLiveCpuChart" height="120" aria-label="Top CPU chart"></canvas>
        </div>
      </div>
    </article>
  </div>
  <div class="col-12 col-xxl-4">
    <article class="card ap-card h-100">
      <header class="card-header ap-card-head">
        <div>
          <h4 class="ap-card-title mb-1">Top Memory Consumers</h4>
          <p class="ap-card-sub mb-0">Top 5 by memory usage</p>
        </div>
      </header>
      <div class="card-body">
        <div class="ap-chart-wrap ap-chart-sm">
          <canvas id="apLiveMemoryChart" height="190" aria-label="Top memory chart"></canvas>
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
          <h4 class="ap-card-title mb-1">Containers + Network + Top Consumers</h4>
          <p class="ap-card-sub mb-0">Merged container status, top consumer CPU/memory, and network matrix</p>
        </div>
      </header>
      <div class="table-responsive">
        <table class="table ap-table mb-0">
          <thead id="apLiveNetworkMatrixHead">
          <tr><th>Container</th><th>Service</th><th>State</th><th>Health</th><th class="text-end">CPU %</th><th class="text-end">Mem Usage</th><th class="text-end">Networks</th></tr>
          </thead>
          <tbody id="apLiveNetworkMatrixRows">
          <tr><td colspan="7" class="text-center ap-page-sub py-4">Loading...</td></tr>
          </tbody>
        </table>
      </div>
    </article>
  </div>
</section>

<section class="row g-3 mt-1">
  <div class="col-12">
    <article class="card ap-card h-100">
      <header class="card-header ap-card-head">
        <div>
          <h4 class="ap-card-title mb-1">Probes + Recent Errors</h4>
          <p class="ap-card-sub mb-0">Probe response and error feed</p>
        </div>
      </header>
      <div class="table-responsive">
        <table class="table ap-table mb-0">
          <thead><tr><th>Probe URL</th><th class="text-end">Status</th><th class="text-end">Time</th></tr></thead>
          <tbody id="apLiveProbeRows">
          <tr><td colspan="3" class="text-center ap-page-sub py-4">Loading...</td></tr>
          </tbody>
        </table>
      </div>
      <div class="card-body pt-2">
        <p class="ap-page-sub mb-2">Recent Errors</p>
        <ul class="ap-live-list list-unstyled mb-0" id="apLiveRecentErrors"></ul>
      </div>
    </article>
  </div>
</section>

<section class="row g-3 mt-1">
  <div class="col-12">
    <article class="card ap-card">
      <header class="card-header ap-card-head">
        <div>
          <h4 class="ap-card-title mb-1">Raw status --json Payload</h4>
          <p class="ap-card-sub mb-0">Full response for parity checks</p>
        </div>
      </header>
      <div class="card-body">
        <pre id="apLiveRawJson" class="ap-live-raw mb-0">Loading...</pre>
      </div>
    </article>
  </div>
</section>

<div id="apLiveError" class="ap-live-error d-none mt-3"></div>
