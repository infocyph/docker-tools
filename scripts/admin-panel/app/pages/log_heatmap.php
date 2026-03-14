<?php
declare(strict_types=1);
?>

<section class="ap-page-head">
  <div>
    <p class="ap-breadcrumb mb-1">Home / Monitoring / Log Error Heatmap</p>
    <h2 class="ap-page-title mb-1">Log Error Heatmap</h2>
    <p class="ap-page-sub mb-0">Top error signatures from docker + file logs grouped by service and time bucket.</p>
  </div>
  <div class="d-flex align-items-center gap-2 flex-wrap">
    <div id="apHeatRefreshMeta" class="ap-live-refresh-meta" aria-live="polite">
      <span id="apHeatUpdatedAt" class="ap-live-meta">Next refresh in --:--</span>
      <span class="ap-live-countdown-track" aria-hidden="true">
        <span id="apHeatCountdownBar" class="ap-live-countdown-bar"></span>
      </span>
      <small id="apHeatLastUpdated" class="ap-live-meta-sub">Waiting for first snapshot...</small>
    </div>
  </div>
</section>

<div id="apHeatError" class="ap-live-error d-none mb-2" role="status" aria-live="polite"></div>

<section class="row g-3 mt-1">
  <div class="col-12">
    <article class="card ap-card h-100">
      <header class="card-header ap-card-head ap-card-head-wrap">
        <div>
          <h4 class="ap-card-title mb-1">Filters</h4>
          <p id="apHeatMeta" class="ap-card-sub mb-0">Error buckets and signatures.</p>
        </div>
        <div class="ap-head-tools">
          <div class="ap-live-matrix-tools">
            <select id="apHeatSince" class="form-select form-select-sm ap-live-tool-select" aria-label="Since">
              <option value="1h">Since: 1h</option>
              <option value="6h">Since: 6h</option>
              <option value="24h" selected>Since: 24h</option>
              <option value="7d">Since: 7d</option>
            </select>
            <select id="apHeatBucket" class="form-select form-select-sm ap-live-tool-select" aria-label="Bucket">
              <option value="5">Bucket: 5m</option>
              <option value="15" selected>Bucket: 15m</option>
              <option value="30">Bucket: 30m</option>
              <option value="60">Bucket: 60m</option>
            </select>
            <select id="apHeatTop" class="form-select form-select-sm ap-live-tool-select" aria-label="Top signatures">
              <option value="5">Top: 5</option>
              <option value="12" selected>Top: 12</option>
              <option value="20">Top: 20</option>
            </select>
            <select id="apHeatLineLimit" class="form-select form-select-sm ap-live-tool-select" aria-label="Line limit">
              <option value="500">Lines: 500</option>
              <option value="1000" selected>Lines: 1000</option>
              <option value="2000">Lines: 2000</option>
            </select>
            <button id="apHeatAuto" class="btn ap-chip-btn" type="button" aria-pressed="false">Auto</button>
            <button id="apHeatRefreshBtn" class="btn ap-ghost-btn" type="button"><i class="bi bi-arrow-repeat me-1"></i> Refresh</button>
          </div>
        </div>
      </header>
      <div class="card-body">
        <div id="apHeatSummary" class="ap-monitor-summary mb-3"></div>
        <div class="table-responsive ap-local-sticky mb-3">
          <table class="table ap-table ap-table-sticky ap-table-emphasis mb-0">
            <thead><tr><th>Signature</th><th class="text-end">Count</th></tr></thead>
            <tbody id="apHeatSigRows">
            <tr><td colspan="2" class="text-center ap-page-sub py-4">Loading...</td></tr>
            </tbody>
          </table>
        </div>
        <div class="table-responsive ap-local-sticky">
          <table class="table ap-table ap-table-sticky ap-table-emphasis mb-0">
            <thead><tr><th>Service</th><th class="text-end">Count</th><th>Bucket Distribution</th></tr></thead>
            <tbody id="apHeatServiceRows">
            <tr><td colspan="3" class="text-center ap-page-sub py-4">Loading...</td></tr>
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

    var sigRowsEl = document.getElementById("apHeatSigRows");
    var serviceRowsEl = document.getElementById("apHeatServiceRows");
    if (!sigRowsEl || !serviceRowsEl) {
      return;
    }

    var basePath = (document.body && document.body.getAttribute("data-ap-base")) || "";
    if (basePath === "/") {
      basePath = "";
    }
    var apiUrl = basePath + "/api/log-heatmap";

    var sinceEl = document.getElementById("apHeatSince");
    var bucketEl = document.getElementById("apHeatBucket");
    var topEl = document.getElementById("apHeatTop");
    var lineLimitEl = document.getElementById("apHeatLineLimit");
    var autoBtn = document.getElementById("apHeatAuto");
    var refreshBtn = document.getElementById("apHeatRefreshBtn");
    var metaEl = document.getElementById("apHeatMeta");
    var summaryEl = document.getElementById("apHeatSummary");
    var errEl = document.getElementById("apHeatError");
    var refreshMetaEl = document.getElementById("apHeatRefreshMeta");
    var updatedAtEl = document.getElementById("apHeatUpdatedAt");
    var lastUpdatedEl = document.getElementById("apHeatLastUpdated");
    var countdownBarEl = document.getElementById("apHeatCountdownBar");

    var refreshTimer = null;
    var refreshCountdownTimer = null;
    var refreshIntervalMs = 15000;
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
      refreshIntervalMs = wait > 0 ? wait : 15000;
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
          updatedAtEl.textContent = "Refreshing log heatmap...";
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
        since: sinceEl ? String(sinceEl.value || "24h").trim() : "24h",
        bucketMin: bucketEl ? Math.max(1, Math.min(120, Number(bucketEl.value || "15"))) : 15,
        top: topEl ? Math.max(1, Math.min(100, Number(topEl.value || "12"))) : 12,
        lineLimit: lineLimitEl ? Math.max(100, Math.min(5000, Number(lineLimitEl.value || "1000"))) : 1000
      };
    }

    function isAutoRefreshEnabled() {
      return !!(autoBtn && autoBtn.classList.contains("is-active"));
    }

    function renderSummary(summary) {
      var s = summary && typeof summary === "object" ? summary : {};
      summaryEl.innerHTML = ""
        + '<span class="ap-kv-group ap-live-state-unhealthy"><span class="ap-kv-group-key">Errors</span><span class="ap-kv-group-val">' + numberText(s.errors) + "</span></span>"
        + '<span class="ap-kv-group ap-live-state-info"><span class="ap-kv-group-key">Services</span><span class="ap-kv-group-val">' + numberText(s.services) + "</span></span>"
        + '<span class="ap-kv-group ap-live-state-info"><span class="ap-kv-group-key">Buckets</span><span class="ap-kv-group-val">' + numberText(s.buckets) + "</span></span>"
        + '<span class="ap-kv-group ap-live-state-info"><span class="ap-kv-group-key">Top Signatures</span><span class="ap-kv-group-val">' + numberText(s.top_signatures) + "</span></span>";
    }

    function renderSigRows(rows) {
      var items = Array.isArray(rows) ? rows : [];
      sigRowsEl.innerHTML = items.length === 0
        ? '<tr><td colspan="2" class="text-center ap-page-sub py-4">No error signatures found.</td></tr>'
        : items.map(function (row) {
          return '<tr><td>' + esc(String(row.signature || "-")) + '</td><td class="text-end">' + numberText(row.count) + '</td></tr>';
        }).join("");
    }

    function renderServiceRows(rows) {
      var items = Array.isArray(rows) ? rows : [];
      serviceRowsEl.innerHTML = items.length === 0
        ? '<tr><td colspan="3" class="text-center ap-page-sub py-4">No service heatmap rows found.</td></tr>'
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

    function buildUrl() {
      var f = getFilters();
      var qp = new URLSearchParams();
      qp.set("since", f.since);
      qp.set("bucket_min", String(Math.round(f.bucketMin)));
      qp.set("top", String(Math.round(f.top)));
      qp.set("line_limit", String(Math.round(f.lineLimit)));
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
            throw new Error(payload && payload.message ? payload.message : ("log heatmap api failed (" + String(result.status || 500) + ")"));
          }
          renderSummary(payload.summary || {});
          renderSigRows(payload.top_signatures || []);
          renderServiceRows(payload.services || []);
          lastGeneratedAt = String(payload.generated_at || "");
          activeProject = String(payload.project || "-");
          if (metaEl) {
            metaEl.textContent = "Project: " + activeProject + " | Errors: " + numberText(payload.summary && payload.summary.errors);
          }
        })
        .catch(function (err) {
          renderSummary({});
          renderSigRows([]);
          renderServiceRows([]);
          showError(err && err.message ? err.message : "Unable to load log heatmap.");
        })
        .finally(function () {
          setLoading(false);
          if (isAutoRefreshEnabled()) {
            scheduleNextRefresh(15000);
          } else {
            clearNextRefresh();
            updateRefreshMeta();
          }
        });
    }

    function rebindAutoRefresh() {
      if (isAutoRefreshEnabled()) {
        scheduleNextRefresh(15000);
      } else {
        clearNextRefresh();
        updateRefreshMeta();
      }
    }

    if (refreshBtn) {
      refreshBtn.addEventListener("click", refreshSnapshot);
    }
    [sinceEl, bucketEl, topEl, lineLimitEl].forEach(function (el) {
      if (el) {
        el.addEventListener("change", refreshSnapshot);
      }
    });
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
