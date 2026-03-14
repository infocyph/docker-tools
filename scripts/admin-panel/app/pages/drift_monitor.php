<?php
declare(strict_types=1);
?>

<section class="ap-page-head">
  <div>
    <p class="ap-breadcrumb mb-1">Home / Monitoring / Config Drift</p>
    <h2 class="ap-page-title mb-1">Config Drift Monitor</h2>
    <p class="ap-page-sub mb-0">Generated config versus active in-container runtime config.</p>
  </div>
  <div class="d-flex align-items-center gap-2 flex-wrap">
    <div id="apDriftRefreshMeta" class="ap-live-refresh-meta" aria-live="polite">
      <span id="apDriftUpdatedAt" class="ap-live-meta">Next refresh in --:--</span>
      <span class="ap-live-countdown-track" aria-hidden="true">
        <span id="apDriftCountdownBar" class="ap-live-countdown-bar"></span>
      </span>
      <small id="apDriftLastUpdated" class="ap-live-meta-sub">Waiting for first snapshot...</small>
    </div>
  </div>
</section>

<div id="apDriftError" class="ap-live-error d-none mb-2" role="status" aria-live="polite"></div>

<section class="row g-3 mt-1">
  <div class="col-12">
    <article class="card ap-card h-100">
      <header class="card-header ap-card-head ap-card-head-wrap">
        <div>
          <h4 class="ap-card-title mb-1">Runtime Drift</h4>
          <p id="apDriftMeta" class="ap-card-sub mb-0">Missing/changed/extra active configs per component.</p>
        </div>
        <div class="ap-head-tools">
          <div class="ap-live-matrix-tools">
            <button id="apDriftAuto" class="btn ap-chip-btn" type="button" aria-pressed="false">Auto</button>
            <button id="apDriftRefreshBtn" class="btn ap-ghost-btn" type="button"><i class="bi bi-arrow-repeat me-1"></i> Refresh</button>
          </div>
        </div>
      </header>
      <div class="card-body">
        <div id="apDriftSummary" class="ap-monitor-summary mb-3"></div>
        <div class="table-responsive ap-local-sticky">
          <table class="table ap-table ap-table-sticky ap-table-emphasis mb-0">
            <thead>
            <tr>
              <th>Component</th>
              <th>Container</th>
              <th class="text-end">State</th>
              <th class="text-end">Source Files</th>
              <th class="text-end">Matched</th>
              <th class="text-end">Changed</th>
              <th class="text-end">Missing</th>
              <th class="text-end">Extra</th>
              <th>Note</th>
            </tr>
            </thead>
            <tbody id="apDriftRows">
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

    var rowsEl = document.getElementById("apDriftRows");
    if (!rowsEl) {
      return;
    }

    var basePath = (document.body && document.body.getAttribute("data-ap-base")) || "";
    if (basePath === "/") {
      basePath = "";
    }
    var apiUrl = basePath + "/api/drift-monitor";

    var autoBtn = document.getElementById("apDriftAuto");
    var refreshBtn = document.getElementById("apDriftRefreshBtn");
    var metaEl = document.getElementById("apDriftMeta");
    var summaryEl = document.getElementById("apDriftSummary");
    var errEl = document.getElementById("apDriftError");
    var refreshMetaEl = document.getElementById("apDriftRefreshMeta");
    var updatedAtEl = document.getElementById("apDriftUpdatedAt");
    var lastUpdatedEl = document.getElementById("apDriftLastUpdated");
    var countdownBarEl = document.getElementById("apDriftCountdownBar");

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
          updatedAtEl.textContent = "Refreshing drift monitor...";
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

    function isAutoRefreshEnabled() {
      return !!(autoBtn && autoBtn.classList.contains("is-active"));
    }

    function renderSummary(summary) {
      var data = summary && typeof summary === "object" ? summary : {};
      summaryEl.innerHTML = ""
        + '<span class="ap-kv-group ap-live-state-info"><span class="ap-kv-group-key">Components</span><span class="ap-kv-group-val">' + numberText(data.components) + "</span></span>"
        + '<span class="ap-kv-group ap-live-state-running"><span class="ap-kv-group-key">Pass</span><span class="ap-kv-group-val">' + numberText(data.pass) + "</span></span>"
        + '<span class="ap-kv-group ap-live-state-starting"><span class="ap-kv-group-key">Warn</span><span class="ap-kv-group-val">' + numberText(data.warn) + "</span></span>"
        + '<span class="ap-kv-group ap-live-state-unhealthy"><span class="ap-kv-group-key">Fail</span><span class="ap-kv-group-val">' + numberText(data.fail) + "</span></span>";
    }

    function renderRows(payload) {
      var items = Array.isArray(payload && payload.items) ? payload.items : [];
      if (items.length === 0) {
        rowsEl.innerHTML = '<tr><td colspan="9" class="text-center ap-page-sub py-4">No drift rows found.</td></tr>';
        return;
      }
      rowsEl.innerHTML = items.map(function (item) {
        return ''
          + '<tr>'
          + '  <td>' + esc(String(item.component || "-")) + '</td>'
          + '  <td>' + esc(String(item.container || "-")) + '</td>'
          + '  <td class="text-end">' + esc(String(item.container_state || "-")) + '</td>'
          + '  <td class="text-end">' + numberText(item.source_files) + '</td>'
          + '  <td class="text-end">' + numberText(item.matched) + '</td>'
          + '  <td class="text-end">' + numberText(item.changed) + '</td>'
          + '  <td class="text-end">' + numberText(item.missing) + '</td>'
          + '  <td class="text-end">' + numberText(item.extra) + '</td>'
          + '  <td><span class="ap-badge ' + esc(toneClass(item.level || "warn")) + '">' + esc(String(item.note || "-")) + '</span></td>'
          + '</tr>';
      }).join("");
    }

    function refreshSnapshot() {
      if (loading) {
        return;
      }
      clearNextRefresh();
      setLoading(true);
      showError("");
      fetch(apiUrl, {
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
            throw new Error(payload && payload.message ? payload.message : ("drift monitor api failed (" + String(result.status || 500) + ")"));
          }
          renderSummary(payload.summary || {});
          renderRows(payload);
          lastGeneratedAt = String(payload.generated_at || "");
          activeProject = String(payload.project || "-");
          if (metaEl) {
            metaEl.textContent = "Project: " + activeProject + " | Components: " + numberText(payload.summary && payload.summary.components);
          }
        })
        .catch(function (err) {
          renderSummary({});
          renderRows({ items: [] });
          showError(err && err.message ? err.message : "Unable to load drift monitor.");
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
