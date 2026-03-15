<?php
declare(strict_types=1);
?>

<section class="ap-page-head">
  <div>
    <p class="ap-breadcrumb mb-1">Home / Monitoring / Queue / Cron</p>
    <h2 class="ap-page-title mb-1">Queue / Cron Health</h2>
    <p class="ap-page-sub mb-0">Stuck queue backlog, oldest pending age, scheduler heartbeat, and failed job signals.</p>
  </div>
  <div class="d-flex align-items-center gap-2 flex-wrap">
    <div id="apQueueRefreshMeta" class="ap-live-refresh-meta" aria-live="polite">
      <div class="ap-live-meta-row">
        <span id="apQueueUpdatedAt" class="ap-live-meta">Next refresh in --:--</span>
        <div class="ap-live-meta-controls">
          <label class="ap-live-auto-switch" for="apQueueAuto">
            <span class="ap-live-auto-switch-label">Auto</span>
            <input id="apQueueAuto" type="checkbox" role="switch" aria-label="Auto refresh queue health">
          </label>
          <button id="apQueueRefreshBtn" class="btn ap-live-meta-refresh" type="button" aria-label="Refresh queue health" title="Refresh">
            <i class="bi bi-arrow-repeat"></i>
          </button>
        </div>
      </div>
      <span class="ap-live-countdown-track" aria-hidden="true">
        <span id="apQueueCountdownBar" class="ap-live-countdown-bar"></span>
      </span>
      <small id="apQueueLastUpdated" class="ap-live-meta-sub">Waiting for first snapshot...</small>
    </div>
  </div>
</section>

<div id="apQueueError" class="ap-live-error d-none mb-2" role="status" aria-live="polite"></div>

<section class="row g-3 mt-1">
  <div class="col-12">
    <article class="card ap-card h-100">
      <header class="card-header ap-card-head ap-card-head-wrap">
        <div>
          <h4 class="ap-card-title mb-1">Filters</h4>
          <p id="apQueueMeta" class="ap-card-sub mb-0">Track queue workers and scheduler health.</p>
        </div>
        <div class="ap-head-tools">
          <div class="ap-live-matrix-tools">
            <select id="apQueueSince" class="form-select form-select-sm ap-live-tool-select" aria-label="Window">
              <option value="30m">Since: 30m</option>
              <option value="60m" selected>Since: 1h</option>
              <option value="6h">Since: 6h</option>
              <option value="24h">Since: 24h</option>
            </select>
            <select id="apQueuePendingThreshold" class="form-select form-select-sm ap-live-tool-select" aria-label="Pending threshold">
              <option value="200">Pending >= 200</option>
              <option value="500" selected>Pending >= 500</option>
              <option value="1000">Pending >= 1000</option>
              <option value="2000">Pending >= 2000</option>
            </select>
            <select id="apQueueHeartbeatStaleSec" class="form-select form-select-sm ap-live-tool-select" aria-label="Heartbeat stale threshold">
              <option value="300">Heartbeat stale: 5m</option>
              <option value="900" selected>Heartbeat stale: 15m</option>
              <option value="1800">Heartbeat stale: 30m</option>
              <option value="3600">Heartbeat stale: 60m</option>
            </select>
          </div>
        </div>
      </header>
      <div class="card-body">
        <div id="apQueueSummary" class="ap-monitor-summary mb-3"></div>
        <div id="apQueueBackend" class="ap-monitor-summary mb-3"></div>
        <div class="table-responsive ap-local-sticky">
          <table class="table ap-table ap-table-sticky ap-table-emphasis mb-0">
            <thead>
            <tr>
              <th>Container</th>
              <th>Service</th>
              <th class="text-end">State</th>
              <th class="text-end">Processed</th>
              <th class="text-end">Failed</th>
              <th class="text-end">Failed %</th>
              <th class="text-end">Heartbeat Age (s)</th>
              <th class="text-end">Failed Jobs</th>
              <th>Note</th>
            </tr>
            </thead>
            <tbody id="apQueueRows">
            <tr><td colspan="9" class="text-center ap-page-sub py-4">Loading...</td></tr>
            </tbody>
          </table>
        </div>
      </div>
    </article>
  </div>
</section>

<script>
  (function () {
    "use strict";

    var rowsEl = document.getElementById("apQueueRows");
    if (!rowsEl) {
      return;
    }

    var basePath = (document.body && document.body.getAttribute("data-ap-base")) || "";
    if (basePath === "/") {
      basePath = "";
    }
    var apiUrl = basePath + "/api/queue-health";

    var sinceEl = document.getElementById("apQueueSince");
    var pendingThresholdEl = document.getElementById("apQueuePendingThreshold");
    var heartbeatStaleSecEl = document.getElementById("apQueueHeartbeatStaleSec");
    var autoBtn = document.getElementById("apQueueAuto");
    var refreshBtn = document.getElementById("apQueueRefreshBtn");
    var metaEl = document.getElementById("apQueueMeta");
    var summaryEl = document.getElementById("apQueueSummary");
    var backendEl = document.getElementById("apQueueBackend");
    var errEl = document.getElementById("apQueueError");
    var refreshMetaEl = document.getElementById("apQueueRefreshMeta");
    var updatedAtEl = document.getElementById("apQueueUpdatedAt");
    var lastUpdatedEl = document.getElementById("apQueueLastUpdated");
    var countdownBarEl = document.getElementById("apQueueCountdownBar");

    var refreshTimer = null;
    var refreshCountdownTimer = null;
    var refreshIntervalMs = 10000;
    var nextRefreshAt = 0;
    var lastGeneratedAt = "";
    var activeProject = "-";
    var loading = false;

    function esc(value) {
      return String(value || "")
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;")
        .replace(/'/g, "&#039;");
    }

    function toneClass(state) {
      var s = String(state || "").toLowerCase();
      if (s === "pass") {
        return "ap-live-state-running";
      }
      if (s === "fail") {
        return "ap-live-state-unhealthy";
      }
      return "ap-live-state-starting";
    }

    function numberText(value) {
      var n = Number(value);
      if (!isFinite(n) || n < 0) {
        return "-";
      }
      return String(Math.round(n));
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
      refreshIntervalMs = wait > 0 ? wait : 10000;
      nextRefreshAt = wait > 0 ? Date.now() + wait : 0;
      updateRefreshMeta();
      if (wait > 0) {
        refreshTimer = window.setTimeout(refreshSnapshot, wait);
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
          updatedAtEl.textContent = "Refreshing queue health...";
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
      return {
        since: sinceEl ? String(sinceEl.value || "60m").trim() : "60m",
        pendingThreshold: pendingThresholdEl ? Math.max(1, Number(pendingThresholdEl.value || "500")) : 500,
        heartbeatStaleSec: heartbeatStaleSecEl ? Math.max(60, Number(heartbeatStaleSecEl.value || "900")) : 900
      };
    }

    function isAutoRefreshEnabled() {
      return !!(autoBtn && autoBtn.checked);
    }

    function renderSummary(summary) {
      var data = summary && typeof summary === "object" ? summary : {};
      summaryEl.innerHTML = ""
        + '<span class="ap-kv-group ap-live-state-info"><span class="ap-kv-group-key">Workers</span><span class="ap-kv-group-val">' + esc(String(data.workers || 0)) + "</span></span>"
        + '<span class="ap-kv-group ap-live-state-running"><span class="ap-kv-group-key">Pass</span><span class="ap-kv-group-val">' + esc(String(data.pass || 0)) + "</span></span>"
        + '<span class="ap-kv-group ap-live-state-starting"><span class="ap-kv-group-key">Warn</span><span class="ap-kv-group-val">' + esc(String(data.warn || 0)) + "</span></span>"
        + '<span class="ap-kv-group ap-live-state-unhealthy"><span class="ap-kv-group-key">Fail</span><span class="ap-kv-group-val">' + esc(String(data.fail || 0)) + "</span></span>"
        + '<span class="ap-kv-group ap-live-state-starting"><span class="ap-kv-group-key">Stale Workers</span><span class="ap-kv-group-val">' + esc(String(data.stale_workers || 0)) + "</span></span>"
        + '<span class="ap-kv-group ap-live-state-unhealthy"><span class="ap-kv-group-key">Failed Jobs</span><span class="ap-kv-group-val">' + esc(String(data.failed_jobs_total || 0)) + "</span></span>";
    }

    function renderBackend(backend) {
      var data = backend && typeof backend === "object" ? backend : {};
      backendEl.innerHTML = ""
        + '<span class="ap-kv-group ap-live-state-info"><span class="ap-kv-group-key">Backend</span><span class="ap-kv-group-val">' + esc(String(data.type || "-")) + "</span></span>"
        + '<span class="ap-kv-group ap-live-state-info"><span class="ap-kv-group-key">Container</span><span class="ap-kv-group-val">' + esc(String(data.container || "-")) + "</span></span>"
        + '<span class="ap-kv-group ap-live-state-info"><span class="ap-kv-group-key">Pending</span><span class="ap-kv-group-val">' + numberText(data.pending) + "</span></span>"
        + '<span class="ap-kv-group ap-live-state-info"><span class="ap-kv-group-key">Delayed</span><span class="ap-kv-group-val">' + numberText(data.delayed) + "</span></span>"
        + '<span class="ap-kv-group ap-live-state-info"><span class="ap-kv-group-key">Reserved</span><span class="ap-kv-group-val">' + numberText(data.reserved) + "</span></span>"
        + '<span class="ap-kv-group ap-live-state-info"><span class="ap-kv-group-key">Oldest Age (s)</span><span class="ap-kv-group-val">' + numberText(data.oldest_pending_age_s) + "</span></span>"
        + '<span class="ap-kv-group ' + esc(toneClass(data.level || "warn")) + '"><span class="ap-kv-group-key">State</span><span class="ap-kv-group-val">' + esc(String(data.note || "-")) + "</span></span>";
    }

    function renderRows(payload) {
      var items = Array.isArray(payload && payload.items) ? payload.items : [];
      if (items.length === 0) {
        rowsEl.innerHTML = '<tr><td colspan="9" class="text-center ap-page-sub py-4">No queue worker signals found.</td></tr>';
        return;
      }
      items.sort(function (a, b) {
        return String(a && a.container || "").localeCompare(String(b && b.container || ""));
      });
      rowsEl.innerHTML = items.map(function (item) {
        return ""
          + "<tr>"
          + "  <td>" + esc(String(item && item.container || "-")) + "</td>"
          + "  <td>" + esc(String(item && item.service || "-")) + "</td>"
          + '  <td class="text-end">' + esc(String(item && item.state || "-")) + "</td>"
          + '  <td class="text-end">' + numberText(item && item.processed) + "</td>"
          + '  <td class="text-end">' + numberText(item && item.failed) + "</td>"
          + '  <td class="text-end">' + numberText(item && item.failed_rate_pct) + "</td>"
          + '  <td class="text-end">' + numberText(item && item.heartbeat_age_s) + "</td>"
          + '  <td class="text-end">' + numberText(item && item.failed_jobs) + "</td>"
          + '  <td><span class="ap-badge ' + esc(toneClass(item && item.level || "warn")) + '">' + esc(String(item && item.note || "-")) + "</span></td>"
          + "</tr>";
      }).join("");
    }

    function buildUrl() {
      var f = getFilters();
      var qp = new URLSearchParams();
      qp.set("since", f.since);
      qp.set("pending_threshold", String(Math.round(f.pendingThreshold)));
      qp.set("heartbeat_stale_sec", String(Math.round(f.heartbeatStaleSec)));
      return apiUrl + "?" + qp.toString();
    }

    function refreshSnapshot() {
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
            throw new Error(payload && payload.message ? payload.message : ("queue health api failed (" + String(result.status || 500) + ")"));
          }
          renderSummary(payload.summary || {});
          renderBackend(payload.queue_backend || {});
          renderRows(payload);
          lastGeneratedAt = String(payload.generated_at || "");
          activeProject = String(payload.project || "-");
          if (metaEl) {
            metaEl.textContent = "Project: " + activeProject + " | Workers: " + String((payload.summary && payload.summary.workers) || 0);
          }
        })
        .catch(function (err) {
          renderSummary({});
          renderBackend({});
          renderRows({ items: [] });
          showError(err && err.message ? err.message : "Unable to load queue health.");
        })
        .finally(function () {
          setLoading(false);
          if (isAutoRefreshEnabled()) {
            scheduleNextRefresh(10000);
          } else {
            clearNextRefresh();
            updateRefreshMeta();
          }
        });
    }

    function rebindAutoRefresh() {
      if (isAutoRefreshEnabled()) {
        scheduleNextRefresh(10000);
      } else {
        clearNextRefresh();
        updateRefreshMeta();
      }
    }

    if (refreshBtn) {
      refreshBtn.addEventListener("click", refreshSnapshot);
    }
    if (sinceEl) {
      sinceEl.addEventListener("change", refreshSnapshot);
    }
    if (pendingThresholdEl) {
      pendingThresholdEl.addEventListener("change", refreshSnapshot);
    }
    if (heartbeatStaleSecEl) {
      heartbeatStaleSecEl.addEventListener("change", refreshSnapshot);
    }
    if (autoBtn) {
      autoBtn.addEventListener("change", function () {
        var enabled = !!autoBtn.checked;
        rebindAutoRefresh();
        if (enabled) {
          refreshSnapshot();
        } else {
          updateRefreshMeta();
        }
      });
    }

    function startInitialLoad() {
      refreshSnapshot();
    }

    ensureCountdownTicker();
    rebindAutoRefresh();
    if (document.readyState === "complete") {
      window.setTimeout(startInitialLoad, 0);
    } else {
      window.addEventListener("load", startInitialLoad, { once: true });
    }
  })();
</script>
