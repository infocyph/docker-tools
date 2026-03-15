<?php
declare(strict_types=1);
?>

<section class="ap-page-head">
  <div>
    <p class="ap-breadcrumb mb-1">Home / Monitoring / Runtime Watch</p>
    <h2 class="ap-page-title mb-1">Runtime Watch</h2>
    <p class="ap-page-sub mb-0">Container crash loops, OOMs, and restart/event health.</p>
  </div>
  <div class="d-flex align-items-center gap-2 flex-wrap">
    <div id="apRuntimeRefreshMeta" class="ap-live-refresh-meta" aria-live="polite">
      <div class="ap-live-meta-row">
        <span id="apRuntimeUpdatedAt" class="ap-live-meta">Next refresh in --:--</span>
        <div class="ap-live-meta-controls">
          <label class="ap-live-auto-switch" for="apRuntimeAuto">
            <span class="ap-live-auto-switch-label">Auto</span>
            <input id="apRuntimeAuto" type="checkbox" role="switch" aria-label="Auto refresh runtime watch">
          </label>
          <button id="apRuntimeRefreshBtn" class="btn ap-live-meta-refresh" type="button" aria-label="Refresh runtime watch" title="Refresh">
            <i class="bi bi-arrow-repeat"></i>
          </button>
        </div>
      </div>
      <span class="ap-live-countdown-track" aria-hidden="true">
        <span id="apRuntimeCountdownBar" class="ap-live-countdown-bar"></span>
      </span>
      <small id="apRuntimeLastUpdated" class="ap-live-meta-sub">Waiting for first snapshot...</small>
    </div>
  </div>
</section>

<div id="apRuntimeError" class="ap-live-error d-none mb-2" role="status" aria-live="polite"></div>

<section class="row g-3 mt-1">
  <div class="col-12">
    <article class="card ap-card h-100">
      <header class="card-header ap-card-head ap-card-head-wrap">
        <div>
          <h4 class="ap-card-title mb-1">Filters</h4>
          <p id="apRuntimeMeta" class="ap-card-sub mb-0">Inspect restart/health/OOM signals.</p>
        </div>
        <div class="ap-head-tools">
          <div class="ap-live-matrix-tools">
            <select id="apRuntimeSince" class="form-select form-select-sm ap-live-tool-select" aria-label="Event window">
              <option value="15m">Since: 15m</option>
              <option value="60m" selected>Since: 1h</option>
              <option value="6h">Since: 6h</option>
              <option value="24h">Since: 24h</option>
            </select>
            <select id="apRuntimeRestartThreshold" class="form-select form-select-sm ap-live-tool-select" aria-label="Restart threshold">
              <option value="2">Restarts >= 2</option>
              <option value="3" selected>Restarts >= 3</option>
              <option value="4">Restarts >= 4</option>
              <option value="5">Restarts >= 5</option>
              <option value="8">Restarts >= 8</option>
            </select>
            <select id="apRuntimeEventLimit" class="form-select form-select-sm ap-live-tool-select" aria-label="Event limit">
              <option value="30">Events: 30</option>
              <option value="80" selected>Events: 80</option>
              <option value="150">Events: 150</option>
              <option value="300">Events: 300</option>
            </select>
          </div>
        </div>
      </header>
      <div class="card-body">
        <div id="apRuntimeSummary" class="ap-monitor-summary mb-3"></div>

        <h5 class="ap-card-title mb-2">Container Signals</h5>
        <div class="table-responsive ap-local-sticky mb-3">
          <table class="table ap-table ap-table-sticky ap-table-emphasis mb-0">
            <thead>
            <tr>
              <th>Container</th>
              <th>Service</th>
              <th class="text-end">State</th>
              <th class="text-end">Health</th>
              <th class="text-end">Restarts</th>
              <th class="text-end">OOM</th>
              <th class="text-end">Exit</th>
              <th>Issues</th>
            </tr>
            </thead>
            <tbody id="apRuntimeRows">
            <tr><td colspan="8" class="text-center ap-page-sub py-4">Loading...</td></tr>
            </tbody>
          </table>
        </div>

        <h5 class="ap-card-title mb-2">Recent Runtime Events</h5>
        <div class="table-responsive ap-local-sticky">
          <table class="table ap-table ap-table-sticky ap-table-emphasis mb-0">
            <thead>
            <tr>
              <th>Time</th>
              <th>Action</th>
              <th>Container</th>
              <th>Service</th>
              <th class="text-end">Exit</th>
            </tr>
            </thead>
            <tbody id="apRuntimeEventsRows">
            <tr><td colspan="5" class="text-center ap-page-sub py-4">Loading...</td></tr>
            </tbody>
          </table>
        </div>

        <h5 class="ap-card-title mb-2 mt-3">Event Trend</h5>
        <div class="table-responsive ap-local-sticky">
          <table class="table ap-table ap-table-sticky ap-table-emphasis mb-0">
            <thead>
            <tr>
              <th>Bucket</th>
              <th class="text-end">Total</th>
              <th class="text-end">OOM</th>
              <th class="text-end">Die</th>
              <th class="text-end">Restart</th>
              <th class="text-end">Start</th>
            </tr>
            </thead>
            <tbody id="apRuntimeTrendRows">
            <tr><td colspan="6" class="text-center ap-page-sub py-4">Loading...</td></tr>
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

    var rowsEl = document.getElementById("apRuntimeRows");
    var eventsRowsEl = document.getElementById("apRuntimeEventsRows");
    var trendRowsEl = document.getElementById("apRuntimeTrendRows");
    if (!rowsEl || !eventsRowsEl || !trendRowsEl) {
      return;
    }

    var basePath = (document.body && document.body.getAttribute("data-ap-base")) || "";
    if (basePath === "/") {
      basePath = "";
    }
    var apiUrl = basePath + "/api/runtime-watch";

    var sinceEl = document.getElementById("apRuntimeSince");
    var thresholdEl = document.getElementById("apRuntimeRestartThreshold");
    var eventLimitEl = document.getElementById("apRuntimeEventLimit");
    var autoBtn = document.getElementById("apRuntimeAuto");
    var refreshBtn = document.getElementById("apRuntimeRefreshBtn");
    var metaEl = document.getElementById("apRuntimeMeta");
    var summaryEl = document.getElementById("apRuntimeSummary");
    var errEl = document.getElementById("apRuntimeError");
    var refreshMetaEl = document.getElementById("apRuntimeRefreshMeta");
    var updatedAtEl = document.getElementById("apRuntimeUpdatedAt");
    var lastUpdatedEl = document.getElementById("apRuntimeLastUpdated");
    var countdownBarEl = document.getElementById("apRuntimeCountdownBar");

    var refreshTimer = null;
    var refreshCountdownTimer = null;
    var refreshIntervalMs = 8000;
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
      refreshIntervalMs = wait > 0 ? wait : 8000;
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
          updatedAtEl.textContent = "Refreshing runtime watch...";
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
      var threshold = thresholdEl ? Number(thresholdEl.value || "3") : 3;
      var eventLimit = eventLimitEl ? Number(eventLimitEl.value || "80") : 80;
      if (!isFinite(threshold) || threshold <= 0) {
        threshold = 3;
      }
      if (!isFinite(eventLimit) || eventLimit < 0) {
        eventLimit = 80;
      }
      return {
        since: sinceEl ? String(sinceEl.value || "60m").trim() : "60m",
        restartThreshold: Math.max(1, Math.min(50, Math.round(threshold))),
        eventLimit: Math.max(0, Math.min(500, Math.round(eventLimit)))
      };
    }

    function isAutoRefreshEnabled() {
      return !!(autoBtn && autoBtn.checked);
    }

    function toneClass(level) {
      var s = String(level || "").toLowerCase();
      if (s === "pass") {
        return "ap-live-state-running";
      }
      if (s === "fail") {
        return "ap-live-state-unhealthy";
      }
      return "ap-live-state-starting";
    }

    function renderSummary(summary) {
      var data = summary && typeof summary === "object" ? summary : {};
      summaryEl.innerHTML = ""
        + '<span class="ap-kv-group ap-live-state-info"><span class="ap-kv-group-key">Containers</span><span class="ap-kv-group-val">' + esc(String(data.containers || 0)) + "</span></span>"
        + '<span class="ap-kv-group ap-live-state-running"><span class="ap-kv-group-key">Pass</span><span class="ap-kv-group-val">' + esc(String(data.pass || 0)) + "</span></span>"
        + '<span class="ap-kv-group ap-live-state-starting"><span class="ap-kv-group-key">Warn</span><span class="ap-kv-group-val">' + esc(String(data.warn || 0)) + "</span></span>"
        + '<span class="ap-kv-group ap-live-state-unhealthy"><span class="ap-kv-group-key">Fail</span><span class="ap-kv-group-val">' + esc(String(data.fail || 0)) + "</span></span>"
        + '<span class="ap-kv-group ap-live-state-starting"><span class="ap-kv-group-key">Flapping</span><span class="ap-kv-group-val">' + esc(String(data.flapping || 0)) + "</span></span>"
        + '<span class="ap-kv-group ap-live-state-unhealthy"><span class="ap-kv-group-key">OOM</span><span class="ap-kv-group-val">' + esc(String(data.oom_killed || 0)) + "</span></span>"
        + '<span class="ap-kv-group ap-live-state-info"><span class="ap-kv-group-key">Events</span><span class="ap-kv-group-val">' + esc(String(data.events_total || 0)) + "</span></span>";
    }

    function renderRows(payload) {
      var items = Array.isArray(payload && payload.items) ? payload.items : [];
      if (items.length === 0) {
        rowsEl.innerHTML = '<tr><td colspan="8" class="text-center ap-page-sub py-4">No container runtime rows found.</td></tr>';
        return;
      }

      items.sort(function (a, b) {
        var av = String(a && a.name || "");
        var bv = String(b && b.name || "");
        return av.localeCompare(bv);
      });

      rowsEl.innerHTML = items.map(function (item) {
        var name = String(item && item.name || "-");
        var service = String(item && item.service || "-");
        var state = String(item && item.state || "-");
        var health = String(item && item.health || "-");
        var restarts = Number(item && item.restart_count || 0);
        var oom = !!(item && item.oom_killed);
        var exitCode = String(item && item.exit_code != null ? item.exit_code : "-");
        var level = String(item && item.level || "warn");
        var issues = String(item && item.issues || "none");
        return ""
          + "<tr>"
          + "  <td>" + esc(name) + "</td>"
          + "  <td>" + esc(service) + "</td>"
          + '  <td class="text-end">' + esc(state) + "</td>"
          + '  <td class="text-end">' + esc(health) + "</td>"
          + '  <td class="text-end">' + esc(String(isFinite(restarts) ? restarts : 0)) + "</td>"
          + '  <td class="text-end">' + (oom ? '<span class="ap-badge ap-live-state-unhealthy">Yes</span>' : '<span class="ap-badge ap-live-state-running">No</span>') + "</td>"
          + '  <td class="text-end">' + esc(exitCode) + "</td>"
          + '  <td><span class="ap-badge ' + esc(toneClass(level)) + '">' + esc(issues === "none" ? "ok" : issues) + "</span></td>"
          + "</tr>";
      }).join("");
    }

    function eventToneClass(action, exitCode) {
      var a = String(action || "").toLowerCase();
      if (a === "oom") {
        return "ap-live-state-unhealthy";
      }
      if (a === "die") {
        return String(exitCode || "") === "0" ? "ap-live-state-starting" : "ap-live-state-unhealthy";
      }
      if (a === "restart") {
        return "ap-live-state-starting";
      }
      return "ap-live-state-info";
    }

    function renderEvents(payload) {
      var events = Array.isArray(payload && payload.events) ? payload.events : [];
      if (events.length === 0) {
        eventsRowsEl.innerHTML = '<tr><td colspan="5" class="text-center ap-page-sub py-4">No runtime events in selected window.</td></tr>';
        return;
      }
      eventsRowsEl.innerHTML = events.map(function (event) {
        var time = String(event && event.time || "-");
        var action = String(event && event.action || "-");
        var name = String(event && event.name || "-");
        var service = String(event && event.service || "-");
        var exitCode = String(event && event.exit_code || "-");
        return ""
          + "<tr>"
          + "  <td>" + esc(time) + "</td>"
          + '  <td><span class="ap-badge ' + esc(eventToneClass(action, exitCode)) + '">' + esc(action) + "</span></td>"
          + "  <td>" + esc(name) + "</td>"
          + "  <td>" + esc(service) + "</td>"
          + '  <td class="text-end">' + esc(exitCode) + "</td>"
          + "</tr>";
      }).join("");
    }

    function renderTrend(payload) {
      var trend = Array.isArray(payload && payload.trend) ? payload.trend : [];
      if (trend.length === 0) {
        trendRowsEl.innerHTML = '<tr><td colspan="6" class="text-center ap-page-sub py-4">No event trend buckets in selected window.</td></tr>';
        return;
      }
      trendRowsEl.innerHTML = trend.map(function (row) {
        var bucket = String(row && row.bucket || "-");
        var total = Number(row && row.total || 0);
        var oom = Number(row && row.oom || 0);
        var die = Number(row && row.die || 0);
        var restart = Number(row && row.restart || 0);
        var start = Number(row && row.start || 0);
        return ""
          + "<tr>"
          + "  <td>" + esc(bucket) + "</td>"
          + '  <td class="text-end">' + esc(String(isFinite(total) ? total : 0)) + "</td>"
          + '  <td class="text-end">' + esc(String(isFinite(oom) ? oom : 0)) + "</td>"
          + '  <td class="text-end">' + esc(String(isFinite(die) ? die : 0)) + "</td>"
          + '  <td class="text-end">' + esc(String(isFinite(restart) ? restart : 0)) + "</td>"
          + '  <td class="text-end">' + esc(String(isFinite(start) ? start : 0)) + "</td>"
          + "</tr>";
      }).join("");
    }

    function buildUrl() {
      var filters = getFilters();
      var qp = new URLSearchParams();
      qp.set("since", filters.since);
      qp.set("restart_threshold", String(filters.restartThreshold));
      qp.set("event_limit", String(filters.eventLimit));
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
            throw new Error(payload && payload.message ? payload.message : ("runtime watch api failed (" + String(result.status || 500) + ")"));
          }
          renderSummary(payload.summary || {});
          renderRows(payload);
          renderEvents(payload);
          renderTrend(payload);
          lastGeneratedAt = String(payload.generated_at || "");
          activeProject = String(payload.project || "-");
          if (metaEl) {
            metaEl.textContent = "Project: " + activeProject + " | Containers: " + String((payload.summary && payload.summary.containers) || 0) + " | Events: " + String((payload.summary && payload.summary.events_total) || 0);
          }
        })
        .catch(function (err) {
          renderSummary({});
          renderRows({ items: [] });
          renderEvents({ events: [] });
          renderTrend({ trend: [] });
          showError(err && err.message ? err.message : "Unable to load runtime watch.");
        })
        .finally(function () {
          setLoading(false);
          if (isAutoRefreshEnabled()) {
            scheduleNextRefresh(8000);
          } else {
            clearNextRefresh();
            updateRefreshMeta();
          }
        });
    }

    function rebindAutoRefresh() {
      if (isAutoRefreshEnabled()) {
        scheduleNextRefresh(8000);
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
    if (thresholdEl) {
      thresholdEl.addEventListener("change", refreshSnapshot);
    }
    if (eventLimitEl) {
      eventLimitEl.addEventListener("change", refreshSnapshot);
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
