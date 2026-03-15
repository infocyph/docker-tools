<?php
declare(strict_types=1);
?>

<section class="ap-page-head">
  <div>
    <p class="ap-breadcrumb mb-1">Home / Monitoring / Volume Growth</p>
    <h2 class="ap-page-title mb-1">Volume Growth / Inode Monitor</h2>
    <p class="ap-page-sub mb-0">Per-volume size trend, growth rate, inode pressure, and exhaustion estimate.</p>
  </div>
  <div class="d-flex align-items-center gap-2 flex-wrap">
    <div id="apVolumeRefreshMeta" class="ap-live-refresh-meta" aria-live="polite">
      <div class="ap-live-meta-row">
        <span id="apVolumeUpdatedAt" class="ap-live-meta">Next refresh in --:--</span>
        <div class="ap-live-meta-controls">
          <label class="ap-live-auto-switch" for="apVolumeAuto">
            <span class="ap-live-auto-switch-label">Auto</span>
            <input id="apVolumeAuto" type="checkbox" role="switch" aria-label="Auto refresh volume monitor">
          </label>
          <button id="apVolumeRefreshBtn" class="btn ap-live-meta-refresh" type="button" aria-label="Refresh volume monitor" title="Refresh">
            <i class="bi bi-arrow-repeat"></i>
          </button>
        </div>
      </div>
      <span class="ap-live-countdown-track" aria-hidden="true">
        <span id="apVolumeCountdownBar" class="ap-live-countdown-bar"></span>
      </span>
      <small id="apVolumeLastUpdated" class="ap-live-meta-sub">Waiting for first snapshot...</small>
    </div>
  </div>
</section>

<div id="apVolumeError" class="ap-live-error d-none mb-2" role="status" aria-live="polite"></div>

<section class="row g-3 mt-1">
  <div class="col-12">
    <article class="card ap-card h-100">
      <header class="card-header ap-card-head ap-card-head-wrap">
        <div>
          <h4 class="ap-card-title mb-1">Filters</h4>
          <p id="apVolumeMeta" class="ap-card-sub mb-0">Largest volumes with growth and inode indicators.</p>
        </div>
        <div class="ap-head-tools">
          <div class="ap-live-matrix-tools">
            <select id="apVolumeTop" class="form-select form-select-sm ap-live-tool-select" aria-label="Top volumes">
              <option value="10">Top: 10</option>
              <option value="20" selected>Top: 20</option>
              <option value="30">Top: 30</option>
              <option value="50">Top: 50</option>
            </select>
            <select id="apVolumeInodeTop" class="form-select form-select-sm ap-live-tool-select" aria-label="Inode scan top">
              <option value="0">Inodes: Off</option>
              <option value="5">Inodes: top 5</option>
              <option value="8" selected>Inodes: top 8</option>
              <option value="12">Inodes: top 12</option>
            </select>
          </div>
        </div>
      </header>
      <div class="card-body">
        <div id="apVolumeSummary" class="ap-monitor-summary mb-3"></div>
        <div class="table-responsive ap-local-sticky">
          <table class="table ap-table ap-table-sticky ap-table-emphasis mb-0">
            <thead>
            <tr>
              <th>Volume</th>
              <th>Services</th>
              <th class="text-end">Size</th>
              <th class="text-end">Delta</th>
              <th class="text-end">Growth /h</th>
              <th class="text-end">ETA (h)</th>
              <th class="text-end">Pressure %</th>
              <th class="text-end">Inode %</th>
              <th class="text-end">Files</th>
              <th>State</th>
            </tr>
            </thead>
            <tbody id="apVolumeRows">
            <tr><td colspan="10" class="text-center ap-page-sub py-4">Loading...</td></tr>
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

    var rowsEl = document.getElementById("apVolumeRows");
    if (!rowsEl) {
      return;
    }

    var basePath = (document.body && document.body.getAttribute("data-ap-base")) || "";
    if (basePath === "/") {
      basePath = "";
    }
    var apiUrl = basePath + "/api/volume-monitor";

    var topEl = document.getElementById("apVolumeTop");
    var inodeTopEl = document.getElementById("apVolumeInodeTop");
    var autoBtn = document.getElementById("apVolumeAuto");
    var refreshBtn = document.getElementById("apVolumeRefreshBtn");
    var metaEl = document.getElementById("apVolumeMeta");
    var summaryEl = document.getElementById("apVolumeSummary");
    var errEl = document.getElementById("apVolumeError");
    var refreshMetaEl = document.getElementById("apVolumeRefreshMeta");
    var updatedAtEl = document.getElementById("apVolumeUpdatedAt");
    var lastUpdatedEl = document.getElementById("apVolumeLastUpdated");
    var countdownBarEl = document.getElementById("apVolumeCountdownBar");

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
          updatedAtEl.textContent = "Refreshing volume monitor...";
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
      var top = topEl ? Number(topEl.value || "20") : 20;
      var inodeTop = inodeTopEl ? Number(inodeTopEl.value || "8") : 8;
      if (!isFinite(top) || top <= 0) {
        top = 20;
      }
      if (!isFinite(inodeTop) || inodeTop < 0) {
        inodeTop = 8;
      }
      return {
        top: Math.max(1, Math.min(200, Math.round(top))),
        inodeTop: Math.max(0, Math.min(30, Math.round(inodeTop)))
      };
    }

    function isAutoRefreshEnabled() {
      return !!(autoBtn && autoBtn.checked);
    }

    function renderSummary(summary) {
      var data = summary && typeof summary === "object" ? summary : {};
      summaryEl.innerHTML = ""
        + '<span class="ap-kv-group ap-live-state-info"><span class="ap-kv-group-key">Volumes</span><span class="ap-kv-group-val">' + esc(String(data.volumes || 0)) + "</span></span>"
        + '<span class="ap-kv-group ap-live-state-running"><span class="ap-kv-group-key">Pass</span><span class="ap-kv-group-val">' + esc(String(data.pass || 0)) + "</span></span>"
        + '<span class="ap-kv-group ap-live-state-starting"><span class="ap-kv-group-key">Warn</span><span class="ap-kv-group-val">' + esc(String(data.warn || 0)) + "</span></span>"
        + '<span class="ap-kv-group ap-live-state-unhealthy"><span class="ap-kv-group-key">Fail</span><span class="ap-kv-group-val">' + esc(String(data.fail || 0)) + "</span></span>"
        + '<span class="ap-kv-group ap-live-state-info"><span class="ap-kv-group-key">Inode Scanned</span><span class="ap-kv-group-val">' + esc(String(data.inode_scanned || 0)) + "</span></span>"
        + '<span class="ap-kv-group ap-live-state-info"><span class="ap-kv-group-key">Docker Free</span><span class="ap-kv-group-val">' + numberText(data.docker_root_free_bytes) + "</span></span>";
    }

    function renderRows(payload) {
      var items = Array.isArray(payload && payload.items) ? payload.items : [];
      if (items.length === 0) {
        rowsEl.innerHTML = '<tr><td colspan="10" class="text-center ap-page-sub py-4">No volume rows found.</td></tr>';
        return;
      }

      rowsEl.innerHTML = items.map(function (item) {
        return ""
          + "<tr>"
          + "  <td>" + esc(String(item && item.volume || "-")) + "</td>"
          + "  <td>" + esc(String(item && item.services || "-")) + "</td>"
          + '  <td class="text-end">' + esc(String(item && item.size || "-")) + "</td>"
          + '  <td class="text-end">' + esc(String(item && item.delta_human || "-")) + "</td>"
          + '  <td class="text-end">' + esc(String(item && item.growth_human_per_hour || "-")) + "</td>"
          + '  <td class="text-end">' + numberText(item && item.eta_hours) + "</td>"
          + '  <td class="text-end">' + numberText(item && item.pressure_pct) + "</td>"
          + '  <td class="text-end">' + numberText(item && item.inode_pct) + "</td>"
          + '  <td class="text-end">' + numberText(item && item.file_count) + "</td>"
          + '  <td><span class="ap-badge ' + esc(toneClass(item && item.level || "warn")) + '">' + esc(String(item && item.note || "-")) + "</span></td>"
          + "</tr>";
      }).join("");
    }

    function buildUrl() {
      var filters = getFilters();
      var qp = new URLSearchParams();
      qp.set("top", String(filters.top));
      qp.set("inode_top", String(filters.inodeTop));
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
            throw new Error(payload && payload.message ? payload.message : ("volume monitor api failed (" + String(result.status || 500) + ")"));
          }
          renderSummary(payload.summary || {});
          renderRows(payload);
          lastGeneratedAt = String(payload.generated_at || "");
          activeProject = String(payload.project || "-");
          if (metaEl) {
            metaEl.textContent = "Project: " + activeProject + " | Volumes: " + String((payload.summary && payload.summary.volumes) || 0);
          }
        })
        .catch(function (err) {
          renderSummary({});
          renderRows({ items: [] });
          showError(err && err.message ? err.message : "Unable to load volume monitor.");
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
    if (topEl) {
      topEl.addEventListener("change", refreshSnapshot);
    }
    if (inodeTopEl) {
      inodeTopEl.addEventListener("change", refreshSnapshot);
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
