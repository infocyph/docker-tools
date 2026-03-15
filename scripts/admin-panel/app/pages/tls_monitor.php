<?php
declare(strict_types=1);
?>

<section class="ap-page-head">
  <div>
    <p class="ap-breadcrumb mb-1">Home / Monitoring / TLS / mTLS</p>
    <h2 class="ap-page-title mb-1">TLS / mTLS Monitor</h2>
    <p class="ap-page-sub mb-0">Per-host certificate, SAN, chain, and mTLS handshake checks.</p>
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
          <p id="apTlsMeta" class="ap-card-sub mb-0">Inspect host TLS/mTLS health from SERVER_TOOLS.</p>
        </div>
        <div class="ap-head-tools">
          <div class="ap-live-matrix-tools">
            <input id="apTlsDomain" class="form-control form-control-sm ap-live-tool-input" type="search" placeholder="Domain filter (optional)">
            <select id="apTlsTimeout" class="form-select form-select-sm ap-live-tool-select" aria-label="Timeout">
              <option value="2">Timeout: 2s</option>
              <option value="4" selected>Timeout: 4s</option>
              <option value="6">Timeout: 6s</option>
              <option value="10">Timeout: 10s</option>
            </select>
          </div>
        </div>
      </header>
      <div class="card-body">
        <div id="apTlsSummary" class="ap-monitor-summary mb-3"></div>
        <div class="table-responsive ap-local-sticky">
          <table class="table ap-table ap-table-sticky ap-table-emphasis mb-0">
            <thead>
            <tr>
              <th>Domain</th>
              <th class="text-end">State</th>
              <th class="text-end">mTLS</th>
              <th class="text-end">Days Left</th>
              <th class="text-end">SAN</th>
              <th class="text-end">Chain</th>
              <th class="text-end">HTTP(no cert)</th>
              <th class="text-end">HTTP(with cert)</th>
              <th>Verify</th>
              <th>Note</th>
            </tr>
            </thead>
            <tbody id="apTlsRows">
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
    var autoBtn = document.getElementById("apTlsAuto");
    var refreshBtn = document.getElementById("apTlsRefreshBtn");
    var metaEl = document.getElementById("apTlsMeta");
    var summaryEl = document.getElementById("apTlsSummary");
    var errEl = document.getElementById("apTlsError");
    var refreshMetaEl = document.getElementById("apTlsRefreshMeta");
    var updatedAtEl = document.getElementById("apTlsUpdatedAt");
    var lastUpdatedEl = document.getElementById("apTlsLastUpdated");
    var countdownBarEl = document.getElementById("apTlsCountdownBar");

    var refreshTimer = null;
    var refreshCountdownTimer = null;
    var refreshIntervalMs = 10000;
    var nextRefreshAt = 0;
    var lastGeneratedAt = "";
    var activeProject = "-";
    var activeTarget = "-";
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
      if (!isFinite(timeout) || timeout <= 0) {
        timeout = 4;
      }
      return {
        domain: domainEl ? String(domainEl.value || "").trim().toLowerCase() : "",
        timeout: Math.max(1, Math.min(20, Math.round(timeout)))
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
        + '<span class="ap-kv-group ap-live-state-starting"><span class="ap-kv-group-key">Chain N/A</span><span class="ap-kv-group-val">' + esc(String(data.chain_unverified || 0)) + "</span></span>"
        + '<span class="ap-kv-group ap-live-state-starting"><span class="ap-kv-group-key">Expiring</span><span class="ap-kv-group-val">' + esc(String(data.expiring_14d || 0)) + "</span></span>"
        + '<span class="ap-kv-group ap-live-state-unhealthy"><span class="ap-kv-group-key">Expired</span><span class="ap-kv-group-val">' + esc(String(data.expired || 0)) + "</span></span>";
    }

    function yesNoBadge(ok, checked) {
      if (checked === false) {
        return '<span class="ap-badge ap-live-state-starting">N/A</span>';
      }
      return ok
        ? '<span class="ap-badge ap-live-state-running">Yes</span>'
        : '<span class="ap-badge ap-live-state-unhealthy">No</span>';
    }

    function renderRows(payload) {
      var items = Array.isArray(payload && payload.items) ? payload.items : [];
      if (items.length === 0) {
        rowsEl.innerHTML = '<tr><td colspan="10" class="text-center ap-page-sub py-4">No TLS hosts found for current filters.</td></tr>';
        return;
      }

      items.sort(function (a, b) {
        var ad = String(a && a.domain || "");
        var bd = String(b && b.domain || "");
        return ad.localeCompare(bd);
      });

      rowsEl.innerHTML = items.map(function (item) {
        var domain = String(item && item.domain || "-");
        var state = String(item && item.state || "warn");
        var mtls = String(item && item.mtls_mode || "-");
        var daysLeft = Number(item && item.days_left != null ? item.days_left : -1);
        var sanMatch = !!(item && item.san_match);
        var chainOk = !!(item && item.chain_ok);
        var chainChecked = !(item && item.chain_checked === false);
        var noClient = String(item && item.http_no_client || "-");
        var withClient = String(item && item.http_with_client || "-");
        var verifyCode = String(item && item.verify_code || "-");
        var note = String(item && item.note || "-");
        var daysText = isFinite(daysLeft) && daysLeft > -9999 ? String(daysLeft) : "-";
        return ""
          + "<tr>"
          + "  <td>" + esc(domain) + "</td>"
          + '  <td class="text-end"><span class="ap-badge ' + esc(toneClass(state)) + '">' + esc(state) + "</span></td>"
          + '  <td class="text-end"><span class="ap-badge ap-live-state-info">' + esc(mtls) + "</span></td>"
          + '  <td class="text-end">' + esc(daysText) + "</td>"
          + '  <td class="text-end">' + yesNoBadge(sanMatch, true) + "</td>"
          + '  <td class="text-end">' + yesNoBadge(chainOk, chainChecked) + "</td>"
          + '  <td class="text-end">' + esc(noClient) + "</td>"
          + '  <td class="text-end">' + esc(withClient) + "</td>"
          + "  <td>" + esc(verifyCode) + "</td>"
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
          renderRows(payload);
          lastGeneratedAt = String(payload.generated_at || "");
          activeProject = String(payload.project || "-");
          activeTarget = String(payload && payload.filters && payload.filters.target || "-");
          if (metaEl) {
            metaEl.textContent = "Project: " + activeProject + " | Hosts: " + String((payload.summary && payload.summary.hosts) || 0) + " | Target: " + activeTarget;
          }
        })
        .catch(function (err) {
          renderSummary({});
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
