<?php
declare(strict_types=1);
?>

<section class="ap-page-head">
  <div>
    <p class="ap-breadcrumb mb-1">Home / Dashboard</p>
    <h2 class="ap-page-title mb-1">Operations Overview</h2>
    <p class="ap-page-sub mb-0">Live LocalDevStack status. No synthetic business or uptime data is displayed.</p>
  </div>
  <div class="d-flex align-items-center gap-2 flex-wrap">
    <span id="apDashboardGenerated" class="small text-body-secondary">Waiting for status…</span>
    <button id="apDashboardRefresh" class="btn ap-primary-btn" type="button">
      <i class="bi bi-arrow-clockwise me-1"></i> Refresh
    </button>
  </div>
</section>

<section class="row g-3 mt-1">
  <div class="col-12 col-sm-6 col-xxl-3">
    <article class="card ap-card ap-kpi-card h-100">
      <div class="card-body">
        <p class="ap-kpi-label mb-1">Compose Project</p>
        <h3 id="apDashboardProject" class="ap-kpi-value mb-1">—</h3>
        <p id="apDashboardProfiles" class="ap-kpi-meta mb-0">Profiles: —</p>
      </div>
    </article>
  </div>
  <div class="col-12 col-sm-6 col-xxl-3">
    <article class="card ap-card ap-kpi-card h-100">
      <div class="card-body">
        <p class="ap-kpi-label mb-1">Containers Running</p>
        <h3 id="apDashboardContainers" class="ap-kpi-value mb-1">—</h3>
        <p id="apDashboardHealth" class="ap-kpi-meta mb-0">Health: —</p>
      </div>
    </article>
  </div>
  <div class="col-12 col-sm-6 col-xxl-3">
    <article class="card ap-card ap-kpi-card h-100">
      <div class="card-body">
        <p class="ap-kpi-label mb-1">Detected Problems</p>
        <h3 id="apDashboardProblems" class="ap-kpi-value mb-1">—</h3>
        <p id="apDashboardChecks" class="ap-kpi-meta mb-0">Checks: —</p>
      </div>
    </article>
  </div>
  <div class="col-12 col-sm-6 col-xxl-3">
    <article class="card ap-card ap-kpi-card h-100">
      <div class="card-body">
        <p class="ap-kpi-label mb-1">Discovered URLs</p>
        <h3 id="apDashboardUrls" class="ap-kpi-value mb-1">—</h3>
        <p id="apDashboardPorts" class="ap-kpi-meta mb-0">Ports: —</p>
      </div>
    </article>
  </div>
</section>

<section class="row g-3 mt-1">
  <div class="col-12 col-xl-7">
    <article class="card ap-card h-100">
      <header class="card-header ap-card-head">
        <div>
          <h4 class="ap-card-title mb-1">Deterministic Checks</h4>
          <p class="ap-card-sub mb-0">Summaries reported by the existing status command.</p>
        </div>
      </header>
      <div class="card-body">
        <div class="row g-3">
          <div class="col-12 col-md-6">
            <div class="border rounded p-3 h-100">
              <p class="fw-semibold mb-2">System</p>
              <div class="d-flex gap-2 flex-wrap">
                <span id="apSystemPass" class="badge text-bg-success">Pass —</span>
                <span id="apSystemWarn" class="badge text-bg-warning">Warn —</span>
                <span id="apSystemFail" class="badge text-bg-danger">Fail —</span>
              </div>
            </div>
          </div>
          <div class="col-12 col-md-6">
            <div class="border rounded p-3 h-100">
              <p class="fw-semibold mb-2">Project</p>
              <div class="d-flex gap-2 flex-wrap">
                <span id="apProjectPass" class="badge text-bg-success">Pass —</span>
                <span id="apProjectWarn" class="badge text-bg-warning">Warn —</span>
                <span id="apProjectFail" class="badge text-bg-danger">Fail —</span>
              </div>
            </div>
          </div>
        </div>

        <div class="mt-3 border rounded p-3">
          <div class="d-flex justify-content-between gap-3 flex-wrap">
            <div>
              <p class="fw-semibold mb-1">Optional local AI</p>
              <p class="small text-body-secondary mb-0">Provider state only; opening the dashboard never starts generation.</p>
            </div>
            <span id="apDashboardAi" class="badge text-bg-secondary align-self-start">Checking…</span>
          </div>
        </div>

        <div id="apDashboardError" class="alert alert-warning mt-3 mb-0 d-none" role="alert"></div>
      </div>
    </article>
  </div>

  <div class="col-12 col-xl-5">
    <article class="card ap-card h-100">
      <header class="card-header ap-card-head">
        <div>
          <h4 class="ap-card-title mb-1">Operational Views</h4>
          <p class="ap-card-sub mb-0">Open deeper deterministic diagnostics only when needed.</p>
        </div>
      </header>
      <div class="card-body">
        <div class="list-group list-group-flush">
          <a class="list-group-item list-group-item-action px-0" href="<?= htmlspecialchars($routeHref('live-stats'), ENT_QUOTES, 'UTF-8') ?>"><i class="bi bi-activity me-2"></i>Live Stack Telemetry</a>
          <a class="list-group-item list-group-item-action px-0" href="<?= htmlspecialchars($routeHref('db-health'), ENT_QUOTES, 'UTF-8') ?>"><i class="bi bi-database-check me-2"></i>Database Health</a>
          <a class="list-group-item list-group-item-action px-0" href="<?= htmlspecialchars($routeHref('queue-health'), ENT_QUOTES, 'UTF-8') ?>"><i class="bi bi-list-task me-2"></i>Queue / Cron Health</a>
          <a class="list-group-item list-group-item-action px-0" href="<?= htmlspecialchars($routeHref('tls-monitor'), ENT_QUOTES, 'UTF-8') ?>"><i class="bi bi-shield-lock me-2"></i>TLS / mTLS Monitor</a>
          <a class="list-group-item list-group-item-action px-0" href="<?= htmlspecialchars($routeHref('volume-monitor'), ENT_QUOTES, 'UTF-8') ?>"><i class="bi bi-device-ssd me-2"></i>Volumes / Inodes</a>
          <a class="list-group-item list-group-item-action px-0" href="<?= htmlspecialchars($routeHref('drift-monitor'), ENT_QUOTES, 'UTF-8') ?>"><i class="bi bi-sliders me-2"></i>Configuration Drift</a>
          <a class="list-group-item list-group-item-action px-0" href="<?= htmlspecialchars($routeHref('logs'), ENT_QUOTES, 'UTF-8') ?>"><i class="bi bi-file-earmark-text me-2"></i>File Logs</a>
          <a class="list-group-item list-group-item-action px-0" href="<?= htmlspecialchars($routeHref('ai-assistant'), ENT_QUOTES, 'UTF-8') ?>"><i class="bi bi-stars me-2"></i>AI Assistant</a>
        </div>
      </div>
    </article>
  </div>
</section>

<script>
(() => {
  const base = document.body.dataset.apBase || '';
  const refresh = document.getElementById('apDashboardRefresh');
  const error = document.getElementById('apDashboardError');

  const setText = (id, value) => {
    const el = document.getElementById(id);
    if (el) el.textContent = String(value);
  };

  const count = (value) => Number.isFinite(Number(value)) ? Number(value) : 0;

  const setCheckSummary = (prefix, summary) => {
    const s = summary && typeof summary === 'object' ? summary : {};
    setText(prefix + 'Pass', 'Pass ' + count(s.pass));
    setText(prefix + 'Warn', 'Warn ' + count(s.warn));
    setText(prefix + 'Fail', 'Fail ' + count(s.fail));
  };

  const fetchJson = async (path) => {
    const res = await fetch(base + path, {headers: {'Accept': 'application/json'}, cache: 'no-store'});
    const data = await res.json();
    if (!res.ok || data.ok === false) {
      throw new Error(data.message || data.error || ('Request failed: ' + path));
    }
    return data;
  };

  const load = async () => {
    refresh.disabled = true;
    error.classList.add('d-none');
    setText('apDashboardGenerated', 'Refreshing…');

    const [statusResult, aiResult] = await Promise.allSettled([
      fetchJson('/api/live-stats'),
      fetchJson('/api/ai-assistant')
    ]);

    if (statusResult.status === 'fulfilled') {
      const payload = statusResult.value;
      const summary = payload.summary || {};
      const core = (payload.data && payload.data.core) || {};

      setText('apDashboardProject', core.project || 'unknown');
      setText('apDashboardProfiles', 'Profiles: ' + (core.profiles || 'default'));
      setText('apDashboardContainers', count(summary.running) + ' / ' + count(summary.total));
      setText('apDashboardHealth', 'Health: ' + count(summary.healthy) + ' healthy · ' + count(summary.unhealthy) + ' unhealthy · ' + count(summary.no_health) + ' unchecked');
      setText('apDashboardProblems', count(summary.problem_count));
      setText('apDashboardChecks', 'Project checks: ' + count((summary.project_checks || {}).pass) + ' pass · ' + count((summary.project_checks || {}).fail) + ' fail');
      setText('apDashboardUrls', count(summary.url_count));
      setText('apDashboardPorts', 'Published ports: ' + count(summary.port_count));
      setCheckSummary('apSystem', summary.system_checks);
      setCheckSummary('apProject', summary.project_checks);
      setText('apDashboardGenerated', payload.generated_at ? ('Updated ' + payload.generated_at) : 'Updated');
    } else {
      error.textContent = 'Stack status unavailable: ' + String(statusResult.reason && statusResult.reason.message ? statusResult.reason.message : statusResult.reason);
      error.classList.remove('d-none');
      setText('apDashboardGenerated', 'Status unavailable');
    }

    const ai = document.getElementById('apDashboardAi');
    if (aiResult.status === 'fulfilled' && aiResult.value.available) {
      ai.className = 'badge text-bg-success align-self-start';
      ai.textContent = 'Available' + (aiResult.value.model ? ' · ' + aiResult.value.model : '');
    } else {
      ai.className = 'badge text-bg-secondary align-self-start';
      ai.textContent = 'Unavailable / optional';
    }

    refresh.disabled = false;
  };

  refresh.addEventListener('click', load);
  load();
})();
</script>
