<?php
declare(strict_types=1);
?>

<section class="ap-page-head">
  <div>
    <p class="ap-breadcrumb mb-1">Home / Monitoring / DB / Redis Health</p>
    <h2 class="ap-page-title mb-1">DB / Redis Health</h2>
    <p class="ap-page-sub mb-0">Connection pressure, slow queries, evictions, and replication basics.</p>
  </div>
  <div class="d-flex align-items-center gap-2 flex-wrap">
    <div id="apDbHealthRefreshMeta" class="ap-live-refresh-meta" aria-live="polite">
      <span id="apDbHealthUpdatedAt" class="ap-live-meta">Next refresh in --:--</span>
      <span class="ap-live-countdown-track" aria-hidden="true">
        <span id="apDbHealthCountdownBar" class="ap-live-countdown-bar"></span>
      </span>
      <small id="apDbHealthLastUpdated" class="ap-live-meta-sub">Waiting for first snapshot...</small>
    </div>
  </div>
</section>

<div id="apDbHealthError" class="ap-live-error d-none mb-2" role="status" aria-live="polite"></div>

<section class="row g-3 mt-1">
  <div class="col-12">
    <article class="card ap-card h-100">
      <header class="card-header ap-card-head ap-card-head-wrap">
        <div>
          <h4 class="ap-card-title mb-1">Filters</h4>
          <p id="apDbHealthMeta" class="ap-card-sub mb-0">Inspect database and redis runtime health.</p>
        </div>
        <div class="ap-head-tools">
          <div class="ap-live-matrix-tools">
            <select id="apDbHealthEngine" class="form-select form-select-sm ap-live-tool-select" aria-label="Engine filter">
              <option value="all" selected>Engine: All</option>
              <option value="mysql">Engine: MySQL / MariaDB</option>
              <option value="postgres">Engine: PostgreSQL</option>
              <option value="redis">Engine: Redis</option>
            </select>
            <button id="apDbHealthAuto" class="btn ap-chip-btn" type="button" aria-pressed="false">Auto</button>
            <button id="apDbHealthRefreshBtn" class="btn ap-ghost-btn" type="button"><i class="bi bi-arrow-repeat me-1"></i> Refresh</button>
          </div>
        </div>
      </header>
      <div class="card-body">
        <div id="apDbHealthSummary" class="ap-monitor-summary mb-3"></div>
        <div class="table-responsive ap-local-sticky">
          <table class="table ap-table ap-table-sticky ap-table-emphasis mb-0">
            <thead>
            <tr>
              <th>Container</th>
              <th>Service</th>
              <th class="text-end">Engine</th>
              <th class="text-end">State</th>
              <th class="text-end">Health</th>
              <th class="text-end">Connections</th>
              <th class="text-end">Active</th>
              <th class="text-end">Max Conn</th>
              <th class="text-end">Slow</th>
              <th class="text-end">Evicted</th>
              <th class="text-end">Pressure %</th>
              <th class="text-end">Repl Lag (s)</th>
              <th>Note</th>
            </tr>
            </thead>
            <tbody id="apDbHealthRows">
            <tr><td colspan="13" class="text-center ap-page-sub py-4">Loading...</td></tr>
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

    var rowsEl = document.getElementById("apDbHealthRows");
    if (!rowsEl) {
      return;
    }

    var basePath = (document.body && document.body.getAttribute("data-ap-base")) || "";
    if (basePath === "/") {
      basePath = "";
    }
    var apiUrl = basePath + "/api/db-health";

    var engineEl = document.getElementById("apDbHealthEngine");
    var autoBtn = document.getElementById("apDbHealthAuto");
    var refreshBtn = document.getElementById("apDbHealthRefreshBtn");
    var metaEl = document.getElementById("apDbHealthMeta");
    var summaryEl = document.getElementById("apDbHealthSummary");
    var errEl = document.getElementById("apDbHealthError");
    var refreshMetaEl = document.getElementById("apDbHealthRefreshMeta");
    var updatedAtEl = document.getElementById("apDbHealthUpdatedAt");
    var lastUpdatedEl = document.getElementById("apDbHealthLastUpdated");
    var countdownBarEl = document.getElementById("apDbHealthCountdownBar");

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
          updatedAtEl.textContent = "Refreshing DB/Redis health...";
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
        engine: engineEl ? String(engineEl.value || "all").trim().toLowerCase() : "all"
      };
    }

    function isAutoRefreshEnabled() {
      return !!(autoBtn && autoBtn.classList.contains("is-active"));
    }

    function renderSummary(summary) {
      var data = summary && typeof summary === "object" ? summary : {};
      summaryEl.innerHTML = ""
        + '<span class="ap-kv-group ap-live-state-info"><span class="ap-kv-group-key">Targets</span><span class="ap-kv-group-val">' + esc(String(data.targets || 0)) + "</span></span>"
        + '<span class="ap-kv-group ap-live-state-running"><span class="ap-kv-group-key">Pass</span><span class="ap-kv-group-val">' + esc(String(data.pass || 0)) + "</span></span>"
        + '<span class="ap-kv-group ap-live-state-starting"><span class="ap-kv-group-key">Warn</span><span class="ap-kv-group-val">' + esc(String(data.warn || 0)) + "</span></span>"
        + '<span class="ap-kv-group ap-live-state-unhealthy"><span class="ap-kv-group-key">Fail</span><span class="ap-kv-group-val">' + esc(String(data.fail || 0)) + "</span></span>"
        + '<span class="ap-kv-group ap-live-state-info"><span class="ap-kv-group-key">Redis</span><span class="ap-kv-group-val">' + esc(String(data.redis || 0)) + "</span></span>"
        + '<span class="ap-kv-group ap-live-state-info"><span class="ap-kv-group-key">MySQL</span><span class="ap-kv-group-val">' + esc(String(data.mysql || 0)) + "</span></span>"
        + '<span class="ap-kv-group ap-live-state-info"><span class="ap-kv-group-key">Postgres</span><span class="ap-kv-group-val">' + esc(String(data.postgres || 0)) + "</span></span>";
    }

    function renderRows(payload) {
      var items = Array.isArray(payload && payload.items) ? payload.items : [];
      if (items.length === 0) {
        rowsEl.innerHTML = '<tr><td colspan="13" class="text-center ap-page-sub py-4">No DB/Redis targets found.</td></tr>';
        return;
      }

      items.sort(function (a, b) {
        return String(a && a.container || "").localeCompare(String(b && b.container || ""));
      });

      rowsEl.innerHTML = items.map(function (item) {
        var metrics = item && typeof item.metrics === "object" ? item.metrics : {};
        return ""
          + "<tr>"
          + "  <td>" + esc(String(item && item.container || "-")) + "</td>"
          + "  <td>" + esc(String(item && item.service || "-")) + "</td>"
          + '  <td class="text-end">' + esc(String(item && item.engine || "-")) + "</td>"
          + '  <td class="text-end">' + esc(String(item && item.state || "-")) + "</td>"
          + '  <td class="text-end">' + esc(String(item && item.health || "-")) + "</td>"
          + '  <td class="text-end">' + numberText(metrics.connections) + "</td>"
          + '  <td class="text-end">' + numberText(metrics.active) + "</td>"
          + '  <td class="text-end">' + numberText(metrics.max_connections) + "</td>"
          + '  <td class="text-end">' + numberText(metrics.slow_queries) + "</td>"
          + '  <td class="text-end">' + numberText(metrics.evicted_keys) + "</td>"
          + '  <td class="text-end">' + numberText(metrics.pressure_pct) + "</td>"
          + '  <td class="text-end">' + numberText(metrics.replication_lag_s) + "</td>"
          + '  <td><span class="ap-badge ' + esc(toneClass(item && item.level || "warn")) + '">' + esc(String(item && item.note || "-")) + "</span></td>"
          + "</tr>";
      }).join("");
    }

    function buildUrl() {
      var filters = getFilters();
      var qp = new URLSearchParams();
      if (filters.engine !== "" && filters.engine !== "all") {
        qp.set("engine", filters.engine);
      }
      return apiUrl + (qp.toString() ? ("?" + qp.toString()) : "");
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
            throw new Error(payload && payload.message ? payload.message : ("db health api failed (" + String(result.status || 500) + ")"));
          }
          renderSummary(payload.summary || {});
          renderRows(payload);
          lastGeneratedAt = String(payload.generated_at || "");
          activeProject = String(payload.project || "-");
          if (metaEl) {
            metaEl.textContent = "Project: " + activeProject + " | Targets: " + String((payload.summary && payload.summary.targets) || 0);
          }
        })
        .catch(function (err) {
          renderSummary({});
          renderRows({ items: [] });
          showError(err && err.message ? err.message : "Unable to load DB/Redis health.");
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
    if (engineEl) {
      engineEl.addEventListener("change", refreshSnapshot);
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
