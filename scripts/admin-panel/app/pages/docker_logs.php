<?php
declare(strict_types=1);
?>

<section class="ap-page-head">
  <div>
    <p class="ap-breadcrumb mb-1">Home / Monitoring / Docker Logs</p>
    <h2 class="ap-page-title mb-1">Docker Logs</h2>
    <p class="ap-page-sub mb-0">Service-grouped container logs.</p>
  </div>
  <div class="d-flex align-items-center gap-2 flex-wrap">
    <div id="apDockerLogsRefreshMeta" class="ap-live-refresh-meta" aria-live="polite">
      <div class="ap-live-meta-row">
        <span id="apDockerLogsUpdatedAt" class="ap-live-meta">Next refresh in --:--</span>
        <div class="ap-live-meta-controls">
          <label class="ap-live-auto-switch" for="apDockerLogsAuto">
            <span class="ap-live-auto-switch-label">Auto</span>
            <input id="apDockerLogsAuto" type="checkbox" role="switch" aria-label="Auto refresh docker logs">
          </label>
          <button id="apDockerLogsRefreshBtn" class="btn ap-live-meta-refresh" type="button" aria-label="Refresh docker logs" title="Refresh">
            <i class="bi bi-arrow-repeat"></i>
          </button>
        </div>
      </div>
      <span class="ap-live-countdown-track" aria-hidden="true">
        <span id="apDockerLogsCountdownBar" class="ap-live-countdown-bar"></span>
      </span>
      <small id="apDockerLogsLastUpdated" class="ap-live-meta-sub">Waiting for first snapshot...</small>
    </div>
  </div>
</section>

<div id="apDockerLogsError" class="ap-live-error d-none mb-2" role="status" aria-live="polite"></div>

<section class="row g-3 mt-1">
  <div class="col-12">
    <article class="card ap-card h-100">
      <header class="card-header ap-card-head ap-card-head-wrap">
        <div>
          <h4 class="ap-card-title mb-1">Docker Error Heatmap <span id="apDockerHeatErrorCount" class="ap-badge ap-live-state-unhealthy">0</span></h4>
          <p class="ap-card-sub mb-0">Top error signatures grouped by docker service and time bucket.</p>
        </div>
        <button id="apDockerHeatToggleBtn" class="btn ap-ghost-btn" type="button" aria-expanded="false" aria-controls="apDockerHeatBody" title="Expand section">
          <i id="apDockerHeatToggleIcon" class="bi bi-chevron-down"></i>
        </button>
      </header>
      <div id="apDockerHeatBody" class="card-body d-none">
        <div id="apDockerHeatSummary" class="ap-monitor-summary mb-3"></div>
        <div class="table-responsive ap-local-sticky mb-3">
          <table class="table ap-table ap-table-sticky ap-table-emphasis mb-0">
            <thead><tr><th>Signature</th><th class="text-end">Count</th></tr></thead>
            <tbody id="apDockerHeatSigRows">
            <tr><td colspan="2" class="text-center ap-page-sub py-4">Loading...</td></tr>
            </tbody>
          </table>
        </div>
        <div class="table-responsive ap-local-sticky">
          <table class="table ap-table ap-table-sticky ap-table-emphasis mb-0">
            <thead><tr><th>Service</th><th class="text-end">Count</th><th>Bucket Distribution</th></tr></thead>
            <tbody id="apDockerHeatServiceRows">
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
      <header class="card-header ap-card-head ap-card-head-wrap">
        <div>
          <h4 class="ap-card-title mb-1">Filters</h4>
          <p id="apDockerLogsMeta" class="ap-card-sub mb-0">Filter and inspect grouped service logs.</p>
        </div>
        <div class="ap-head-tools">
          <div class="ap-live-matrix-tools">
            <select id="apDockerLogsSince" class="form-select form-select-sm ap-docker-tool-select" aria-label="Since window">
              <option value="10m">Since: 10m</option>
              <option value="30m" selected>Since: 30m</option>
              <option value="1h">Since: 1h</option>
              <option value="6h">Since: 6h</option>
              <option value="24h">Since: 24h</option>
            </select>
            <select id="apDockerLogsTail" class="form-select form-select-sm ap-docker-tool-select" aria-label="Tail per container">
              <option value="50">Tail: 50</option>
              <option value="80" selected>Tail: 80</option>
              <option value="120">Tail: 120</option>
              <option value="200">Tail: 200</option>
              <option value="300">Tail: 300</option>
              <option value="500">Tail: 500</option>
            </select>
            <input id="apDockerLogsGrep" class="form-control form-control-sm ap-live-tool-input" type="search" placeholder="Search lines (substring)" aria-label="Search">
          </div>
        </div>
      </header>
      <div class="card-body">
        <div class="ap-docker-services-pane">
          <label class="form-label mb-1">Services</label>
          <div class="ap-docker-tabs-wrap">
            <ul id="apDockerLogsTabs" class="nav nav-tabs ap-docker-tabs" role="tablist" aria-label="Docker log services">
              <li class="nav-item" role="presentation">
                <button class="nav-link active" id="apDockerTab-all" data-bs-toggle="tab" data-bs-target="#apDockerTabPane" type="button" role="tab" aria-controls="apDockerTabPane" aria-selected="true" data-service-tab="all">All</button>
              </li>
            </ul>
          </div>
          <select id="apDockerLogsService" class="form-select d-none" aria-hidden="true" tabindex="-1">
            <option value="all">All services</option>
          </select>
          <div class="tab-content mt-2">
            <div class="tab-pane fade show active" id="apDockerTabPane" role="tabpanel" aria-labelledby="apDockerTab-all" tabindex="0">
              <section id="apDockerLogsGroups" class="row g-3"></section>
            </div>
          </div>
        </div>
      </div>
    </article>
  </div>
</section>

<script>
  (function () {
    "use strict";

    var root = document.getElementById("apDockerLogsGroups");
    if (!root) {
      return;
    }

    var basePath = (document.body && document.body.getAttribute("data-ap-base")) || "";
    if (basePath === "/") {
      basePath = "";
    }
    var apiUrl = basePath + "/api/docker-logs";
    var heatmapApiUrl = basePath + "/api/log-heatmap";

    var serviceEl = document.getElementById("apDockerLogsService");
    var tabsEl = document.getElementById("apDockerLogsTabs");
    var sinceEl = document.getElementById("apDockerLogsSince");
    var grepEl = document.getElementById("apDockerLogsGrep");
    var tailEl = document.getElementById("apDockerLogsTail");
    var autoBtn = document.getElementById("apDockerLogsAuto");
    var refreshBtn = document.getElementById("apDockerLogsRefreshBtn");
    var metaEl = document.getElementById("apDockerLogsMeta");
    var errEl = document.getElementById("apDockerLogsError");
    var refreshMetaEl = document.getElementById("apDockerLogsRefreshMeta");
    var updatedAtEl = document.getElementById("apDockerLogsUpdatedAt");
    var lastUpdatedEl = document.getElementById("apDockerLogsLastUpdated");
    var countdownBarEl = document.getElementById("apDockerLogsCountdownBar");
    var heatSummaryEl = document.getElementById("apDockerHeatSummary");
    var heatSigRowsEl = document.getElementById("apDockerHeatSigRows");
    var heatServiceRowsEl = document.getElementById("apDockerHeatServiceRows");
    var heatErrorCountEl = document.getElementById("apDockerHeatErrorCount");
    var heatBodyEl = document.getElementById("apDockerHeatBody");
    var heatToggleBtn = document.getElementById("apDockerHeatToggleBtn");
    var heatToggleIcon = document.getElementById("apDockerHeatToggleIcon");

    var refreshTimer = null;
    var refreshCountdownTimer = null;
    var refreshIntervalMs = 5000;
    var nextRefreshAt = 0;
    var lastGeneratedAt = "";
    var activeProject = "-";
    var loading = false;
    var heatFetchInFlight = false;

    function esc(value) {
      return String(value || "")
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;")
        .replace(/'/g, "&#039;");
    }

    function toTitleWords(value) {
      return String(value || "")
        .split(/[_\s-]+/)
        .filter(function (part) { return part !== ""; })
        .map(function (part) {
          return part.charAt(0).toUpperCase() + part.slice(1).toLowerCase();
        })
        .join(" ");
    }

    function numberText(value) {
      var n = Number(value);
      if (!isFinite(n) || n < 0) {
        return "-";
      }
      return String(Math.round(n));
    }

    function stateIconMeta(state) {
      var s = String(state || "").toLowerCase();
      if (s === "running") {
        return { icon: "bi-play-circle-fill", label: "Running", tone: "ap-live-health-healthy", spin: false, badge: "ap-live-state-running" };
      }
      if (s === "restarting") {
        return { icon: "bi-arrow-repeat", label: "Restarting", tone: "ap-live-health-degraded", spin: true, badge: "ap-live-state-starting" };
      }
      if (s === "starting" || s === "created" || s === "paused") {
        return { icon: s === "paused" ? "bi-pause-circle-fill" : "bi-hourglass-split", label: toTitleWords(s || "starting"), tone: "ap-live-health-degraded", spin: false, badge: "ap-live-state-starting" };
      }
      if (s === "exited" || s === "dead" || s === "stopped") {
        return { icon: "bi-x-octagon-fill", label: toTitleWords(s), tone: "ap-live-health-failing", spin: false, badge: "ap-live-state-unhealthy" };
      }
      return { icon: "bi-question-circle-fill", label: toTitleWords(s || "unknown"), tone: "ap-live-health-degraded", spin: false, badge: "ap-live-state-no-health" };
    }

    function healthIconMeta(health) {
      var h = String(health || "").toLowerCase();
      if (h === "healthy") {
        return { icon: "&#9829;", label: "Healthy", tone: "ap-live-health-healthy", pulse: false, badge: "ap-live-state-running" };
      }
      if (h === "unhealthy") {
        return { icon: "&#9829;", label: "Unhealthy", tone: "ap-live-health-failing", pulse: true, badge: "ap-live-state-unhealthy" };
      }
      return { icon: "!", label: toTitleWords(h || "no health"), tone: "ap-live-health-degraded", pulse: false, badge: "ap-live-state-starting" };
    }

    function renderKv(key, value, toneCls) {
      return '<span class="ap-kv-group ' + esc(String(toneCls || "ap-live-state-info")) + '"><span class="ap-kv-group-key">' + esc(key) + '</span><span class="ap-kv-group-val">' + esc(value) + "</span></span>";
    }

    function renderStateBadge(state) {
      var meta = stateIconMeta(state);
      var spinCls = meta.spin ? " ap-state-icon-spin" : "";
      return ''
        + '<span class="ap-badge ap-docker-status-badge ' + esc(meta.badge) + '">'
        + '  <span class="ap-state-icon ' + esc(meta.tone) + spinCls + '" title="state: ' + esc(meta.label) + '" aria-label="state: ' + esc(meta.label) + '"><i class="bi ' + esc(meta.icon) + '"></i></span>'
        + '  <span class="ap-docker-status-label">' + esc(meta.label) + '</span>'
        + "</span>";
    }

    function renderHealthBadge(health) {
      var meta = healthIconMeta(health);
      var pulseCls = meta.pulse ? " ap-health-icon-pulse" : "";
      return ''
        + '<span class="ap-badge ap-docker-status-badge ' + esc(meta.badge) + '">'
        + '  <span class="ap-health-icon ' + esc(meta.tone) + pulseCls + '" title="health: ' + esc(meta.label) + '" aria-label="health: ' + esc(meta.label) + '">' + meta.icon + "</span>"
        + '  <span class="ap-docker-status-label">' + esc(meta.label) + '</span>'
        + "</span>";
    }

    function showError(message) {
      if (!errEl) {
        return;
      }
      var text = String(message || "").trim();
      if (text === "") {
        errEl.classList.add("d-none");
        errEl.textContent = "";
        return;
      }
      errEl.classList.remove("d-none");
      errEl.textContent = text;
    }

    function setLoading(isLoading) {
      loading = !!isLoading;
      if (refreshBtn) {
        refreshBtn.disabled = loading;
        var icon = refreshBtn.querySelector("i");
        if (icon) {
          icon.className = loading ? "bi bi-arrow-repeat ap-spin" : "bi bi-arrow-repeat";
        }
      }
      updateRefreshMeta();
    }

    function padTwo(value) {
      var n = Math.max(0, Number(value) || 0);
      return n < 10 ? ("0" + String(n)) : String(n);
    }

    function formatCountdown(valueMs) {
      var totalSeconds = Math.max(0, Math.ceil((Number(valueMs) || 0) / 1000));
      var minutes = Math.floor(totalSeconds / 60);
      var seconds = totalSeconds % 60;
      return padTwo(minutes) + ":" + padTwo(seconds);
    }

    function formatUpdatedAt(value) {
      var raw = String(value || "").trim();
      if (!raw) {
        return "-";
      }
      var parsed = new Date(raw);
      if (!parsed || !isFinite(parsed.getTime())) {
        return raw;
      }
      try {
        return parsed.toLocaleString(undefined, {
          year: "numeric",
          month: "short",
          day: "2-digit",
          hour: "2-digit",
          minute: "2-digit",
          second: "2-digit",
          hour12: false
        });
      } catch (e) {
        return parsed.toISOString();
      }
    }

    function clearNextRefresh() {
      if (refreshTimer) {
        window.clearTimeout(refreshTimer);
        refreshTimer = null;
      }
      nextRefreshAt = 0;
    }

    function scheduleNextRefresh(delayMs) {
      clearNextRefresh();
      var wait = Math.max(0, Number(delayMs) || 0);
      refreshIntervalMs = wait > 0 ? wait : 5000;
      nextRefreshAt = wait > 0 ? Date.now() + wait : 0;
      updateRefreshMeta();
      if (wait > 0) {
        refreshTimer = window.setTimeout(refreshLogs, wait);
      }
    }

    function ensureCountdownTicker() {
      if (refreshCountdownTimer) {
        return;
      }
      refreshCountdownTimer = window.setInterval(updateRefreshMeta, 250);
    }

    function updateRefreshMeta() {
      var hasNext = nextRefreshAt > 0;
      var remainingMs = hasNext ? Math.max(0, nextRefreshAt - Date.now()) : 0;

      if (updatedAtEl) {
        if (loading) {
          updatedAtEl.textContent = "Refreshing docker logs...";
        } else if (hasNext) {
          updatedAtEl.textContent = "Next refresh in " + formatCountdown(remainingMs);
        } else {
          updatedAtEl.textContent = "Next refresh in --:--";
        }
      }

      if (lastUpdatedEl) {
        if (lastGeneratedAt) {
          lastUpdatedEl.textContent = "Last update " + formatUpdatedAt(lastGeneratedAt) + " | Project " + activeProject;
        } else if (loading) {
          lastUpdatedEl.textContent = "Waiting for response...";
        } else {
          lastUpdatedEl.textContent = "Waiting for first snapshot...";
        }
      }

      if (refreshMetaEl) {
        refreshMetaEl.classList.toggle("is-loading", loading);
      }

      if (countdownBarEl) {
        if (loading) {
          countdownBarEl.style.width = "38%";
        } else if (!hasNext || refreshIntervalMs <= 0) {
          countdownBarEl.style.width = "0%";
        } else {
          var elapsedMs = refreshIntervalMs - remainingMs;
          var percent = Math.max(0, Math.min(100, (elapsedMs / refreshIntervalMs) * 100));
          countdownBarEl.style.width = percent.toFixed(2) + "%";
        }
      }
    }

    function getFilters() {
      var service = serviceEl ? String(serviceEl.value || "all").trim().toLowerCase() : "all";
      var since = sinceEl ? String(sinceEl.value || "").trim() : "";
      var grep = grepEl ? String(grepEl.value || "").trim() : "";
      var tail = 80;
      if (tailEl) {
        var parsed = Number(tailEl.value || "80");
        if (isFinite(parsed) && parsed > 0) {
          tail = Math.max(1, Math.min(500, Math.round(parsed)));
        }
      }

      return { service: service, since: since, grep: grep, tail: tail };
    }

    function isAutoRefreshEnabled() {
      return !!(autoBtn && autoBtn.checked);
    }

    function bindServiceTabs() {
      if (!tabsEl || !serviceEl) {
        return;
      }
      Array.prototype.slice.call(tabsEl.querySelectorAll("[data-service-tab]")).forEach(function (btn) {
        btn.addEventListener("click", function (event) {
          event.preventDefault();
          var selected = String(btn.getAttribute("data-service-tab") || "all").toLowerCase();
          serviceEl.value = selected;
          Array.prototype.slice.call(tabsEl.querySelectorAll(".nav-link")).forEach(function (node) {
            node.classList.toggle("active", node === btn);
            node.setAttribute("aria-selected", node === btn ? "true" : "false");
          });
          refreshLogs();
        });
      });
    }

    function renderServiceTabs(servicesAvailable, activeService) {
      if (!tabsEl) {
        return;
      }
      var services = Array.isArray(servicesAvailable) ? servicesAvailable : [];
      var selected = String(activeService || "all").toLowerCase();
      var items = ['<li class="nav-item" role="presentation"><button class="nav-link' + (selected === "all" ? ' active' : '') + '" id="apDockerTab-all" data-bs-toggle="tab" data-bs-target="#apDockerTabPane" type="button" role="tab" aria-controls="apDockerTabPane" aria-selected="' + (selected === "all" ? 'true' : 'false') + '" data-service-tab="all">All</button></li>'];
      services.forEach(function (svc) {
        var val = String(svc || "").trim().toLowerCase();
        if (val === "") {
          return;
        }
        items.push('<li class="nav-item" role="presentation"><button class="nav-link' + (selected === val ? ' active' : '') + '" id="apDockerTab-' + esc(val) + '" data-bs-toggle="tab" data-bs-target="#apDockerTabPane" type="button" role="tab" aria-controls="apDockerTabPane" aria-selected="' + (selected === val ? 'true' : 'false') + '" data-service-tab="' + esc(val) + '">' + esc(val) + '</button></li>');
      });
      tabsEl.innerHTML = items.join("");
      bindServiceTabs();
    }

    function updateServiceOptions(servicesAvailable) {
      if (!serviceEl) {
        return;
      }
      var selected = String(serviceEl.value || "all").toLowerCase();
      var options = ['<option value="all">All services</option>'];
      (Array.isArray(servicesAvailable) ? servicesAvailable : []).forEach(function (svc) {
        var val = String(svc || "").trim().toLowerCase();
        if (val === "") {
          return;
        }
        options.push('<option value="' + esc(val) + '">' + esc(val) + "</option>");
      });
      serviceEl.innerHTML = options.join("");

      if (selected !== "all" && Array.isArray(servicesAvailable) && servicesAvailable.indexOf(selected) !== -1) {
        serviceEl.value = selected;
      } else {
        serviceEl.value = "all";
      }
      renderServiceTabs(servicesAvailable, serviceEl.value || "all");
    }

    function renderGroups(payload) {
      var groups = Array.isArray(payload && payload.groups) ? payload.groups : [];
      if (groups.length === 0) {
        root.innerHTML = '<div class="col-12"><article class="card ap-card"><div class="card-body"><p class="ap-page-sub mb-0">No logs found for the selected filters.</p></div></article></div>';
        return;
      }

      var html = groups.map(function (group) {
        var service = String(group && group.service || "unknown");
        var lines = Array.isArray(group && group.lines) ? group.lines : [];
        var containers = Array.isArray(group && group.containers) ? group.containers : [];
        var lineCount = Number(group && group.line_count || lines.length || 0);
        var preview = lines.length > 0 ? lines.join("\n") : "(no lines)";
        var rows = (containers.length > 0 ? containers : [{}]).map(function (c) {
          var rawName = String(c && c.name || "unknown").trim();
          var name = rawName === "" ? "UNKNOWN" : rawName.toUpperCase();
          var state = String(c && c.state || "");
          var health = String(c && c.health || "");
          return ''
            + '<div class="ap-docker-summary-row">'
            + renderKv("Lines", String(lineCount), "ap-live-state-info")
            + renderKv("Containers", String(containers.length), "ap-live-state-info")
            + renderKv("Name", name, "ap-live-state-no-health")
            + renderStateBadge(state)
            + renderHealthBadge(health)
            + "</div>";
        }).join("");

        return ''
          + '<div class="col-12">'
          + '  <article class="card ap-card">'
          + '    <header class="card-header ap-card-head">'
          + '      <div>'
          + '        <h4 class="ap-card-title mb-0">' + esc(service) + '</h4>'
          + '      </div>'
          + '    </header>'
          + '    <div class="card-body">'
          + '      <div class="ap-docker-summary-lines mb-2">' + rows + '</div>'
          + '      <pre class="ap-docker-logs-pre mb-0">' + esc(preview) + '</pre>'
          + '    </div>'
          + '  </article>'
          + '</div>';
      }).join("");

      root.innerHTML = html;
    }

    function renderDockerHeatSummary(summary) {
      if (!heatSummaryEl) {
        return;
      }
      var s = summary && typeof summary === "object" ? summary : {};
      if (heatErrorCountEl) {
        heatErrorCountEl.textContent = numberText(s.errors === "-" ? 0 : s.errors);
      }
      heatSummaryEl.innerHTML = ""
        + '<span class="ap-kv-group ap-live-state-unhealthy"><span class="ap-kv-group-key">Errors</span><span class="ap-kv-group-val">' + numberText(s.errors) + "</span></span>"
        + '<span class="ap-kv-group ap-live-state-info"><span class="ap-kv-group-key">Services</span><span class="ap-kv-group-val">' + numberText(s.services) + "</span></span>"
        + '<span class="ap-kv-group ap-live-state-info"><span class="ap-kv-group-key">Buckets</span><span class="ap-kv-group-val">' + numberText(s.buckets) + "</span></span>"
        + '<span class="ap-kv-group ap-live-state-info"><span class="ap-kv-group-key">Top Signatures</span><span class="ap-kv-group-val">' + numberText(s.top_signatures) + "</span></span>";
    }

    function renderDockerHeatSigRows(rows) {
      if (!heatSigRowsEl) {
        return;
      }
      var items = Array.isArray(rows) ? rows : [];
      heatSigRowsEl.innerHTML = items.length === 0
        ? '<tr><td colspan="2" class="text-center ap-page-sub py-4">No error signatures found.</td></tr>'
        : items.map(function (row) {
          return '<tr><td>' + esc(String(row.signature || "-")) + '</td><td class="text-end">' + numberText(row.count) + '</td></tr>';
        }).join("");
    }

    function renderDockerHeatServiceRows(rows) {
      if (!heatServiceRowsEl) {
        return;
      }
      var items = Array.isArray(rows) ? rows : [];
      heatServiceRowsEl.innerHTML = items.length === 0
        ? '<tr><td colspan="3" class="text-center ap-page-sub py-4">No docker service heatmap rows found.</td></tr>'
        : items.map(function (row) {
          var heat = Array.isArray(row.heatmap) ? row.heatmap : [];
          var dist = heat.map(function (h) {
            var ts = Number(h && h.bucket_epoch || 0);
            var cnt = numberText(h && h.count);
            if (!isFinite(ts) || ts <= 0) {
              return cnt;
            }
            var d = new Date(ts * 1000);
            var label = isFinite(d.getTime()) ? d.toISOString().slice(11, 16) : String(ts);
            return label + " (" + cnt + ")";
          }).join(" | ");
          return ''
            + '<tr>'
            + '  <td>' + esc(String(row.service || "-")) + '</td>'
            + '  <td class="text-end">' + numberText(row.count) + '</td>'
            + '  <td>' + esc(dist || "-") + '</td>'
            + '</tr>';
        }).join("");
    }

    function refreshDockerHeatmap(since) {
      if (heatFetchInFlight || !heatmapApiUrl) {
        return;
      }
      heatFetchInFlight = true;
      var qp = new URLSearchParams();
      qp.set("source", "docker");
      qp.set("since", String(since || "30m"));
      qp.set("bucket_min", "15");
      qp.set("top", "8");
      qp.set("line_limit", "1000");
      fetch(heatmapApiUrl + "?" + qp.toString(), {
        method: "GET",
        credentials: "same-origin",
        cache: "no-store",
        headers: { "Accept": "application/json" }
      })
        .then(function (res) {
          return res.json().catch(function () { return null; }).then(function (json) {
            return { status: res.status, ok: res.ok, json: json };
          });
        })
        .then(function (result) {
          var payload = result && result.json && typeof result.json === "object" ? result.json : {};
          if (!result.ok || !payload.ok) {
            throw new Error("docker heatmap api failed");
          }
          renderDockerHeatSummary(payload.summary || {});
          renderDockerHeatSigRows(payload.top_signatures || []);
          renderDockerHeatServiceRows(payload.services || []);
        })
        .catch(function () {
          renderDockerHeatSummary({});
          renderDockerHeatSigRows([]);
          renderDockerHeatServiceRows([]);
        })
        .finally(function () {
          heatFetchInFlight = false;
        });
    }

    function setDockerHeatCollapsed(collapsed) {
      var isCollapsed = !!collapsed;
      if (heatBodyEl) {
        heatBodyEl.classList.toggle("d-none", isCollapsed);
      }
      if (heatToggleBtn) {
        heatToggleBtn.setAttribute("aria-expanded", isCollapsed ? "false" : "true");
        heatToggleBtn.setAttribute("title", isCollapsed ? "Expand section" : "Collapse section");
      }
      if (heatToggleIcon) {
        heatToggleIcon.className = "bi " + (isCollapsed ? "bi-chevron-down" : "bi-chevron-up");
      }
    }

    function buildUrl() {
      var filters = getFilters();
      var qp = new URLSearchParams();
      qp.set("tail", String(filters.tail));
      if (filters.service !== "" && filters.service !== "all") {
        qp.set("service", filters.service);
      }
      if (filters.since !== "") {
        qp.set("since", filters.since);
      }
      if (filters.grep !== "") {
        qp.set("grep", filters.grep);
      }
      return apiUrl + "?" + qp.toString();
    }

    function refreshLogs() {
      if (loading) {
        return;
      }
      clearNextRefresh();
      setLoading(true);
      showError("");

      fetch(buildUrl(), {
        method: "GET",
        credentials: "same-origin",
        cache: "no-store",
        headers: { "Accept": "application/json" }
      })
        .then(function (res) {
          return res.json().catch(function () { return null; }).then(function (json) {
            return { status: res.status, ok: res.ok, json: json };
          });
        })
        .then(function (result) {
          var payload = result && result.json && typeof result.json === "object" ? result.json : {};
          if (!result.ok || !payload.ok) {
            var msg = payload && payload.message ? payload.message : ("docker logs api failed (" + String(result.status || 500) + ")");
            throw new Error(msg);
          }

          updateServiceOptions(payload.services_available || []);
          renderGroups(payload);
          lastGeneratedAt = String(payload.generated_at || "");
          activeProject = String(payload.project || "-");
          refreshDockerHeatmap(getFilters().since);

          if (metaEl) {
            metaEl.textContent = "Project: " + activeProject + " | Services: " + String((payload.services_available || []).length);
          }
        })
        .catch(function (err) {
          renderGroups({ groups: [] });
          showError(err && err.message ? err.message : "Unable to load docker logs.");
        })
        .finally(function () {
          setLoading(false);
          if (isAutoRefreshEnabled()) {
            scheduleNextRefresh(5000);
          } else {
            clearNextRefresh();
            updateRefreshMeta();
          }
        });
    }

    function rebindAutoRefresh() {
      if (isAutoRefreshEnabled()) {
        scheduleNextRefresh(5000);
      } else {
        clearNextRefresh();
        updateRefreshMeta();
      }
    }

    if (refreshBtn) {
      refreshBtn.addEventListener("click", refreshLogs);
    }
    if (serviceEl) {
      serviceEl.addEventListener("change", refreshLogs);
    }
    if (sinceEl) {
      sinceEl.addEventListener("change", refreshLogs);
    }
    if (tailEl) {
      tailEl.addEventListener("change", refreshLogs);
    }
    if (grepEl) {
      grepEl.addEventListener("keydown", function (e) {
        if (e.key === "Enter") {
          e.preventDefault();
          refreshLogs();
        }
      });
    }
    if (autoBtn) {
      autoBtn.addEventListener("change", function () {
        var enabled = !!autoBtn.checked;
        rebindAutoRefresh();
        if (enabled) {
          refreshLogs();
        } else {
          updateRefreshMeta();
        }
      });
    }
    if (heatToggleBtn) {
      heatToggleBtn.addEventListener("click", function () {
        var collapsed = heatBodyEl ? !heatBodyEl.classList.contains("d-none") : true;
        setDockerHeatCollapsed(collapsed);
      });
    }

    function startInitialLoad() {
      refreshLogs();
    }

    ensureCountdownTicker();
    setDockerHeatCollapsed(true);
    rebindAutoRefresh();
    if (document.readyState === "complete") {
      window.setTimeout(startInitialLoad, 0);
    } else {
      window.addEventListener("load", startInitialLoad, { once: true });
    }
  })();
</script>
