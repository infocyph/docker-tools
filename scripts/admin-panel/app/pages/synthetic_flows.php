<?php
declare(strict_types=1);
?>

<section class="ap-page-head">
  <div>
    <p class="ap-breadcrumb mb-1">Home / Monitoring / Synthetic Flows</p>
    <h2 class="ap-page-title mb-1">Synthetic Flows</h2>
    <p class="ap-page-sub mb-0">Route-level probes across mapped LDS domains.</p>
  </div>
  <div class="d-flex align-items-center gap-2 flex-wrap">
    <div id="apFlowsRefreshMeta" class="ap-live-refresh-meta" aria-live="polite">
      <span id="apFlowsUpdatedAt" class="ap-live-meta">Next refresh in --:--</span>
      <span class="ap-live-countdown-track" aria-hidden="true">
        <span id="apFlowsCountdownBar" class="ap-live-countdown-bar"></span>
      </span>
      <small id="apFlowsLastUpdated" class="ap-live-meta-sub">Waiting for first snapshot...</small>
    </div>
  </div>
</section>

<div id="apFlowsError" class="ap-live-error d-none mb-2" role="status" aria-live="polite"></div>

<section class="row g-3 mt-1">
  <div class="col-12">
    <article class="card ap-card h-100">
      <header class="card-header ap-card-head ap-card-head-wrap">
        <div>
          <h4 class="ap-card-title mb-1">Filters</h4>
          <p id="apFlowsMeta" class="ap-card-sub mb-0">Configure domain/path checks.</p>
        </div>
        <div class="ap-head-tools">
          <div class="ap-live-matrix-tools">
            <input id="apFlowsDomain" class="form-control form-control-sm ap-live-tool-input" type="search" placeholder="Domain filter (optional)">
            <input id="apFlowsPaths" class="form-control form-control-sm ap-live-tool-input" type="text" value="/,/login,/api/health,?/api/ping,?/health/db" placeholder="Paths CSV (?path = optional)">
            <select id="apFlowsTimeout" class="form-select form-select-sm ap-live-tool-select" aria-label="Timeout">
              <option value="2">Timeout: 2s</option>
              <option value="4" selected>Timeout: 4s</option>
              <option value="6">Timeout: 6s</option>
              <option value="10">Timeout: 10s</option>
            </select>
            <button id="apFlowsAuto" class="btn ap-chip-btn" type="button" aria-pressed="false">Auto</button>
            <button id="apFlowsRefreshBtn" class="btn ap-ghost-btn" type="button"><i class="bi bi-arrow-repeat me-1"></i> Refresh</button>
          </div>
        </div>
      </header>
      <div class="card-body">
        <div id="apFlowsSummary" class="ap-monitor-summary mb-3"></div>
        <div class="table-responsive ap-local-sticky">
          <table class="table ap-table ap-table-sticky ap-table-emphasis mb-0">
            <thead>
            <tr>
              <th>Domain</th>
              <th>Flow</th>
              <th>Path</th>
              <th class="text-end">State</th>
              <th class="text-end">HTTP</th>
              <th class="text-end">Time</th>
              <th>Note</th>
            </tr>
            </thead>
            <tbody id="apFlowsRows">
            <tr><td colspan="7" class="text-center ap-page-sub py-4">Loading...</td></tr>
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

    var rowsEl = document.getElementById("apFlowsRows");
    if (!rowsEl) {
      return;
    }

    var basePath = (document.body && document.body.getAttribute("data-ap-base")) || "";
    if (basePath === "/") {
      basePath = "";
    }
    var apiUrl = basePath + "/api/synthetic-flows";

    var domainEl = document.getElementById("apFlowsDomain");
    var pathsEl = document.getElementById("apFlowsPaths");
    var timeoutEl = document.getElementById("apFlowsTimeout");
    var autoBtn = document.getElementById("apFlowsAuto");
    var refreshBtn = document.getElementById("apFlowsRefreshBtn");
    var metaEl = document.getElementById("apFlowsMeta");
    var summaryEl = document.getElementById("apFlowsSummary");
    var errEl = document.getElementById("apFlowsError");
    var refreshMetaEl = document.getElementById("apFlowsRefreshMeta");
    var updatedAtEl = document.getElementById("apFlowsUpdatedAt");
    var lastUpdatedEl = document.getElementById("apFlowsLastUpdated");
    var countdownBarEl = document.getElementById("apFlowsCountdownBar");

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
          icon.className = loading ? "bi bi-arrow-repeat ap-spin me-1" : "bi bi-arrow-repeat me-1";
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
          updatedAtEl.textContent = "Refreshing synthetic flows...";
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
      var timeout = 4;
      if (timeoutEl) {
        timeout = Number(timeoutEl.value || "4");
      }
      if (!isFinite(timeout) || timeout <= 0) {
        timeout = 4;
      }
      return {
        domain: domainEl ? String(domainEl.value || "").trim().toLowerCase() : "",
        paths: pathsEl ? String(pathsEl.value || "").trim() : "",
        timeout: Math.max(1, Math.min(20, Math.round(timeout)))
      };
    }

    function isAutoRefreshEnabled() {
      return !!(autoBtn && autoBtn.classList.contains("is-active"));
    }

    function stateBadgeClass(state) {
      var s = String(state || "").toLowerCase();
      if (s === "pass") {
        return "ap-live-state-running";
      }
      if (s === "fail") {
        return "ap-live-state-unhealthy";
      }
      if (s === "skip") {
        return "ap-live-state-no-health";
      }
      return "ap-live-state-starting";
    }

    function renderSummary(summary) {
      var data = summary && typeof summary === "object" ? summary : {};
      summaryEl.innerHTML = ""
        + '<span class="ap-kv-group ap-live-state-info"><span class="ap-kv-group-key">Domains</span><span class="ap-kv-group-val">' + esc(String(data.domains || 0)) + "</span></span>"
        + '<span class="ap-kv-group ap-live-state-info"><span class="ap-kv-group-key">Checks</span><span class="ap-kv-group-val">' + esc(String(data.checks || 0)) + "</span></span>"
        + '<span class="ap-kv-group ap-live-state-running"><span class="ap-kv-group-key">Pass</span><span class="ap-kv-group-val">' + esc(String(data.pass || 0)) + "</span></span>"
        + '<span class="ap-kv-group ap-live-state-starting"><span class="ap-kv-group-key">Warn</span><span class="ap-kv-group-val">' + esc(String(data.warn || 0)) + "</span></span>"
        + '<span class="ap-kv-group ap-live-state-unhealthy"><span class="ap-kv-group-key">Fail</span><span class="ap-kv-group-val">' + esc(String(data.fail || 0)) + "</span></span>"
        + '<span class="ap-kv-group ap-live-state-no-health"><span class="ap-kv-group-key">Skip</span><span class="ap-kv-group-val">' + esc(String(data.skip || 0)) + "</span></span>"
        + '<span class="ap-kv-group ap-live-state-info"><span class="ap-kv-group-key">Avg</span><span class="ap-kv-group-val">' + esc(String(data.avg_ms || 0)) + "ms</span></span>"
        + '<span class="ap-kv-group ap-live-state-info"><span class="ap-kv-group-key">P95</span><span class="ap-kv-group-val">' + esc(String(data.p95_ms || 0)) + "ms</span></span>";
    }

    function renderRows(payload) {
      var items = Array.isArray(payload && payload.items) ? payload.items : [];
      if (items.length === 0) {
        rowsEl.innerHTML = '<tr><td colspan="7" class="text-center ap-page-sub py-4">No synthetic flow results for current filters.</td></tr>';
        return;
      }

      items.sort(function (a, b) {
        var ad = String(a && a.domain || "");
        var bd = String(b && b.domain || "");
        if (ad !== bd) {
          return ad.localeCompare(bd);
        }
        var ap = String(a && a.path || "");
        var bp = String(b && b.path || "");
        return ap.localeCompare(bp);
      });

      rowsEl.innerHTML = items.map(function (item) {
        var domain = String(item && item.domain || "-");
        var flow = String(item && item.flow || "-");
        var path = String(item && item.path || "-");
        var required = !!(item && item.required);
        var state = String(item && item.state || "warn");
        var code = String(item && item.code || "-");
        var timeMs = Number(item && item.time_ms || 0);
        var note = String(item && item.note || "-");
        var stateText = state.charAt(0).toUpperCase() + state.slice(1).toLowerCase();
        var flowText = required ? (flow + " (required)") : flow;
        return ""
          + "<tr>"
          + "  <td>" + esc(domain) + "</td>"
          + "  <td>" + esc(flowText) + "</td>"
          + "  <td><code>" + esc(path) + "</code></td>"
          + '  <td class="text-end"><span class="ap-badge ' + esc(stateBadgeClass(state)) + '">' + esc(stateText) + "</span></td>"
          + '  <td class="text-end">' + esc(code) + "</td>"
          + '  <td class="text-end">' + esc(String(isFinite(timeMs) ? timeMs : 0)) + " ms</td>"
          + "  <td>" + esc(note) + "</td>"
          + "</tr>";
      }).join("");
    }

    function buildUrl() {
      var filters = getFilters();
      var qp = new URLSearchParams();
      qp.set("timeout", String(filters.timeout));
      if (filters.domain !== "") {
        qp.set("domain", filters.domain);
      }
      if (filters.paths !== "") {
        qp.set("paths", filters.paths);
      }
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
            throw new Error(payload && payload.message ? payload.message : ("synthetic flows api failed (" + String(result.status || 500) + ")"));
          }
          renderSummary(payload.summary || {});
          renderRows(payload);
          lastGeneratedAt = String(payload.generated_at || "");
          activeProject = String(payload.project || "-");
          if (metaEl) {
            metaEl.textContent = "Project: " + activeProject + " | Domains: " + String((payload.summary && payload.summary.domains) || 0) + " | Checks: " + String((payload.summary && payload.summary.checks) || 0);
          }
        })
        .catch(function (err) {
          renderSummary({});
          renderRows({ items: [] });
          showError(err && err.message ? err.message : "Unable to load synthetic flows.");
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
    if (domainEl) {
      domainEl.addEventListener("keydown", function (e) {
        if (e.key === "Enter") {
          e.preventDefault();
          refreshSnapshot();
        }
      });
    }
    if (pathsEl) {
      pathsEl.addEventListener("keydown", function (e) {
        if (e.key === "Enter") {
          e.preventDefault();
          refreshSnapshot();
        }
      });
    }
    if (timeoutEl) {
      timeoutEl.addEventListener("change", refreshSnapshot);
    }
    if (autoBtn) {
      autoBtn.addEventListener("click", function () {
        var enabled = !autoBtn.classList.contains("is-active");
        autoBtn.classList.toggle("is-active", enabled);
        autoBtn.setAttribute("aria-pressed", enabled ? "true" : "false");
        rebindAutoRefresh();
        if (enabled) {
          refreshSnapshot();
        } else {
          updateRefreshMeta();
        }
      });
    }

    ensureCountdownTicker();
    rebindAutoRefresh();
    refreshSnapshot();
  })();
</script>
