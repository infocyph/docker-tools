<?php
declare(strict_types=1);
?>

<section class="ap-page-head">
  <div>
    <p class="ap-breadcrumb mb-1">Home / Live Stats</p>
    <h2 class="ap-page-title mb-1">Live Stack Telemetry</h2>
  </div>
  <div class="d-flex align-items-center gap-2 flex-wrap">
    <div class="btn-group" role="group" aria-label="Section visibility">
      <button id="apLiveCollapseAllBtn" class="btn ap-ghost-btn" type="button"><i class="bi bi-arrows-collapse me-1"></i> Collapse all</button>
      <button id="apLiveExpandAllBtn" class="btn ap-ghost-btn" type="button"><i class="bi bi-arrows-expand me-1"></i> Expand all</button>
    </div>
    <button id="apLiveCompactToggleBtn" class="btn ap-ghost-btn" type="button" aria-pressed="false"><i class="bi bi-layout-text-sidebar-reverse me-1"></i> Compact</button>
    <button id="apLiveRefreshBtn" class="btn ap-ghost-btn" type="button"><i class="bi bi-arrow-repeat me-1"></i> Refresh</button>
    <span id="apLiveUpdatedAt" class="ap-live-meta">Loading...</span>
  </div>
</section>

<section class="row g-3 mt-1 ap-kpi-row" id="apLiveStatsPage">
  <div class="col-12 col-md-6 col-xl-3 ap-kpi-col">
    <article class="card ap-card ap-kpi-card h-100">
      <div class="card-body">
        <p class="ap-kpi-label mb-1">Containers</p>
        <div class="ap-kpi-lines">
          <div class="ap-kpi-line">
            <p class="ap-kpi-mini-label mb-0">Running / Total</p>
            <h3 class="ap-kpi-mini-value mb-0" id="apLiveRunning">-</h3>
          </div>
          <div class="ap-kpi-line">
            <p class="ap-kpi-mini-label mb-0">Healthy / Unhealthy / No Health</p>
            <h3 class="ap-kpi-mini-value mb-0" id="apLiveHealth">-</h3>
          </div>
        </div>
      </div>
    </article>
  </div>
  <div class="col-12 col-md-6 col-xl-2 ap-kpi-col">
    <article class="card ap-card ap-kpi-card h-100">
      <div class="card-body">
        <p class="ap-kpi-label mb-1">Access</p>
        <div class="ap-kpi-lines">
          <div class="ap-kpi-line">
            <p class="ap-kpi-mini-label mb-0">URLs</p>
            <h3 class="ap-kpi-mini-value mb-0" id="apLiveUrls">-</h3>
          </div>
          <div class="ap-kpi-line">
            <p class="ap-kpi-mini-label mb-0">Ports</p>
            <h3 class="ap-kpi-mini-value mb-0" id="apLivePorts">-</h3>
          </div>
        </div>
      </div>
    </article>
  </div>
  <div class="col-12 col-md-6 col-xl-3 ap-kpi-col">
    <article class="card ap-card ap-kpi-card h-100">
      <div class="card-body">
        <p class="ap-kpi-label mb-1">Checks</p>
        <div class="ap-kpi-lines">
          <div class="ap-kpi-line">
            <p class="ap-kpi-mini-label mb-0">Problems</p>
            <h3 class="ap-kpi-mini-value mb-0" id="apLiveProblems">-</h3>
          </div>
          <div class="ap-kpi-line">
            <p class="ap-kpi-mini-label mb-0">System</p>
            <h3 class="ap-kpi-mini-value mb-0" id="apLiveSystemChecks">-</h3>
            <div class="ap-kpi-capsules ap-kpi-line-capsules" id="apLiveSystemChecksCaps"></div>
          </div>
          <div class="ap-kpi-line">
            <p class="ap-kpi-mini-label mb-0">Project</p>
            <h3 class="ap-kpi-mini-value mb-0" id="apLiveProjectChecks">-</h3>
            <div class="ap-kpi-capsules ap-kpi-line-capsules" id="apLiveProjectChecksCaps"></div>
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
          <h4 class="ap-card-title mb-1">Endpoint Monitor</h4>
          <p class="ap-card-sub mb-0">Resolved URLs with probe status and response time</p>
        </div>
        <button class="btn ap-ghost-btn ap-card-collapse-toggle" type="button" data-target="apLiveUrlsBody" aria-expanded="true" title="Collapse section">
          <i class="bi bi-chevron-up"></i>
        </button>
      </header>
      <div id="apLiveUrlsBody" data-collapsible-body="urls">
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
        <button class="btn ap-ghost-btn ap-card-collapse-toggle" type="button" data-target="apLiveProblemsBody" aria-expanded="true" title="Collapse section">
          <i class="bi bi-chevron-up"></i>
        </button>
      </header>
      <div id="apLiveProblemsBody" data-collapsible-body="problems">
        <div class="card-body">
          <ul class="ap-live-list list-unstyled mb-0" id="apLiveIssueFeed"></ul>
        </div>
      </div>
    </article>
  </div>
</section>

<section class="row g-3 mt-1">
  <div class="col-12">
    <article class="card ap-card h-100">
      <header class="card-header ap-card-head ap-card-head-wrap">
        <div>
          <h4 class="ap-card-title mb-1">Stats</h4>
          <p class="ap-card-sub mb-0">Grouped CPU, memory, net I/O, block I/O by container (normalized for readability)</p>
        </div>
        <div class="ap-head-tools">
          <div id="apLiveStatsSeriesControls" class="ap-quick-chips" role="group" aria-label="Stats datasets">
            <button type="button" class="btn ap-chip-btn is-active" data-series="cpu">CPU</button>
            <button type="button" class="btn ap-chip-btn is-active" data-series="memory">Memory</button>
            <button type="button" class="btn ap-chip-btn" data-series="network">Net I/O</button>
            <button type="button" class="btn ap-chip-btn" data-series="block">Block I/O</button>
          </div>
          <button class="btn ap-ghost-btn ap-card-collapse-toggle" type="button" data-target="apLiveStatsBody" aria-expanded="true" title="Collapse section">
            <i class="bi bi-chevron-up"></i>
          </button>
        </div>
      </header>
      <div id="apLiveStatsBody" data-collapsible-body="stats">
        <div class="card-body">
          <div class="ap-chart-wrap">
            <canvas id="apLiveStatsChart" height="220" aria-label="Stats chart"></canvas>
          </div>
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
        <button class="btn ap-ghost-btn ap-card-collapse-toggle" type="button" data-target="apLiveDiskBody" aria-expanded="true" title="Collapse section">
          <i class="bi bi-chevron-up"></i>
        </button>
      </header>
      <div id="apLiveDiskBody" data-collapsible-body="disk">
        <div class="card-body">
          <div class="ap-chart-wrap ap-chart-sm">
            <canvas id="apLiveDiskChart" height="180" aria-label="Disk chart"></canvas>
          </div>
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
        <button class="btn ap-ghost-btn ap-card-collapse-toggle" type="button" data-target="apLiveVolumesBody" aria-expanded="true" title="Collapse section">
          <i class="bi bi-chevron-up"></i>
        </button>
      </header>
      <div id="apLiveVolumesBody" data-collapsible-body="volumes">
        <div class="card-body">
          <div class="ap-chart-wrap">
            <canvas id="apLiveVolumeChart" height="180" aria-label="Volume chart"></canvas>
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
          <h4 class="ap-card-title mb-1">Project Health Snapshot</h4>
          <p class="ap-card-sub mb-0">System tests, project checks, mounts, and drift indicators in one place</p>
        </div>
        <button class="btn ap-ghost-btn ap-card-collapse-toggle" type="button" data-target="apLiveProjectHealthBody" aria-expanded="true" title="Collapse section">
          <i class="bi bi-chevron-up"></i>
        </button>
      </header>
      <div id="apLiveProjectHealthBody" data-collapsible-body="project-health">
        <div class="card-body">
          <div class="row g-3">
            <div class="col-12">
              <h5 class="ap-card-title mb-2 ap-title-with-state"><span>System Tests</span><span id="apLiveSystemTestsStateIcon"></span></h5>
              <div class="ap-section-tools mb-2">
                <div id="apLiveChecksFilter" class="ap-quick-chips" role="group" aria-label="Checks filter">
                  <button type="button" class="btn ap-chip-btn is-active" data-check-state="all">All</button>
                  <button type="button" class="btn ap-chip-btn" data-check-state="pass">Pass</button>
                  <button type="button" class="btn ap-chip-btn" data-check-state="warn">Warn</button>
                  <button type="button" class="btn ap-chip-btn" data-check-state="fail">Fail</button>
                </div>
                <input id="apLiveChecksSearch" class="form-control form-control-sm ap-live-tool-input" type="search" placeholder="Search tests or details">
              </div>
              <div class="table-responsive ap-local-sticky">
                <table class="table ap-table ap-table-sticky ap-table-emphasis mb-0">
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
      </div>
    </article>
  </div>
</section>

<section class="row g-3 mt-1">
  <div class="col-12">
    <article class="card ap-card h-100">
      <header class="card-header ap-card-head ap-card-head-wrap">
        <div>
          <h4 class="ap-card-title mb-1">Container Runtime Matrix</h4>
          <p class="ap-card-sub mb-0">Container identity, health, ports, CPU/memory usage, and network connectivity</p>
        </div>
        <div class="ap-head-tools">
          <div class="ap-live-matrix-tools">
            <div id="apLiveMatrixStateFilter" class="ap-quick-chips" role="group" aria-label="Runtime filter">
              <button type="button" class="btn ap-chip-btn is-active" data-runtime-state="all">All</button>
              <button type="button" class="btn ap-chip-btn" data-runtime-state="pass">Pass</button>
              <button type="button" class="btn ap-chip-btn" data-runtime-state="warn">Warn</button>
              <button type="button" class="btn ap-chip-btn" data-runtime-state="fail">Fail</button>
            </div>
            <input id="apLiveMatrixSearch" class="form-control form-control-sm ap-live-tool-input" type="search" placeholder="Search container/service">
            <select id="apLiveMatrixSort" class="form-select form-select-sm ap-live-tool-select" aria-label="Sort rows">
              <option value="cpu_desc">Sort: CPU desc</option>
              <option value="mem_desc">Sort: memory desc</option>
              <option value="name_asc">Sort: name A-Z</option>
            </select>
          </div>
          <button class="btn ap-ghost-btn ap-card-collapse-toggle" type="button" data-target="apLiveRuntimeBody" aria-expanded="true" title="Collapse section">
            <i class="bi bi-chevron-up"></i>
          </button>
        </div>
      </header>
      <div id="apLiveRuntimeBody" data-collapsible-body="runtime">
        <div class="table-responsive ap-local-sticky">
          <table class="table ap-table ap-table-sticky ap-table-emphasis mb-0">
            <thead id="apLiveNetworkMatrixHead">
            <tr><th>Container / Service</th><th>State</th><th>Ports</th><th class="text-end">CPU %</th><th class="text-end">Mem Usage</th><th class="text-end">Networks</th></tr>
            </thead>
            <tbody id="apLiveNetworkMatrixRows">
            <tr><td colspan="6" class="text-center ap-page-sub py-4">Loading...</td></tr>
            </tbody>
          </table>
        </div>
      </div>
    </article>
  </div>
</section>

<div id="apLiveError" class="ap-live-error d-none mt-3"></div>

<div class="modal fade" id="apLiveContainerDetailsModal" tabindex="-1" aria-labelledby="apLiveContainerDetailsTitle" aria-hidden="true">
  <div class="modal-dialog modal-lg modal-dialog-scrollable">
    <div class="modal-content ap-card">
      <div class="modal-header">
        <h5 class="modal-title" id="apLiveContainerDetailsTitle">Container Details</h5>
        <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
      </div>
      <div class="modal-body">
        <dl class="ap-detail-grid mb-0" id="apLiveContainerDetailsGrid"></dl>
      </div>
    </div>
  </div>
</div>
