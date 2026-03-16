<?php
declare(strict_types=1);
?>

<section class="ap-page-head">
  <div>
    <p class="ap-breadcrumb mb-1">Home / Monitoring / TLS / mTLS</p>
    <h2 class="ap-page-title mb-1">TLS / mTLS Monitor</h2>
    <p class="ap-page-sub mb-0">Per-host certificate, policy drift, TLS posture, trend, and mTLS handshake checks.</p>
  </div>
  <div class="d-flex align-items-center gap-2 flex-wrap">
    <div id="apTlsRefreshMeta" class="ap-live-refresh-meta" aria-live="polite">
      <div class="ap-live-meta-row">
        <span id="apTlsUpdatedAt" class="ap-live-meta">Next refresh in --:--</span>
        <div class="ap-live-meta-controls">
          <label class="ap-live-auto-switch" for="apTlsAuto">
            <span class="ap-live-auto-switch-label">Auto</span>
            <input id="apTlsAuto" type="checkbox" role="switch" aria-label="Auto refresh TLS monitor">
          </label>
          <button id="apTlsRefreshBtn" class="btn ap-live-meta-refresh" type="button" aria-label="Refresh TLS monitor" title="Refresh">
            <i class="bi bi-arrow-repeat"></i>
          </button>
        </div>
      </div>
      <span class="ap-live-countdown-track" aria-hidden="true">
        <span id="apTlsCountdownBar" class="ap-live-countdown-bar"></span>
      </span>
      <small id="apTlsLastUpdated" class="ap-live-meta-sub">Waiting for first snapshot...</small>
    </div>
  </div>
</section>

<div id="apTlsError" class="ap-live-error d-none mb-2" role="status" aria-live="polite"></div>

<section class="row g-3 mt-1">
  <div class="col-12">
    <article class="card ap-card h-100">
      <header class="card-header ap-card-head ap-card-head-wrap">
        <div>
          <h4 class="ap-card-title mb-1">Filters</h4>
          <p id="apTlsMeta" class="ap-card-sub mb-0">Inspect host TLS/mTLS policy and posture from SERVER_TOOLS.</p>
        </div>
        <div class="ap-head-tools">
          <div class="ap-live-matrix-tools">
            <input id="apTlsDomain" class="form-control form-control-sm ap-live-tool-input" type="search" placeholder="Domain filter (partial or *.wildcard)">
            <select id="apTlsTimeout" class="form-select form-select-sm ap-live-tool-select" aria-label="Timeout">
              <option value="2">Timeout: 2s</option>
              <option value="4" selected>Timeout: 4s</option>
              <option value="6">Timeout: 6s</option>
              <option value="10">Timeout: 10s</option>
            </select>
            <select id="apTlsRetries" class="form-select form-select-sm ap-live-tool-select" aria-label="Probe retries">
              <option value="1">Retries: 1</option>
              <option value="2" selected>Retries: 2</option>
              <option value="3">Retries: 3</option>
              <option value="4">Retries: 4</option>
            </select>
          </div>
        </div>
      </header>
      <div class="card-body">
        <div id="apTlsSummary" class="ap-monitor-summary mb-3"></div>
        <div id="apTlsAlerts" class="mb-3"></div>
        <div class="table-responsive ap-local-sticky">
          <table class="table ap-table ap-table-sticky ap-table-emphasis mb-0">
            <thead>
            <tr>
              <th>Domain</th>
              <th>State</th>
              <th>Access Profile</th>
              <th>Certificate Window</th>
              <th>TLS Posture</th>
              <th>Policy & Trust</th>
            </tr>
            </thead>
            <tbody id="apTlsRows">
            <tr><td colspan="6" class="text-center ap-page-sub py-4">Loading...</td></tr>
            </tbody>
          </table>
        </div>
      </div>
    </article>
  </div>
</section>

<div class="modal fade" id="apTlsDetailsModal" tabindex="-1" aria-labelledby="apTlsDetailsTitle" aria-hidden="true">
  <div class="modal-dialog modal-lg modal-dialog-scrollable">
    <div class="modal-content">
      <div class="modal-header">
        <h5 id="apTlsDetailsTitle" class="modal-title">TLS Details</h5>
        <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
      </div>
      <div class="modal-body">
        <div id="apTlsDetailsBody" class="ap-tls-detail-body">-</div>
      </div>
    </div>
  </div>
</div>

<script>
  (function () {
    "use strict";

    var rowsEl = document.getElementById("apTlsRows");
    if (!rowsEl) {
      return;
    }

    var basePath = (document.body && document.body.getAttribute("data-ap-base")) || "";
    if (basePath === "/") {
      basePath = "";
    }
    var apiUrl = basePath + "/api/tls-monitor";

    var domainEl = document.getElementById("apTlsDomain");
    var timeoutEl = document.getElementById("apTlsTimeout");
    var retriesEl = document.getElementById("apTlsRetries");
    var autoBtn = document.getElementById("apTlsAuto");
    var refreshBtn = document.getElementById("apTlsRefreshBtn");
    var metaEl = document.getElementById("apTlsMeta");
    var summaryEl = document.getElementById("apTlsSummary");
    var alertsEl = document.getElementById("apTlsAlerts");
    var errEl = document.getElementById("apTlsError");
    var refreshMetaEl = document.getElementById("apTlsRefreshMeta");
    var updatedAtEl = document.getElementById("apTlsUpdatedAt");
    var lastUpdatedEl = document.getElementById("apTlsLastUpdated");
    var countdownBarEl = document.getElementById("apTlsCountdownBar");
    var detailModalEl = document.getElementById("apTlsDetailsModal");
    var detailTitleEl = document.getElementById("apTlsDetailsTitle");
    var detailBodyEl = document.getElementById("apTlsDetailsBody");

    var refreshTimer = null;
    var refreshCountdownTimer = null;
    var refreshIntervalMs = 10000;
    var nextRefreshAt = 0;
    var lastGeneratedAt = "";
    var activeProject = "-";
    var activeTarget = "-";
    var loading = false;
    var tooltipInstances = [];
    var detailModal = null;
    var detailStore = Object.create(null);
    var detailSeed = 0;

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

    function trendToneClass(trend) {
      var t = String(trend || "").toLowerCase();
      if (t === "improved") {
        return "ap-live-state-running";
      }
      if (t === "regressed") {
        return "ap-live-state-unhealthy";
      }
      return "ap-live-state-info";
    }

    function shortText(value, maxLen) {
      var text = String(value || "");
      var size = Number(maxLen || 40);
      if (!isFinite(size) || size < 4) {
        size = 40;
      }
      if (text.length <= size) {
        return text;
      }
      return text.slice(0, size - 1) + "…";
    }

    function humanizeToken(value) {
      var raw = String(value || "").trim();
      if (!raw || raw === "-") {
        return "-";
      }
      var normalized = raw.replace(/_/g, " ").replace(/\s+/g, " ").trim();
      var pretty = normalized.replace(/\b[a-z]/g, function (m) { return m.toUpperCase(); });
      pretty = pretty.replace(/\bMtls\b/g, "mTLS")
        .replace(/\bTls\b/g, "TLS")
        .replace(/\bOcsp\b/g, "OCSP")
        .replace(/\bSan\b/g, "SAN");
      return pretty;
    }

    function tokenListText(value) {
      var raw = String(value || "").trim();
      if (!raw || raw === "-" || raw === "ok") {
        return "";
      }
      return raw.split(",").map(function (part) {
        return humanizeToken(part);
      }).filter(function (part) {
        return part !== "-";
      }).join(", ");
    }

    function httpCodeTone(code) {
      var raw = String(code || "000");
      if (/^[23][0-9]{2}$/.test(raw)) {
        return "ap-live-state-running";
      }
      if (raw === "000" || /^[5][0-9]{2}$/.test(raw)) {
        return "ap-live-state-unhealthy";
      }
      return "ap-live-state-starting";
    }

    function boolTone(ok, checked) {
      if (checked === false) {
        return "ap-live-state-starting";
      }
      return ok ? "ap-live-state-running" : "ap-live-state-unhealthy";
    }

    function boolText(ok, checked) {
      if (checked === false) {
        return "N/A";
      }
      return ok ? "Yes" : "No";
    }

    function tooltipText(text) {
      var raw = String(text || "").trim();
      if (raw === "") {
        return "";
      }
      return ' data-bs-toggle="tooltip" data-bs-placement="top" data-bs-title="' + esc(raw) + '"';
    }

    function disposeTooltips() {
      if (!Array.isArray(tooltipInstances) || tooltipInstances.length === 0) {
        tooltipInstances = [];
        return;
      }
      tooltipInstances.forEach(function (instance) {
        if (!instance || typeof instance.dispose !== "function") {
          return;
        }
        try {
          instance.dispose();
        } catch (e) {
        }
      });
      tooltipInstances = [];
    }

    function initTooltips(scopeEl) {
      disposeTooltips();
      if (!window.bootstrap || typeof window.bootstrap.Tooltip !== "function") {
        return;
      }
      var root = scopeEl && scopeEl.querySelectorAll ? scopeEl : document;
      var nodes = root.querySelectorAll('[data-bs-toggle="tooltip"]');
      nodes.forEach(function (node) {
        tooltipInstances.push(new window.bootstrap.Tooltip(node, {
          container: "body",
          trigger: "hover focus"
        }));
      });
    }

    function resetDetailStore() {
      detailStore = Object.create(null);
      detailSeed = 0;
    }

    function registerDetail(title, body) {
      detailSeed += 1;
      var id = "tlsd_" + String(detailSeed);
      detailStore[id] = {
        title: String(title || "TLS Details"),
        body: String(body || "-")
      };
      return id;
    }

    function detailButton(groupLabel, summaryValue, detailId, tone, hint, iconClass) {
      var btnLabel = String(groupLabel || "Details");
      var btnValue = String(summaryValue || "-");
      var ref = String(detailId || "");
      var btnTone = String(tone || "ap-live-state-info");
      var btnHint = String(hint || "Open details");
      var icon = String(iconClass || "bi bi-info-circle");
      return '<button type="button" class="ap-kv-group ap-tls-group-btn ' + esc(btnTone) + '"' + tooltipText(btnHint) + ' data-ap-tls-detail-id="' + esc(ref) + '"><span class="ap-kv-group-key"><i class="' + esc(icon) + ' ap-tls-group-icon" aria-hidden="true"></i>' + esc(btnLabel) + '</span><span class="ap-kv-group-val ap-tls-group-val">' + esc(btnValue) + "</span></button>";
    }

    function prettyWord(value) {
      var raw = String(value || "").trim();
      if (raw === "") {
        return "-";
      }
      return raw.charAt(0).toUpperCase() + raw.slice(1).toLowerCase();
    }

    function ensureDetailModal() {
      if (!detailModalEl || !window.bootstrap || typeof window.bootstrap.Modal !== "function") {
        return null;
      }
      if (!detailModal) {
        detailModal = new window.bootstrap.Modal(detailModalEl);
      }
      return detailModal;
    }

    function showDetailModal(title, body) {
      if (detailTitleEl) {
        detailTitleEl.textContent = String(title || "TLS Details");
      }
      if (detailBodyEl) {
        var lines = String(body || "-")
          .split("\n")
          .map(function (line) { return String(line || "").trim(); })
          .filter(function (line) { return line !== ""; });
        if (lines.length === 0) {
          detailBodyEl.innerHTML = "<p class=\"mb-0 ap-page-sub\">-</p>";
        } else {
          var rowsHtml = lines.map(function (line) {
            var idx = line.indexOf(":");
            var key = "Detail";
            var value = line;
            if (idx > 0) {
              key = line.slice(0, idx).trim() || "Detail";
              value = line.slice(idx + 1).trim();
            }
            return "<tr><th>" + esc(key) + "</th><td>" + esc(value || "-") + "</td></tr>";
          }).join("");
          detailBodyEl.innerHTML = '<div class="table-responsive"><table class="table table-sm ap-table mb-0 ap-tls-detail-table"><tbody>' + rowsHtml + "</tbody></table></div>";
        }
      }
      var modal = ensureDetailModal();
      if (modal) {
        modal.show();
      }
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
          updatedAtEl.textContent = "Refreshing TLS monitor...";
        } else if (hasNext) {
          updatedAtEl.textContent = "Next refresh in " + formatCountdown(remainingMs);
        } else {
          updatedAtEl.textContent = "Next refresh in --:--";
        }
      }
      if (lastUpdatedEl) {
        if (lastGeneratedAt) {
          lastUpdatedEl.textContent = "Last update " + formatUpdatedAt(lastGeneratedAt) + " | Project " + activeProject + " | Target " + activeTarget;
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
      var timeout = timeoutEl ? Number(timeoutEl.value || "4") : 4;
      var retries = retriesEl ? Number(retriesEl.value || "2") : 2;
      if (!isFinite(timeout) || timeout <= 0) {
        timeout = 4;
      }
      if (!isFinite(retries) || retries <= 0) {
        retries = 2;
      }
      return {
        domain: domainEl ? String(domainEl.value || "").trim().toLowerCase() : "",
        timeout: Math.max(1, Math.min(20, Math.round(timeout))),
        retries: Math.max(1, Math.min(5, Math.round(retries)))
      };
    }

    function isAutoRefreshEnabled() {
      return !!(autoBtn && autoBtn.checked);
    }

    function renderSummary(summary) {
      var data = summary && typeof summary === "object" ? summary : {};
      summaryEl.innerHTML = ""
        + '<span class="ap-kv-group ap-live-state-info"><span class="ap-kv-group-key">Hosts</span><span class="ap-kv-group-val">' + esc(String(data.hosts || 0)) + "</span></span>"
        + '<span class="ap-kv-group ap-live-state-running"><span class="ap-kv-group-key">Pass</span><span class="ap-kv-group-val">' + esc(String(data.pass || 0)) + "</span></span>"
        + '<span class="ap-kv-group ap-live-state-starting"><span class="ap-kv-group-key">Warn</span><span class="ap-kv-group-val">' + esc(String(data.warn || 0)) + "</span></span>"
        + '<span class="ap-kv-group ap-live-state-unhealthy"><span class="ap-kv-group-key">Fail</span><span class="ap-kv-group-val">' + esc(String(data.fail || 0)) + "</span></span>"
        + '<span class="ap-kv-group ap-live-state-info"><span class="ap-kv-group-key">mTLS Req</span><span class="ap-kv-group-val">' + esc(String(data.mtls_required || 0)) + "</span></span>"
        + '<span class="ap-kv-group ap-live-state-unhealthy"><span class="ap-kv-group-key">mTLS Broken</span><span class="ap-kv-group-val">' + esc(String(data.mtls_broken || 0)) + "</span></span>"
        + '<span class="ap-kv-group ap-live-state-starting"><span class="ap-kv-group-key">Policy Drift</span><span class="ap-kv-group-val">' + esc(String(data.policy_drift || 0)) + "</span></span>"
        + '<span class="ap-kv-group ap-live-state-starting"><span class="ap-kv-group-key">OCSP Missing</span><span class="ap-kv-group-val">' + esc(String(data.ocsp_missing || 0)) + "</span></span>"
        + '<span class="ap-kv-group ap-live-state-starting"><span class="ap-kv-group-key">No Intermediate</span><span class="ap-kv-group-val">' + esc(String(data.no_intermediate || 0)) + "</span></span>"
        + '<span class="ap-kv-group ap-live-state-unhealthy"><span class="ap-kv-group-key">TLS Legacy</span><span class="ap-kv-group-val">' + esc(String(data.tls_legacy || 0)) + "</span></span>"
        + '<span class="ap-kv-group ap-live-state-info"><span class="ap-kv-group-key">Alerts</span><span class="ap-kv-group-val">' + esc(String(data.alerts || 0)) + "</span></span>"
        + '<span class="ap-kv-group ap-live-state-starting"><span class="ap-kv-group-key">Expiring</span><span class="ap-kv-group-val">' + esc(String(data.expiring_14d || 0)) + "</span></span>"
        + '<span class="ap-kv-group ap-live-state-unhealthy"><span class="ap-kv-group-key">Expired</span><span class="ap-kv-group-val">' + esc(String(data.expired || 0)) + "</span></span>";
    }

    function renderAlerts(payload) {
      if (!alertsEl) {
        return;
      }
      var alerts = Array.isArray(payload && payload.alerts) ? payload.alerts : [];
      if (alerts.length === 0) {
        alertsEl.innerHTML = '<p class="ap-page-sub mb-0">No TLS transition alerts in this snapshot.</p>';
        return;
      }
      alertsEl.innerHTML = alerts.slice(0, 8).map(function (item) {
        var domain = String(item && item.domain || "-");
        var type = String(item && item.type || "alert");
        var sev = String(item && item.severity || "medium").toLowerCase();
        var msg = String(item && item.message || "-");
        var sevClass = sev === "high" ? "ap-live-state-unhealthy" : (sev === "low" ? "ap-live-state-info" : "ap-live-state-starting");
        return ""
          + '<div class="d-flex align-items-start gap-2 mb-1">'
          + '  <span class="ap-badge ' + esc(sevClass) + '">' + esc(sev) + "</span>"
          + '  <span class="ap-page-sub"><strong>' + esc(domain) + "</strong> · " + esc(type) + " · " + esc(msg) + "</span>"
          + "</div>";
      }).join("");
    }

    function renderRows(payload) {
      var items = Array.isArray(payload && payload.items) ? payload.items : [];
      if (items.length === 0) {
        disposeTooltips();
        rowsEl.innerHTML = '<tr><td colspan="6" class="text-center ap-page-sub py-4">No TLS hosts found for current filters.</td></tr>';
        return;
      }

      items.sort(function (a, b) {
        var ad = String(a && a.domain || "");
        var bd = String(b && b.domain || "");
        return ad.localeCompare(bd);
      });

      resetDetailStore();
      rowsEl.innerHTML = items.map(function (item) {
        var domain = String(item && item.domain || "-");
        var state = String(item && item.state || "warn");
        var trend = String(item && item.trend_state || "stable");
        var mtls = String(item && item.mtls_mode || "-");
        var subject = String(item && item.subject || "-");
        var expiresAt = String(item && item.expires_at || "-");
        var daysLeft = Number(item && item.days_left != null ? item.days_left : -1);
        var sanMatch = !!(item && item.san_match);
        var chainOk = !!(item && item.chain_ok);
        var chainChecked = !(item && item.chain_checked === false);
        var chainDepth = Number(item && item.chain_depth != null ? item.chain_depth : 0);
        var hasIntermediate = !!(item && item.has_intermediate);
        var ocsp = String(item && item.ocsp_status || "-");
        var noClient = String(item && item.http_no_client || "-");
        var withClient = String(item && item.http_with_client || "-");
        var verifyCode = String(item && item.verify_code || "-");
        var tlsVersion = String(item && item.tls_version || "-");
        var tlsCipher = String(item && item.tls_cipher || "-");
        var tlsTextFull = tlsVersion + (tlsCipher !== "-" && tlsCipher !== "" ? (" / " + tlsCipher) : "");
        var policyExpected = String(item && item.policy_expected_mtls || "any");
        var policyMinDays = Number(item && item.policy_min_days != null ? item.policy_min_days : -1);
        var policyStrict = !(item && item.policy_san_strict === false);
        var policyOk = !(item && item.policy_ok === false);
        var policyDrift = String(item && item.policy_drift || "-");
        var policyClass = policyOk ? "ap-live-state-running" : "ap-live-state-starting";
        var ocspClass = (ocsp === "stapled" || ocsp === "present") ? "ap-live-state-running" : "ap-live-state-starting";
        var note = String(item && item.note || "-");
        var postureNote = tokenListText(item && item.posture_note);
        var noteText = tokenListText(note);
        var driftText = tokenListText(policyDrift);
        var daysText = isFinite(daysLeft) && daysLeft > -9999 ? String(daysLeft) : "-";
        var daysClass = "ap-live-state-info";
        if (isFinite(daysLeft) && daysLeft >= 0) {
          daysClass = daysLeft <= 14 ? "ap-live-state-starting" : "ap-live-state-running";
        } else if (isFinite(daysLeft) && daysLeft < 0) {
          daysClass = "ap-live-state-unhealthy";
        }
        var verifyClass = verifyCode === "0 (ok)" ? "ap-live-state-running" : (verifyCode === "rootca_missing" ? "ap-live-state-starting" : "ap-live-state-unhealthy");
        var intermediateClass = hasIntermediate ? "ap-live-state-running" : "ap-live-state-starting";
        var stateTone = toneClass(state);
        var mtlsRequired = /require/.test(mtls.toLowerCase());
        var withClientSuccess = /^[23][0-9]{2}$/.test(withClient);
        var noClientSuccess = /^[23][0-9]{2}$/.test(noClient);
        var accessTone = withClientSuccess ? ((mtlsRequired && noClientSuccess) ? "ap-live-state-starting" : "ap-live-state-running") : httpCodeTone(withClient);
        var mtlsLower = String(mtls || "").toLowerCase();
        if (mtlsLower === "broken" || mtlsLower === "error") {
          accessTone = "ap-live-state-unhealthy";
        } else if (mtlsLower === "required" && noClientSuccess) {
          accessTone = "ap-live-state-unhealthy";
        }
        var postureTone = "ap-live-state-info";
        if (/tlsv1(\.0|\.1)?/i.test(tlsVersion) || /^TLSv1\.[01]$/i.test(tlsVersion)) {
          postureTone = "ap-live-state-unhealthy";
        } else if (ocspClass === "ap-live-state-running" && intermediateClass === "ap-live-state-running") {
          postureTone = "ap-live-state-running";
        } else if (ocspClass === "ap-live-state-starting" || intermediateClass === "ap-live-state-starting") {
          postureTone = "ap-live-state-starting";
        }
        var policyTone = policyClass;
        if (!policyOk && (verifyClass === "ap-live-state-unhealthy" || !sanMatch || (chainChecked && !chainOk))) {
          policyTone = "ap-live-state-unhealthy";
        }

        var stateSummary = prettyWord(state) + " (" + prettyWord(trend) + ")";
        var stateDetails = [
          "State: " + state,
          "Trend: " + trend,
          "Reason: " + (noteText || "-"),
          "Posture: " + (postureNote || "-"),
          "Drift: " + (driftText || "-")
        ].join("\n");
        var accessSummary = "mTLS " + prettyWord(mtls);
        var accessDetails = [
          "mTLS mode: " + mtls,
          "HTTP no-cert: " + noClient,
          "HTTP with-cert: " + withClient,
          "Subject: " + subject
        ].join("\n");
        var certHint = expiresAt && expiresAt !== "-" ? ("Certificate expires at " + expiresAt) : "Certificate expiration timestamp unavailable.";
        var certSummary = /^-?[0-9]+$/.test(daysText) ? (daysText + " days left") : "Unknown";
        var certDetails = [
          "Days left: " + daysText,
          "Expires at: " + expiresAt,
          "Policy min days: " + (isFinite(policyMinDays) && policyMinDays >= 0 ? String(policyMinDays) : "-")
        ].join("\n");
        var postureSummary = shortText((tlsVersion !== "-" ? tlsVersion : "TLS unknown") + " · OCSP " + ocsp, 28);
        var postureDetails = [
          "TLS/Cipher: " + tlsTextFull,
          "OCSP: " + ocsp,
          "Intermediate present: " + (hasIntermediate ? "Yes" : "No")
        ].join("\n");

        var chainStatusText = boolText(chainOk, chainChecked);
        if (chainChecked !== false) {
          chainStatusText += " d" + String(Math.max(0, Math.round(chainDepth)));
        }
        var policySummary = policyOk ? "Policy Compliant" : "Policy Drift";
        var policyDetails = [
          "Policy status: " + policySummary,
          "Expected mTLS: " + policyExpected,
          "Min days: " + (isFinite(policyMinDays) && policyMinDays >= 0 ? String(policyMinDays) : "-"),
          "SAN mode: " + (policyStrict ? "Strict" : "Soft"),
          "SAN match: " + boolText(sanMatch, true),
          "Chain: " + chainStatusText,
          "Verify: " + verifyCode,
          "Drift: " + (driftText || "-")
        ].join("\n");
        var stateDetailId = registerDetail(domain + " state", stateDetails);
        var accessDetailId = registerDetail(domain + " access profile", accessDetails);
        var certDetailId = registerDetail(domain + " certificate window", certDetails);
        var postureDetailId = registerDetail(domain + " TLS posture", postureDetails);
        var policyDetailId = registerDetail(domain + " policy & trust", policyDetails);
        var stateHint = "State: " + prettyWord(state) + " | Trend: " + prettyWord(trend) + ". Click for details.";
        var accessHint = "mTLS: " + prettyWord(mtls) + " | HTTP no-cert: " + noClient + " | with-cert: " + withClient + ". Click for details.";
        var certChipHint = certHint + " Click for details.";
        var postureHint = "TLS: " + (tlsVersion !== "-" ? tlsVersion : "unknown") + " | OCSP: " + ocsp + " | Intermediate: " + (hasIntermediate ? "Yes" : "No") + ". Click for details.";
        var policyHint = "Policy: " + policySummary + " | Verify: " + verifyCode + " | SAN: " + (sanMatch ? "match" : "mismatch") + ". Click for details.";

        return ""
          + "<tr>"
          + "  <td>" + esc(domain) + "</td>"
          + '  <td><div class="ap-tls-cell">' + detailButton("State", stateSummary, stateDetailId, stateTone, stateHint, "bi bi-activity") + "</div></td>"
          + '  <td><div class="ap-tls-cell">' + detailButton("Access", accessSummary, accessDetailId, accessTone, accessHint, "bi bi-person-lock") + "</div></td>"
          + '  <td><div class="ap-tls-cell">' + detailButton("Certificate", certSummary, certDetailId, daysClass, certChipHint, "bi bi-calendar-check") + "</div></td>"
          + '  <td><div class="ap-tls-cell">' + detailButton("Posture", postureSummary, postureDetailId, postureTone, postureHint, "bi bi-shield-check") + "</div></td>"
          + '  <td><div class="ap-tls-cell">' + detailButton("Policy", policySummary, policyDetailId, policyTone, policyHint, "bi bi-clipboard2-check") + "</div></td>"
          + "</tr>";
      }).join("");
      initTooltips(rowsEl);
    }

    function buildUrl() {
      var filters = getFilters();
      var qp = new URLSearchParams();
      qp.set("timeout", String(filters.timeout));
      qp.set("retries", String(filters.retries));
      if (filters.domain !== "") {
        qp.set("domain", filters.domain);
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
            throw new Error(payload && payload.message ? payload.message : ("tls monitor api failed (" + String(result.status || 500) + ")"));
          }
          renderSummary(payload.summary || {});
          renderAlerts(payload);
          renderRows(payload);
          lastGeneratedAt = String(payload.generated_at || "");
          activeProject = String(payload.project || "-");
          activeTarget = String(payload && payload.filters && payload.filters.target || "-");
          if (metaEl) {
            metaEl.textContent = "Project: " + activeProject + " | Hosts: " + String((payload.summary && payload.summary.hosts) || 0) + " | Target: " + activeTarget + " | Alerts: " + String((payload.summary && payload.summary.alerts) || 0);
          }
        })
        .catch(function (err) {
          renderSummary({});
          renderAlerts({ alerts: [] });
          renderRows({ items: [] });
          showError(err && err.message ? err.message : "Unable to load TLS monitor.");
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
    rowsEl.addEventListener("click", function (event) {
      var target = event.target;
      if (!(target instanceof Element)) {
        return;
      }
      var btn = target.closest("[data-ap-tls-detail-id]");
      if (!btn) {
        return;
      }
      event.preventDefault();
      var ref = String(btn.getAttribute("data-ap-tls-detail-id") || "");
      if (ref === "" || !detailStore[ref]) {
        return;
      }
      showDetailModal(detailStore[ref].title, detailStore[ref].body);
    });
    if (domainEl) {
      domainEl.addEventListener("keydown", function (e) {
        if (e.key === "Enter") {
          e.preventDefault();
          refreshSnapshot();
        }
      });
    }
    if (timeoutEl) {
      timeoutEl.addEventListener("change", refreshSnapshot);
    }
    if (retriesEl) {
      retriesEl.addEventListener("change", refreshSnapshot);
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
