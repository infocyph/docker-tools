<?php
declare(strict_types=1);
?>

<section class="ap-page-head">
  <div>
    <p class="ap-breadcrumb mb-1">Home / Monitoring / Alert Rules</p>
    <h2 class="ap-page-title mb-1">Alert Rules + Quiet Hours</h2>
    <p class="ap-page-sub mb-0">Threshold rules, dedupe/cooldown, acknowledgement, and notify channels.</p>
  </div>
  <div class="d-flex align-items-center gap-2 flex-wrap">
    <div id="apAlertsRefreshMeta" class="ap-live-refresh-meta" aria-live="polite">
      <div class="ap-live-meta-row">
        <span id="apAlertsUpdatedAt" class="ap-live-meta">Next refresh in --:--</span>
        <div class="ap-live-meta-controls">
          <label class="ap-live-auto-switch" for="apAlertsAuto">
            <span class="ap-live-auto-switch-label">Auto</span>
            <input id="apAlertsAuto" type="checkbox" role="switch" aria-label="Auto refresh alerts">
          </label>
          <button id="apAlertsRefreshBtn" class="btn ap-live-meta-refresh" type="button" aria-label="Refresh alerts" title="Refresh">
            <i class="bi bi-arrow-repeat"></i>
          </button>
        </div>
      </div>
      <span class="ap-live-countdown-track" aria-hidden="true">
        <span id="apAlertsCountdownBar" class="ap-live-countdown-bar"></span>
      </span>
      <small id="apAlertsLastUpdated" class="ap-live-meta-sub">Waiting for first snapshot...</small>
    </div>
  </div>
</section>

<div id="apAlertsError" class="ap-live-error d-none mb-2" role="status" aria-live="polite"></div>

<section class="row g-3 mt-1">
  <div class="col-12">
    <article class="card ap-card h-100">
      <header class="card-header ap-card-head ap-card-head-wrap">
        <div>
          <h4 class="ap-card-title mb-1">Actions</h4>
          <p id="apAlertsMeta" class="ap-card-sub mb-0">Evaluate, send notifications, and acknowledge incidents.</p>
        </div>
        <div class="ap-head-tools">
          <div class="ap-live-matrix-tools">
            <button id="apAlertsRunBtn" class="btn ap-ghost-btn ap-monitor-refresh-btn" type="button"><i class="bi bi-send-check me-1"></i> Run Notify</button>
          </div>
        </div>
      </header>
      <div class="card-body">
        <div id="apAlertsSummary" class="ap-monitor-summary mb-3"></div>
        <div class="table-responsive ap-local-sticky">
          <table class="table ap-table ap-table-sticky ap-table-emphasis mb-0">
            <thead>
            <tr>
              <th>Rule</th>
              <th>Metric</th>
              <th class="text-end">Value</th>
              <th class="text-end">Threshold</th>
              <th class="text-end">Severity</th>
              <th class="text-end">Firing</th>
              <th class="text-end">Suppressed</th>
              <th class="text-end">Sent Now</th>
              <th>Reason</th>
              <th>Action</th>
            </tr>
            </thead>
            <tbody id="apAlertsRows">
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

    var rowsEl = document.getElementById("apAlertsRows");
    if (!rowsEl) {
      return;
    }

    var basePath = (document.body && document.body.getAttribute("data-ap-base")) || "";
    if (basePath === "/") {
      basePath = "";
    }
    var apiUrl = basePath + "/api/alerts";

    var autoBtn = document.getElementById("apAlertsAuto");
    var runBtn = document.getElementById("apAlertsRunBtn");
    var refreshBtn = document.getElementById("apAlertsRefreshBtn");
    var metaEl = document.getElementById("apAlertsMeta");
    var summaryEl = document.getElementById("apAlertsSummary");
    var errEl = document.getElementById("apAlertsError");
    var refreshMetaEl = document.getElementById("apAlertsRefreshMeta");
    var updatedAtEl = document.getElementById("apAlertsUpdatedAt");
    var lastUpdatedEl = document.getElementById("apAlertsLastUpdated");
    var countdownBarEl = document.getElementById("apAlertsCountdownBar");

    var refreshTimer = null;
    var refreshCountdownTimer = null;
    var refreshIntervalMs = 15000;
    var nextRefreshAt = 0;
    var lastGeneratedAt = "";
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
      if (s === "yes" || s === "true" || s === "firing") {
        return "ap-live-state-unhealthy";
      }
      if (s === "sent") {
        return "ap-live-state-running";
      }
      return "ap-live-state-info";
    }

    function boolText(value) {
      return value ? "Yes" : "No";
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
      if (runBtn) {
        runBtn.disabled = loading;
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
          updatedAtEl.textContent = "Refreshing alerts...";
        } else if (hasNext) {
          updatedAtEl.textContent = "Next refresh in " + formatCountdown(remainingMs);
        } else {
          updatedAtEl.textContent = "Next refresh in --:--";
        }
      }
      if (lastUpdatedEl) {
        if (lastGeneratedAt) {
          lastUpdatedEl.textContent = "Last update " + formatUpdatedAt(lastGeneratedAt);
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
      return !!(autoBtn && autoBtn.checked);
    }

    function renderSummary(payload) {
      var summary = payload && payload.summary && typeof payload.summary === "object" ? payload.summary : {};
      var quiet = payload && payload.quiet_hours && typeof payload.quiet_hours === "object" ? payload.quiet_hours : {};
      summaryEl.innerHTML = ""
        + '<span class="ap-kv-group ap-live-state-info"><span class="ap-kv-group-key">Rules</span><span class="ap-kv-group-val">' + esc(String(summary.rules || 0)) + "</span></span>"
        + '<span class="ap-kv-group ap-live-state-unhealthy"><span class="ap-kv-group-key">Firing</span><span class="ap-kv-group-val">' + esc(String(summary.firing || 0)) + "</span></span>"
        + '<span class="ap-kv-group ap-live-state-running"><span class="ap-kv-group-key">Sent</span><span class="ap-kv-group-val">' + esc(String(summary.sent || 0)) + "</span></span>"
        + '<span class="ap-kv-group ap-live-state-starting"><span class="ap-kv-group-key">Suppressed</span><span class="ap-kv-group-val">' + esc(String(summary.suppressed || 0)) + "</span></span>"
        + '<span class="ap-kv-group ap-live-state-info"><span class="ap-kv-group-key">Quiet Hours</span><span class="ap-kv-group-val">' + esc(boolText(!!quiet.active)) + "</span></span>";
    }

    function bindAckButtons() {
      Array.prototype.slice.call(rowsEl.querySelectorAll("[data-ack-rule][data-ack-fp]")).forEach(function (btn) {
        btn.addEventListener("click", function () {
          var rule = String(btn.getAttribute("data-ack-rule") || "");
          var fp = String(btn.getAttribute("data-ack-fp") || "");
          if (!rule || !fp) {
            return;
          }
          refreshSnapshot({ run: false, ackRule: rule, ackFingerprint: fp });
        });
      });
    }

    function renderRows(payload) {
      var incidents = Array.isArray(payload && payload.incidents) ? payload.incidents : [];
      if (incidents.length === 0) {
        rowsEl.innerHTML = '<tr><td colspan="10" class="text-center ap-page-sub py-4">No alert incidents found.</td></tr>';
        return;
      }
      rowsEl.innerHTML = incidents.map(function (it) {
        var firing = !!it.firing;
        var suppressed = !!it.suppressed;
        var sentNow = !!it.sent_now;
        var canAck = firing && !suppressed;
        var action = canAck
          ? '<button class="btn ap-ghost-btn btn-sm" type="button" data-ack-rule="' + esc(String(it.id || "")) + '" data-ack-fp="' + esc(String(it.fingerprint || "")) + '">Acknowledge</button>'
          : "-";
        return ""
          + "<tr>"
          + "  <td>" + esc(String(it.id || "-")) + "</td>"
          + "  <td>" + esc(String(it.metric || "-")) + "</td>"
          + '  <td class="text-end">' + esc(String(it.value != null ? it.value : "-")) + "</td>"
          + '  <td class="text-end">' + esc(String(it.op || "-")) + " " + esc(String(it.threshold != null ? it.threshold : "-")) + "</td>"
          + '  <td class="text-end">' + esc(String(it.severity || "-")) + "</td>"
          + '  <td class="text-end"><span class="ap-badge ' + esc(toneClass(firing ? "firing" : "ok")) + '">' + esc(boolText(firing)) + "</span></td>"
          + '  <td class="text-end"><span class="ap-badge ' + esc(toneClass(suppressed ? "yes" : "no")) + '">' + esc(boolText(suppressed)) + "</span></td>"
          + '  <td class="text-end"><span class="ap-badge ' + esc(toneClass(sentNow ? "sent" : "no")) + '">' + esc(boolText(sentNow)) + "</span></td>"
          + "  <td>" + esc(String(it.suppressed_reason || "-")) + "</td>"
          + "  <td>" + action + "</td>"
          + "</tr>";
      }).join("");
      bindAckButtons();
    }

    function buildUrl(options) {
      var opt = options || {};
      var qp = new URLSearchParams();
      if (opt.run) {
        qp.set("run", "1");
      }
      if (opt.ackRule) {
        qp.set("ack_rule", String(opt.ackRule));
      }
      if (opt.ackFingerprint) {
        qp.set("ack_fingerprint", String(opt.ackFingerprint));
      }
      return apiUrl + (qp.toString() ? ("?" + qp.toString()) : "");
    }

    function refreshSnapshot(options) {
      if (loading) {
        return;
      }
      clearNextRefresh();
      setLoading(true);
      showError("");
      fetch(buildUrl(options), {
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
            throw new Error(payload && payload.message ? payload.message : ("alerts api failed (" + String(result.status || 500) + ")"));
          }
          renderSummary(payload);
          renderRows(payload);
          lastGeneratedAt = String(payload.generated_at || "");
          if (metaEl) {
            metaEl.textContent = "Firing: " + esc(String(payload.summary && payload.summary.firing || 0)) + " | Sent: " + esc(String(payload.summary && payload.summary.sent || 0));
          }
        })
        .catch(function (err) {
          renderSummary({});
          renderRows({ incidents: [] });
          showError(err && err.message ? err.message : "Unable to load alerts.");
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
      refreshBtn.addEventListener("click", function () {
        refreshSnapshot({ run: false });
      });
    }
    if (runBtn) {
      runBtn.addEventListener("click", function () {
        refreshSnapshot({ run: true });
      });
    }
    if (autoBtn) {
      autoBtn.addEventListener("change", function () {
        var enabled = !!autoBtn.checked;
        rebindAutoRefresh();
        if (enabled) {
          refreshSnapshot({ run: false });
        } else {
          updateRefreshMeta();
        }
      });
    }

    function startInitialLoad() {
      refreshSnapshot({ run: false });
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
