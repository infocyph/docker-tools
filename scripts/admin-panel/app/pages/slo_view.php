<?php
declare(strict_types=1);
?>

<section class="ap-page-head">
  <div>
    <p class="ap-breadcrumb mb-1">Home / Monitoring / Error Budget / SLO</p>
    <h2 class="ap-page-title mb-1">Error Budget / SLO View</h2>
    <p class="ap-page-sub mb-0">Uptime, p95 latency, and error rate by domain/service for 1h/24h/7d.</p>
  </div>
  <div class="d-flex align-items-center gap-2 flex-wrap">
    <div id="apSloRefreshMeta" class="ap-live-refresh-meta" aria-live="polite">
      <span id="apSloUpdatedAt" class="ap-live-meta">Next refresh in --:--</span>
      <span class="ap-live-countdown-track" aria-hidden="true">
        <span id="apSloCountdownBar" class="ap-live-countdown-bar"></span>
      </span>
      <small id="apSloLastUpdated" class="ap-live-meta-sub">Waiting for first snapshot...</small>
    </div>
  </div>
</section>

<div id="apSloError" class="ap-live-error d-none mb-2" role="status" aria-live="polite"></div>

<section class="row g-3 mt-1">
  <div class="col-12">
    <article class="card ap-card h-100">
      <header class="card-header ap-card-head ap-card-head-wrap">
        <div>
          <h4 class="ap-card-title mb-1">Filters</h4>
          <p id="apSloMeta" class="ap-card-sub mb-0">Probe-backed SLO aggregation across rolling windows.</p>
        </div>
        <div class="ap-head-tools">
          <div class="ap-live-matrix-tools">
            <select id="apSloTimeout" class="form-select form-select-sm ap-live-tool-select" aria-label="Probe timeout">
              <option value="2">Timeout: 2s</option>
              <option value="4" selected>Timeout: 4s</option>
              <option value="6">Timeout: 6s</option>
              <option value="10">Timeout: 10s</option>
            </select>
            <input id="apSloPaths" class="form-control form-control-sm ap-live-tool-input" type="text" placeholder="Paths CSV (optional)">
            <button id="apSloAuto" class="btn ap-chip-btn" type="button" aria-pressed="false">Auto</button>
            <button id="apSloRefreshBtn" class="btn ap-ghost-btn" type="button"><i class="bi bi-arrow-repeat me-1"></i> Refresh</button>
          </div>
        </div>
      </header>
      <div class="card-body">
        <div id="apSloSummary" class="ap-monitor-summary mb-3"></div>
        <div class="table-responsive ap-local-sticky mb-3">
          <table class="table ap-table ap-table-sticky ap-table-emphasis mb-0">
            <thead>
            <tr>
              <th>Window</th>
              <th class="text-end">Checks</th>
              <th class="text-end">OK</th>
              <th class="text-end">Error</th>
              <th class="text-end">Uptime %</th>
              <th class="text-end">Error Rate %</th>
            </tr>
            </thead>
            <tbody id="apSloSummaryRows">
            <tr><td colspan="6" class="text-center ap-page-sub py-4">Loading...</td></tr>
            </tbody>
          </table>
        </div>
        <div class="table-responsive ap-local-sticky">
          <table class="table ap-table ap-table-sticky ap-table-emphasis mb-0">
            <thead>
            <tr>
              <th>Window</th>
              <th>Domain</th>
              <th>Service</th>
              <th class="text-end">Checks</th>
              <th class="text-end">Uptime %</th>
              <th class="text-end">Error Rate %</th>
              <th class="text-end">P95 (ms)</th>
              <th class="text-end">AVG (ms)</th>
            </tr>
            </thead>
            <tbody id="apSloRows">
            <tr><td colspan="8" class="text-center ap-page-sub py-4">Loading...</td></tr>
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

    var summaryRowsEl = document.getElementById("apSloSummaryRows");
    var rowsEl = document.getElementById("apSloRows");
    if (!summaryRowsEl || !rowsEl) {
      return;
    }

    var basePath = (document.body && document.body.getAttribute("data-ap-base")) || "";
    if (basePath === "/") {
      basePath = "";
    }
    var apiUrl = basePath + "/api/slo-view";

    var timeoutEl = document.getElementById("apSloTimeout");
    var pathsEl = document.getElementById("apSloPaths");
    var autoBtn = document.getElementById("apSloAuto");
    var refreshBtn = document.getElementById("apSloRefreshBtn");
    var metaEl = document.getElementById("apSloMeta");
    var summaryEl = document.getElementById("apSloSummary");
    var errEl = document.getElementById("apSloError");
    var refreshMetaEl = document.getElementById("apSloRefreshMeta");
    var updatedAtEl = document.getElementById("apSloUpdatedAt");
    var lastUpdatedEl = document.getElementById("apSloLastUpdated");
    var countdownBarEl = document.getElementById("apSloCountdownBar");

    var refreshTimer = null;
    var refreshCountdownTimer = null;
    var refreshIntervalMs = 12000;
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

    function pctFromX100(value) {
      var n = Number(value);
      if (!isFinite(n)) {
        return "-";
      }
      return (n / 100).toFixed(2);
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
      refreshIntervalMs = wait > 0 ? wait : 12000;
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
          updatedAtEl.textContent = "Refreshing SLO view...";
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
        timeout: timeoutEl ? Math.max(1, Math.min(20, Number(timeoutEl.value || "4"))) : 4,
        paths: pathsEl ? String(pathsEl.value || "").trim() : ""
      };
    }

    function isAutoRefreshEnabled() {
      return !!(autoBtn && autoBtn.classList.contains("is-active"));
    }

    function renderSummary(windowRows) {
      var windows = Array.isArray(windowRows) ? windowRows : [];
      summaryEl.innerHTML = windows.map(function (row) {
        return '<span class="ap-kv-group ap-live-state-info"><span class="ap-kv-group-key">' + esc(String(row.window || "-")) + '</span><span class="ap-kv-group-val">' + esc(pctFromX100(row.uptime_pct_x100)) + '%</span></span>';
      }).join("");
      if (windows.length === 0) {
        summaryEl.innerHTML = '<span class="ap-kv-group ap-live-state-starting"><span class="ap-kv-group-key">No Data</span><span class="ap-kv-group-val">-</span></span>';
      }
      summaryRowsEl.innerHTML = windows.length === 0
        ? '<tr><td colspan="6" class="text-center ap-page-sub py-4">No window summary available yet.</td></tr>'
        : windows.map(function (row) {
          return ''
            + '<tr>'
            + '  <td>' + esc(String(row.window || "-")) + '</td>'
            + '  <td class="text-end">' + numberText(row.checks) + '</td>'
            + '  <td class="text-end">' + numberText(row.ok) + '</td>'
            + '  <td class="text-end">' + numberText(row.error) + '</td>'
            + '  <td class="text-end">' + esc(pctFromX100(row.uptime_pct_x100)) + '</td>'
            + '  <td class="text-end">' + esc(pctFromX100(row.error_rate_pct_x100)) + '</td>'
            + '</tr>';
        }).join("");
    }

    function renderRows(items) {
      var rows = Array.isArray(items) ? items : [];
      if (rows.length === 0) {
        rowsEl.innerHTML = '<tr><td colspan="8" class="text-center ap-page-sub py-4">No SLO rows found.</td></tr>';
        return;
      }
      rows.sort(function (a, b) {
        var ak = String(a && a.window || "") + "|" + String(a && a.domain || "");
        var bk = String(b && b.window || "") + "|" + String(b && b.domain || "");
        return ak.localeCompare(bk);
      });
      rowsEl.innerHTML = rows.map(function (row) {
        return ''
          + '<tr>'
          + '  <td>' + esc(String(row.window || "-")) + '</td>'
          + '  <td>' + esc(String(row.domain || "-")) + '</td>'
          + '  <td>' + esc(String(row.service || "-")) + '</td>'
          + '  <td class="text-end">' + numberText(row.checks) + '</td>'
          + '  <td class="text-end">' + esc(pctFromX100(row.uptime_pct_x100)) + '</td>'
          + '  <td class="text-end">' + esc(pctFromX100(row.error_rate_pct_x100)) + '</td>'
          + '  <td class="text-end">' + numberText(row.p95_ms) + '</td>'
          + '  <td class="text-end">' + numberText(row.avg_ms) + '</td>'
          + '</tr>';
      }).join("");
    }

    function buildUrl() {
      var f = getFilters();
      var qp = new URLSearchParams();
      qp.set("timeout", String(Math.round(f.timeout)));
      if (f.paths !== "") {
        qp.set("paths", f.paths);
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
            throw new Error(payload && payload.message ? payload.message : ("slo view api failed (" + String(result.status || 500) + ")"));
          }
          var windows = payload.summary && Array.isArray(payload.summary.windows) ? payload.summary.windows : [];
          renderSummary(windows);
          renderRows(payload.items || []);
          lastGeneratedAt = String(payload.generated_at || "");
          activeProject = String(payload.project || "-");
          if (metaEl) {
            metaEl.textContent = "Project: " + activeProject + " | Domains: " + String((payload.items || []).length);
          }
        })
        .catch(function (err) {
          renderSummary([]);
          renderRows([]);
          showError(err && err.message ? err.message : "Unable to load SLO view.");
        })
        .finally(function () {
          setLoading(false);
          if (isAutoRefreshEnabled()) {
            scheduleNextRefresh(12000);
          } else {
            clearNextRefresh();
            updateRefreshMeta();
          }
        });
    }

    function rebindAutoRefresh() {
      if (isAutoRefreshEnabled()) {
        scheduleNextRefresh(12000);
      } else {
        clearNextRefresh();
        updateRefreshMeta();
      }
    }

    if (refreshBtn) {
      refreshBtn.addEventListener("click", refreshSnapshot);
    }
    if (timeoutEl) {
      timeoutEl.addEventListener("change", refreshSnapshot);
    }
    if (pathsEl) {
      pathsEl.addEventListener("keydown", function (e) {
        if (e.key === "Enter") {
          e.preventDefault();
          refreshSnapshot();
        }
      });
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
