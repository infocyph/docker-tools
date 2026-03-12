(function () {
  "use strict";

  var doc = document;
  var root = doc.documentElement;
  var body = doc.body;

  var sidebarToggle = doc.getElementById("apSidebarToggle");
  var sidebarDesktopToggle = doc.getElementById("apSidebarDesktopToggle");
  var sidebarDesktopToggleTop = doc.getElementById("apSidebarDesktopToggleTop");
  var overlay = doc.getElementById("apOverlay");

  var themeBtn = doc.getElementById("apThemeBtn");
  var themeIcon = doc.getElementById("apThemeIcon");
  var themeItems = doc.querySelectorAll(".ap-theme-item");

  var THEME_KEY = "ap_theme_mode";
  var SIDEBAR_KEY = "ap_sidebar_collapsed";
  var LIVE_SECTIONS_KEY = "ap_live_sections_collapsed";
  var LIVE_COMPACT_KEY = "ap_live_compact";
  var LIVE_STATS_SERIES_KEY = "ap_live_stats_series";
  var desktopMql = window.matchMedia("(min-width: 992px)");

  var basePath = (body && body.getAttribute("data-ap-base")) || "";
  if (basePath === "/") {
    basePath = "";
  }
  var liveStatsApiUrl = basePath + "/api/live-stats";

  var livePayload = null;
  var liveTimer = null;
  var charts = [];
  var liveMatrixDetailMap = {};

  function cssVar(name, fallback) {
    var value = getComputedStyle(root).getPropertyValue(name).trim();
    return value || fallback;
  }

  function prefersDark() {
    return !!(window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)").matches);
  }

  function resolveTheme(mode) {
    if (mode === "dark" || mode === "light") {
      return mode;
    }
    return prefersDark() ? "dark" : "light";
  }

  function clearCharts() {
    charts.forEach(function (ch) {
      if (ch && typeof ch.destroy === "function") {
        ch.destroy();
      }
    });
    charts = [];
  }

  function getIn(obj, path, fallback) {
    var current = obj;
    for (var i = 0; i < path.length; i++) {
      if (!current || typeof current !== "object" || !(path[i] in current)) {
        return fallback;
      }
      current = current[path[i]];
    }
    return current;
  }

  function asArray(value) {
    return Array.isArray(value) ? value : [];
  }

  function numberFmt(value) {
    var n = Number(value);
    if (!isFinite(n)) {
      return "-";
    }
    try {
      return new Intl.NumberFormat().format(n);
    } catch (e) {
      return String(n);
    }
  }

  function percentToNumber(value) {
    if (typeof value === "number" && isFinite(value)) {
      return value;
    }
    var text = String(value || "");
    var match = text.match(/-?\d+(\.\d+)?/);
    if (!match) {
      return 0;
    }
    var parsed = Number(match[0]);
    return isFinite(parsed) ? parsed : 0;
  }

  function sizeToMiB(value) {
    if (typeof value === "number" && isFinite(value)) {
      return Math.max(0, value);
    }

    var text = String(value || "").trim();
    if (!text) {
      return 0;
    }

    var match = text.match(/^([0-9]*\.?[0-9]+)\s*([kmgt]?i?b)?$/i);
    if (!match) {
      return 0;
    }

    var amount = Number(match[1]);
    if (!isFinite(amount)) {
      return 0;
    }

    var unit = String(match[2] || "mib").toLowerCase();
    if (unit === "b") {
      return amount / (1024 * 1024);
    }
    if (unit === "kb" || unit === "kib") {
      return amount / 1024;
    }
    if (unit === "mb" || unit === "mib") {
      return amount;
    }
    if (unit === "gb" || unit === "gib") {
      return amount * 1024;
    }
    if (unit === "tb" || unit === "tib") {
      return amount * 1024 * 1024;
    }
    return amount;
  }

  function ioPairToMiB(value) {
    var text = String(value || "").trim();
    if (!text) {
      return 0;
    }

    var parts = text.split("/");
    var total = 0;
    for (var i = 0; i < parts.length; i++) {
      total += sizeToMiB(String(parts[i] || "").trim());
    }
    return total;
  }

  function escapeHtml(value) {
    return String(value)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#039;");
  }

  function setText(id, value) {
    var el = doc.getElementById(id);
    if (!el) {
      return;
    }
    el.textContent = value;
  }

  function setHidden(id, hidden) {
    var el = doc.getElementById(id);
    if (!el) {
      return;
    }
    el.classList.toggle("d-none", !!hidden);
  }

  function renderCheckCountCapsules(id, summary) {
    var el = doc.getElementById(id);
    if (!el) {
      return;
    }

    var pass = Number(summary && summary.pass != null ? summary.pass : 0);
    var warn = Number(summary && summary.warn != null ? summary.warn : 0);
    var fail = Number(summary && summary.fail != null ? summary.fail : 0);

    pass = isFinite(pass) ? pass : 0;
    warn = isFinite(warn) ? warn : 0;
    fail = isFinite(fail) ? fail : 0;
    var total = pass + warn + fail;
    var chips = [];

    if (total > 0) {
      if (pass > 0) {
        chips.push('<span class="ap-badge ap-live-state-running">Pass ' + escapeHtml(numberFmt(pass)) + "</span>");
      }
      if (warn > 0) {
        chips.push('<span class="ap-badge ap-live-state-starting">Warn ' + escapeHtml(numberFmt(warn)) + "</span>");
      }
      if (fail > 0) {
        chips.push('<span class="ap-badge ap-live-state-unhealthy">Fail ' + escapeHtml(numberFmt(fail)) + "</span>");
      }
    }

    el.innerHTML = chips.join("");
    el.classList.toggle("d-none", total <= 0);
  }

  function setLiveError(message) {
    var box = doc.getElementById("apLiveError");
    if (!box) {
      return;
    }
    if (!message) {
      box.textContent = "";
      box.classList.add("d-none");
      return;
    }
    box.textContent = message;
    box.classList.remove("d-none");
  }

  function setLiveLoading(isLoading) {
    var btn = doc.getElementById("apLiveRefreshBtn");
    if (!btn) {
      return;
    }
    btn.disabled = !!isLoading;
    var icon = btn.querySelector("i");
    if (icon) {
      icon.className = isLoading ? "bi bi-arrow-repeat ap-spin me-1" : "bi bi-arrow-repeat me-1";
    }
  }

  function updateLiveStickyOffsets() {
    var topbarInner = doc.querySelector(".ap-topbar-inner");
    var topbar = doc.querySelector(".ap-topbar");
    var kpiRow = doc.getElementById("apLiveStatsPage");

    var topbarHeight = 66;
    if (topbarInner && topbarInner.getBoundingClientRect) {
      topbarHeight = Math.max(40, Math.round(topbarInner.getBoundingClientRect().height));
    } else if (topbar && topbar.getBoundingClientRect) {
      topbarHeight = Math.max(40, Math.round(topbar.getBoundingClientRect().height));
    }

    var kpiHeight = 0;
    if (kpiRow && kpiRow.getBoundingClientRect) {
      kpiHeight = Math.max(0, Math.round(kpiRow.getBoundingClientRect().height));
    }

    var kpiTop = topbarHeight + 8;
    var tableTop = kpiTop + kpiHeight + 8;

    root.style.setProperty("--ap-topbar-height", String(topbarHeight) + "px");
    root.style.setProperty("--ap-kpi-sticky-top", String(kpiTop) + "px");
    root.style.setProperty("--ap-table-sticky-top", String(tableTop) + "px");
  }

  function readJsonStorage(key, fallback) {
    try {
      var raw = localStorage.getItem(key);
      if (!raw) {
        return fallback;
      }
      var parsed = JSON.parse(raw);
      return parsed && typeof parsed === "object" ? parsed : fallback;
    } catch (e) {
      return fallback;
    }
  }

  function writeJsonStorage(key, value) {
    try {
      localStorage.setItem(key, JSON.stringify(value));
    } catch (e) {
      // ignore storage errors
    }
  }

  function getCollapsedSectionsMap() {
    return readJsonStorage(LIVE_SECTIONS_KEY, {});
  }

  function setCollapsedSectionsMap(map) {
    writeJsonStorage(LIVE_SECTIONS_KEY, map || {});
  }

  function getActiveChipValue(containerId, attrName, fallback) {
    var scope = doc.getElementById(containerId);
    if (!scope) {
      return String(fallback || "");
    }
    var active = scope.querySelector(".ap-chip-btn.is-active[" + attrName + "]");
    if (!active) {
      return String(fallback || "");
    }
    return String(active.getAttribute(attrName) || fallback || "");
  }

  function setActiveChip(containerId, attrName, value) {
    var scope = doc.getElementById(containerId);
    if (!scope) {
      return;
    }
    var chips = Array.prototype.slice.call(scope.querySelectorAll(".ap-chip-btn[" + attrName + "]"));
    var next = String(value || "");
    chips.forEach(function (chip) {
      var isActive = String(chip.getAttribute(attrName) || "") === next;
      chip.classList.toggle("is-active", isActive);
      chip.setAttribute("aria-pressed", isActive ? "true" : "false");
    });
  }

  function defaultStatsSeriesPrefs() {
    return {
      cpu: true,
      memory: true,
      network: false,
      block: false
    };
  }

  function getStatsSeriesPrefs() {
    var defaults = defaultStatsSeriesPrefs();
    var stored = readJsonStorage(LIVE_STATS_SERIES_KEY, defaults);
    return {
      cpu: stored.cpu !== false,
      memory: stored.memory !== false,
      network: !!stored.network,
      block: !!stored.block
    };
  }

  function setStatsSeriesPrefs(prefs) {
    writeJsonStorage(LIVE_STATS_SERIES_KEY, {
      cpu: !!prefs.cpu,
      memory: !!prefs.memory,
      network: !!prefs.network,
      block: !!prefs.block
    });
  }

  function updateStatsSeriesButtons(prefs) {
    var scope = doc.getElementById("apLiveStatsSeriesControls");
    if (!scope) {
      return;
    }
    var map = prefs || getStatsSeriesPrefs();
    Array.prototype.slice.call(scope.querySelectorAll(".ap-chip-btn[data-series]")).forEach(function (btn) {
      var key = String(btn.getAttribute("data-series") || "");
      var isActive = !!map[key];
      btn.classList.toggle("is-active", isActive);
      btn.setAttribute("aria-pressed", isActive ? "true" : "false");
    });
  }

  function getCollapseButtonsByTarget(targetId) {
    return Array.prototype.slice.call(doc.querySelectorAll('.ap-card-collapse-toggle[data-target="' + targetId + '"]'));
  }

  function setCollapseButtonState(btn, isCollapsed) {
    if (!btn) {
      return;
    }
    btn.setAttribute("aria-expanded", isCollapsed ? "false" : "true");
    btn.setAttribute("title", isCollapsed ? "Expand section" : "Collapse section");
    var icon = btn.querySelector("i");
    if (icon) {
      icon.className = "bi " + (isCollapsed ? "bi-chevron-down" : "bi-chevron-up");
    }
  }

  function setSectionCollapsed(targetId, isCollapsed, persist) {
    var bodyEl = doc.getElementById(targetId);
    if (!bodyEl) {
      return;
    }
    bodyEl.classList.toggle("ap-collapsed", !!isCollapsed);
    getCollapseButtonsByTarget(targetId).forEach(function (btn) {
      setCollapseButtonState(btn, !!isCollapsed);
    });

    if (persist !== false) {
      var map = getCollapsedSectionsMap();
      map[targetId] = !!isCollapsed;
      setCollapsedSectionsMap(map);
    }
  }

  function initSectionCollapseControls() {
    var buttons = Array.prototype.slice.call(doc.querySelectorAll(".ap-card-collapse-toggle[data-target]"));
    if (!buttons.length) {
      return;
    }

    var stored = getCollapsedSectionsMap();
    var seenTargets = {};

    buttons.forEach(function (btn) {
      var targetId = String(btn.getAttribute("data-target") || "").trim();
      if (!targetId) {
        return;
      }

      if (!(targetId in seenTargets)) {
        seenTargets[targetId] = true;
        setSectionCollapsed(targetId, !!stored[targetId], false);
      } else {
        setCollapseButtonState(btn, !!stored[targetId]);
      }

      btn.addEventListener("click", function () {
        var target = doc.getElementById(targetId);
        if (!target) {
          return;
        }
        var collapsed = !target.classList.contains("ap-collapsed");
        setSectionCollapsed(targetId, collapsed, true);
      });
    });

    var collapseAllBtn = doc.getElementById("apLiveCollapseAllBtn");
    if (collapseAllBtn) {
      collapseAllBtn.addEventListener("click", function () {
        Object.keys(seenTargets).forEach(function (targetId) {
          setSectionCollapsed(targetId, true, false);
        });
        var nextMap = {};
        Object.keys(seenTargets).forEach(function (targetId) {
          nextMap[targetId] = true;
        });
        setCollapsedSectionsMap(nextMap);
      });
    }

    var expandAllBtn = doc.getElementById("apLiveExpandAllBtn");
    if (expandAllBtn) {
      expandAllBtn.addEventListener("click", function () {
        Object.keys(seenTargets).forEach(function (targetId) {
          setSectionCollapsed(targetId, false, false);
        });
        setCollapsedSectionsMap({});
      });
    }
  }

  function applyCompactMode(enabled, persist) {
    var isEnabled = !!enabled;
    body.classList.toggle("ap-live-compact", isEnabled);
    var btn = doc.getElementById("apLiveCompactToggleBtn");
    if (btn) {
      btn.setAttribute("aria-pressed", isEnabled ? "true" : "false");
      var iconCls = isEnabled ? "bi-layout-text-sidebar" : "bi-layout-text-sidebar-reverse";
      var label = isEnabled ? "Spacious" : "Compact";
      btn.innerHTML = '<i class="bi ' + iconCls + ' me-1"></i> ' + label;
    }
    if (persist !== false) {
      try {
        localStorage.setItem(LIVE_COMPACT_KEY, isEnabled ? "1" : "0");
      } catch (e) {
        // ignore storage errors
      }
    }
    updateLiveStickyOffsets();
  }

  function initCompactToggle() {
    var btn = doc.getElementById("apLiveCompactToggleBtn");
    if (!btn) {
      return;
    }
    var enabled = true;
    try {
      var saved = localStorage.getItem(LIVE_COMPACT_KEY);
      enabled = saved === null ? true : saved === "1";
    } catch (e) {
      enabled = true;
    }
    applyCompactMode(enabled, false);

    btn.addEventListener("click", function () {
      applyCompactMode(!body.classList.contains("ap-live-compact"), true);
    });
  }

  function toTitleWords(value) {
    return String(value || "")
      .split(/[_\s-]+/)
      .filter(function (part) { return part !== ""; })
      .map(function (part) {
        return part.charAt(0).toUpperCase() + part.slice(1).toLowerCase();
      })
      .join(" ");
  }

  function stateIconMeta(state) {
    var s = String(state || "").toLowerCase();
    if (s === "running") {
      return { icon: "bi-play-circle-fill", label: "Running", tone: "ap-live-health-healthy", spin: false };
    }
    if (s === "restarting") {
      return { icon: "bi-arrow-repeat", label: "Restarting", tone: "ap-live-health-degraded", spin: true };
    }
    if (s === "starting" || s === "created") {
      return { icon: "bi-hourglass-split", label: toTitleWords(s || "starting"), tone: "ap-live-health-degraded", spin: false };
    }
    if (s === "paused") {
      return { icon: "bi-pause-circle-fill", label: "Paused", tone: "ap-live-health-degraded", spin: false };
    }
    if (s === "exited" || s === "dead" || s === "stopped") {
      return { icon: "bi-x-octagon-fill", label: toTitleWords(s), tone: "ap-live-health-failing", spin: false };
    }
    return { icon: "bi-question-circle-fill", label: toTitleWords(s || "unknown"), tone: "ap-live-health-degraded", spin: false };
  }

  function checkStateClass(state) {
    var s = String(state || "").toLowerCase();
    if (s === "pass") {
      return "ap-live-state-running";
    }
    if (s === "warn") {
      return "ap-live-state-starting";
    }
    if (s === "fail") {
      return "ap-live-state-unhealthy";
    }
    return "ap-live-state-no-health";
  }

  function checkStateMeta(state) {
    var s = String(state || "").toLowerCase();
    if (s === "pass") {
      return { icon: "bi-check-circle-fill", label: "Pass", tone: "ap-live-health-healthy", spin: false };
    }
    if (s === "warn") {
      return { icon: "bi-exclamation-triangle-fill", label: "Warn", tone: "ap-live-health-degraded", spin: false };
    }
    if (s === "fail") {
      return { icon: "bi-x-octagon-fill", label: "Fail", tone: "ap-live-health-failing", spin: false };
    }
    return { icon: "bi-question-circle-fill", label: "Unknown", tone: "ap-live-health-degraded", spin: false };
  }

  function renderCheckStateIcon(state, extraClass) {
    var meta = checkStateMeta(state);
    var cls = String(extraClass || "ap-check-state-icon");
    var spinCls = meta.spin ? " ap-state-icon-spin" : "";
    return ""
      + '<span class="' + cls + " " + meta.tone + spinCls + '"'
      + ' title="state: ' + escapeHtml(meta.label) + '"'
      + ' aria-label="state: ' + escapeHtml(meta.label) + '">'
      + '  <i class="bi ' + meta.icon + '"></i>'
      + "</span>";
  }

  function setTitleStateIcon(id, state) {
    var el = doc.getElementById(id);
    if (!el) {
      return;
    }
    el.innerHTML = renderCheckStateIcon(state, "ap-title-state-icon");
  }

  function parsePortGroups(raw) {
    var exposed = [];
    var mapped = [];
    var seenExposed = {};
    var seenMapped = {};
    var parts = String(raw || "")
      .split(",")
      .map(function (part) { return String(part || "").trim(); })
      .filter(function (part) { return part !== "" && part !== "-"; });

    parts.forEach(function (part) {
      if (part.indexOf("->") !== -1) {
        var idx = part.indexOf("->");
        var left = String(part.slice(0, idx) || "").trim();
        var right = String(part.slice(idx + 2) || "").trim();
        if (right && !seenExposed[right]) {
          seenExposed[right] = true;
          exposed.push(right);
        }
        var hostMatch = left.match(/:(\d+)$/);
        var hostPort = hostMatch ? hostMatch[1] : left;
        var mapLabel = hostPort && right ? (hostPort + "->" + right) : part;
        if (mapLabel && !seenMapped[mapLabel]) {
          seenMapped[mapLabel] = true;
          mapped.push(mapLabel);
        }
        return;
      }

      if (!seenExposed[part]) {
        seenExposed[part] = true;
        exposed.push(part);
      }
    });

    return {
      exposed: exposed,
      mapped: mapped
    };
  }

  function renderPortBadges(values, badgeClass) {
    var list = asArray(values).filter(function (v) { return String(v || "").trim() !== ""; });
    if (!list.length) {
      return "";
    }
    return list.map(function (value) {
      return '<span class="' + badgeClass + '">' + escapeHtml(String(value)) + "</span>";
    }).join("");
  }

  function parseMemUsageToMiB(value) {
    var text = String(value || "").trim();
    if (!text) {
      return 0;
    }
    var firstPart = text.split("/")[0];
    return sizeToMiB(String(firstPart || "").trim());
  }

  function stateBucket(state, health) {
    var s = String(state || "").toLowerCase();
    var h = String(health || "").toLowerCase();

    if (h === "unhealthy" || s === "exited" || s === "dead" || s === "stopped") {
      return "fail";
    }
    if (h === "healthy" && s === "running") {
      return "pass";
    }
    return "warn";
  }

  function readMatrixControls() {
    var search = doc.getElementById("apLiveMatrixSearch");
    var sort = doc.getElementById("apLiveMatrixSort");

    return {
      query: String(search && search.value ? search.value : "").trim().toLowerCase(),
      state: getActiveChipValue("apLiveMatrixStateFilter", "data-runtime-state", "all").toLowerCase(),
      sort: String(sort && sort.value ? sort.value : "cpu_desc").toLowerCase()
    };
  }

  function readChecksControls() {
    var search = doc.getElementById("apLiveChecksSearch");
    return {
      query: String(search && search.value ? search.value : "").trim().toLowerCase(),
      state: getActiveChipValue("apLiveChecksFilter", "data-check-state", "all").toLowerCase()
    };
  }

  function parseMountFlagTokens(flag) {
    var raw = String(flag || "").trim();
    if (!raw || raw === "-") {
      return [];
    }

    return raw
      .split(/[,\s|]+/)
      .map(function (token) { return String(token || "").trim(); })
      .filter(function (token) { return token !== ""; })
      .map(function (token) {
        var idx = token.indexOf("=");
        if (idx > 0) {
          return {
            type: "kv",
            key: token.slice(0, idx),
            value: token.slice(idx + 1)
          };
        }
        return {
          type: "word",
          value: token
        };
      });
  }

  function mountFlagWordBadgeClass(word) {
    var w = String(word || "").toLowerCase();
    if (w === "present") {
      return "ap-live-state-running";
    }
    if (w === "missing") {
      return "ap-live-state-unhealthy";
    }
    if (w === "empty") {
      return "ap-live-state-starting";
    }
    return "ap-live-state-no-health";
  }

  function renderMountFlagChips(flag) {
    var tokens = parseMountFlagTokens(flag);
    if (!tokens.length) {
      return '<span class="ap-port-empty">-</span>';
    }

    return '<div class="ap-flag-chips">' + tokens.map(function (token) {
      if (token.type === "kv") {
        return ""
          + '<span class="ap-badge ap-flag-chip ap-flag-chip-kv">'
          + '  <span class="ap-flag-chip-key">' + escapeHtml(token.key || "-") + "</span>"
          + '  <span class="ap-flag-chip-sep">=</span>'
          + '  <span class="ap-flag-chip-val">' + escapeHtml(token.value || "-") + "</span>"
          + "</span>";
      }
      return '<span class="ap-badge ap-flag-chip ' + mountFlagWordBadgeClass(token.value) + '">' + escapeHtml(token.value || "-") + "</span>";
    }).join("") + "</div>";
  }

  function renderSystemDetailChip(label, value, badgeClass) {
    var cls = String(badgeClass || "ap-system-detail-chip");
    var safeValue = escapeHtml(String(value || "-"));
    if (!label) {
      return '<span class="ap-badge ' + cls + '">' + safeValue + "</span>";
    }
    return ""
      + '<span class="ap-badge ' + cls + '">'
      + '  <span class="ap-system-detail-chip-label">' + escapeHtml(String(label)) + "</span>"
      + '  <span class="ap-system-detail-chip-sep">=</span>'
      + '  <span class="ap-system-detail-chip-val">' + safeValue + "</span>"
      + "</span>";
  }

  function renderSystemDetailText(text) {
    var t = String(text || "").trim();
    if (!t) {
      return "";
    }
    return '<span class="ap-system-detail-text">' + escapeHtml(t) + "</span>";
  }

  function parseDetailKeyValues(detail) {
    var text = String(detail || "");
    var tokenRe = /([a-zA-Z0-9_]+)=([^\s]+)/g;
    var pairs = [];
    var match;
    while ((match = tokenRe.exec(text)) !== null) {
      pairs.push({
        key: match[1],
        value: match[2]
      });
    }
    return pairs;
  }

  function renderSystemBoolChip(label, value) {
    if (typeof value !== "boolean") {
      return renderSystemDetailChip(label, "-", "ap-live-state-no-health");
    }
    return renderSystemDetailChip(label, value ? "yes" : "no", value ? "ap-live-state-running" : "ap-live-state-unhealthy");
  }

  function renderSystemTestDetail(key, test) {
    var k = String(key || "");
    var chips = [];
    var detailText = "";

    if (k === "internet") {
      detailText = String(test.detail || test.value || "").trim();
      if (detailText) {
        chips.push(renderSystemDetailChip("", detailText, detailText.toLowerCase() === "reachable" ? "ap-live-state-running" : "ap-live-state-starting"));
        detailText = "";
      }
    } else if (k === "egress_ip") {
      detailText = String(test.value || test.detail || "").trim();
      if (detailText) {
        chips.push(renderSystemDetailChip("ip", detailText, "ap-system-detail-chip"));
        detailText = "";
      }
    } else if (k === "memory") {
      var totalMiB = Number(test.total_mib);
      var availableMiB = Number(test.available_mib);
      var availablePct = Number(test.available_percent);

      if (isFinite(totalMiB)) {
        chips.push(renderSystemDetailChip("total", numberFmt(totalMiB) + "MiB", "ap-system-detail-chip"));
      }
      if (isFinite(availableMiB)) {
        chips.push(renderSystemDetailChip("available", numberFmt(availableMiB) + "MiB", "ap-system-detail-chip"));
      }
      if (isFinite(availablePct)) {
        var pctClass = availablePct >= 40 ? "ap-live-state-running" : (availablePct >= 20 ? "ap-live-state-starting" : "ap-live-state-unhealthy");
        chips.push(renderSystemDetailChip("free", numberFmt(availablePct) + "%", pctClass));
      }
      detailText = "";
    } else if (k === "docker") {
      chips.push(renderSystemBoolChip("cli", test.has_cli));
      chips.push(renderSystemBoolChip("compose", test.has_compose));
      chips.push(renderSystemBoolChip("daemon", test.daemon_reachable));
      detailText = "";
    } else {
      detailText = String(test.detail || test.value || "").trim();
      var pairs = parseDetailKeyValues(detailText);
      if (pairs.length) {
        chips = pairs.map(function (pair) {
          return renderSystemDetailChip(pair.key, pair.value, "ap-system-detail-chip");
        });
        detailText = detailText.replace(/([a-zA-Z0-9_]+)=([^\s]+)/g, "").trim();
      }
    }

    if (!chips.length && !detailText) {
      return '<span class="ap-port-empty">-</span>';
    }

    return '<div class="ap-system-test-detail">' + chips.join("") + renderSystemDetailText(detailText) + "</div>";
  }

  function normalizeCheckState(state) {
    var s = String(state || "").toLowerCase();
    if (s === "pass" || s === "warn" || s === "fail") {
      return s;
    }
    return "unknown";
  }

  function checkStateSeverity(state) {
    var s = normalizeCheckState(state);
    if (s === "fail") {
      return 3;
    }
    if (s === "warn") {
      return 2;
    }
    if (s === "unknown") {
      return 1;
    }
    return 0;
  }

  function formatCheckLabel(key) {
    var raw = String(key || "").trim();
    if (!raw) {
      return "-";
    }

    var map = {
      internet: "Internet",
      egress_ip: "Egress IP",
      memory: "Memory",
      docker: "Docker",
      build_cache_reclaimable: "Build Cache Reclaimable",
      builder_prune_hint: "Builder Prune Hint",
      orphan_containers: "Orphan Containers",
      labeled_volumes: "Labeled Volumes",
      unused_labeled_volumes: "Unused Labeled Volumes"
    };
    if (raw in map) {
      return map[raw];
    }

    return raw
      .split("_")
      .map(function (part) {
        var p = String(part || "");
        return p ? (p.charAt(0).toUpperCase() + p.slice(1)) : "";
      })
      .join(" ");
  }

  function isSafeHttpUrl(url) {
    return /^https?:\/\//i.test(String(url || "").trim());
  }

  function worstCheckState(states) {
    var list = asArray(states);
    var worst = "unknown";
    var worstScore = -1;
    list.forEach(function (state) {
      var normalized = normalizeCheckState(state);
      var score = checkStateSeverity(normalized);
      if (score > worstScore) {
        worstScore = score;
        worst = normalized;
      }
    });
    return worstScore >= 0 ? worst : "unknown";
  }

  function parseSizeToBytes(value) {
    var text = String(value || "").trim();
    var match = text.match(/^([0-9]+(?:\.[0-9]+)?)\s*([kmgtp]?i?b)$/i);
    if (!match) {
      return NaN;
    }
    var amount = Number(match[1]);
    var unit = String(match[2] || "").toLowerCase();
    if (!isFinite(amount)) {
      return NaN;
    }
    var factors = {
      b: 1,
      kb: 1000,
      mb: 1000 * 1000,
      gb: 1000 * 1000 * 1000,
      tb: 1000 * 1000 * 1000 * 1000,
      pb: 1000 * 1000 * 1000 * 1000 * 1000,
      kib: 1024,
      mib: 1024 * 1024,
      gib: 1024 * 1024 * 1024,
      tib: 1024 * 1024 * 1024 * 1024,
      pib: 1024 * 1024 * 1024 * 1024 * 1024
    };
    return factors[unit] ? amount * factors[unit] : NaN;
  }

  function renderSystemValueChips(values, badgeClass, emptyClass) {
    var items = asArray(values)
      .map(function (value) { return String(value || "").trim(); })
      .filter(function (value) { return value !== ""; });

    if (!items.length) {
      return '<div class="ap-system-test-detail">' + renderSystemDetailChip("", "none", String(emptyClass || "ap-live-state-running")) + "</div>";
    }

    return '<div class="ap-system-test-detail">' + items.map(function (value) {
      return '<span class="ap-badge ' + badgeClass + '">' + escapeHtml(value) + "</span>";
    }).join("") + "</div>";
  }

  function renderDriftRows(payload) {
    var drift = getIn(payload, ["sections", "drift"], {});
    if (!drift || typeof drift !== "object" || Array.isArray(drift) || !Object.keys(drift).length) {
      return [];
    }

    var rows = [];

    var reclaimable = String(drift.build_cache_reclaimable || "-").trim() || "-";
    var reclaimBytes = parseSizeToBytes(reclaimable);
    var hasReclaimable = reclaimable !== "-";
    var reclaimWarn = hasReclaimable && ((!isFinite(reclaimBytes) && reclaimable !== "0") || (isFinite(reclaimBytes) && reclaimBytes > 0));
    var reclaimState = hasReclaimable ? (reclaimWarn ? "warn" : "pass") : "unknown";
    rows.push({
      key: "build_cache_reclaimable",
      state: reclaimState,
      detail: '<div class="ap-system-test-detail">' + renderSystemDetailChip("", reclaimable, reclaimWarn ? "ap-live-state-starting" : "ap-live-state-running") + "</div>",
      detailText: reclaimable
    });

    var pruneKnown = typeof drift.builder_prune_hint === "boolean";
    var pruneHint = pruneKnown ? !!drift.builder_prune_hint : null;
    rows.push({
      key: "builder_prune_hint",
      state: pruneKnown ? (pruneHint ? "warn" : "pass") : "unknown",
      detail: '<div class="ap-system-test-detail">' + (
        pruneKnown
          ? renderSystemDetailChip("", pruneHint ? "true" : "false", pruneHint ? "ap-live-state-starting" : "ap-live-state-running")
          : renderSystemDetailChip("", "-", "ap-live-state-no-health")
      ) + "</div>",
      detailText: pruneKnown ? (pruneHint ? "true" : "false") : "-"
    });

    var orphans = asArray(drift.orphan_containers || []);
    rows.push({
      key: "orphan_containers",
      state: orphans.length ? "warn" : "pass",
      detail: renderSystemValueChips(orphans, orphans.length ? "ap-live-state-unhealthy" : "ap-live-state-running", "ap-live-state-running"),
      detailText: orphans.length ? orphans.join(" ") : "none"
    });

    var labeled = asArray(drift.labeled_volumes || []);
    rows.push({
      key: "labeled_volumes",
      state: "pass",
      detail: renderSystemValueChips(labeled, "ap-live-state-no-health", "ap-live-state-no-health"),
      detailText: labeled.join(" ")
    });

    var unused = asArray(drift.unused_labeled_volumes || []);
    rows.push({
      key: "unused_labeled_volumes",
      state: unused.length ? "warn" : "pass",
      detail: renderSystemValueChips(unused, unused.length ? "ap-live-state-starting" : "ap-live-state-running", "ap-live-state-running"),
      detailText: unused.length ? unused.join(" ") : "none"
    });

    return rows;
  }

  function renderSystemTestsTable(payload) {
    var rowsEl = doc.getElementById("apLiveSystemTestsRows");
    if (!rowsEl) {
      return;
    }

    var tests = getIn(payload, ["sections", "checks", "system", "tests"], {});
    var keys = Object.keys(tests || {});
    var driftRows = renderDriftRows(payload);
    if (!keys.length && !driftRows.length) {
      setTitleStateIcon("apLiveSystemTestsStateIcon", "");
      rowsEl.innerHTML = '<tr><td colspan="3" class="text-center ap-page-sub py-4">No system tests.</td></tr>';
      return;
    }

    var systemState = normalizeCheckState(getIn(payload, ["sections", "checks", "system", "state"], ""));
    var driftStates = driftRows.map(function (row) { return row.state; });
    setTitleStateIcon("apLiveSystemTestsStateIcon", worstCheckState([systemState].concat(driftStates)));

    var controls = readChecksControls();
    var combinedRows = keys.map(function (key) {
      var test = tests[key] || {};
      return {
        key: key,
        label: formatCheckLabel(key),
        state: normalizeCheckState(test.state),
        detail: renderSystemTestDetail(key, test),
        detailText: String(test.detail || test.value || "")
      };
    });

    driftRows.forEach(function (row) {
      combinedRows.push({
        key: row.key,
        label: formatCheckLabel(row.key),
        state: normalizeCheckState(row.state),
        detail: row.detail,
        detailText: String(row.detailText || "")
      });
    });

    var filteredRows = combinedRows.filter(function (row) {
      if (controls.state !== "all" && row.state !== controls.state) {
        return false;
      }
      if (!controls.query) {
        return true;
      }
      var haystack = (String(row.label || "") + " " + String(row.detailText || "")).toLowerCase();
      return haystack.indexOf(controls.query) !== -1;
    });

    if (!filteredRows.length) {
      rowsEl.innerHTML = '<tr><td colspan="3" class="text-center ap-page-sub py-4">No tests matching current filters.</td></tr>';
      return;
    }

    rowsEl.innerHTML = filteredRows.map(function (row) {
      return ""
        + "<tr>"
        + '  <td><span class="ap-system-test-name">' + escapeHtml(row.label) + "</span></td>"
        + '  <td class="text-end">' + renderCheckStateIcon(row.state, "ap-check-state-icon") + "</td>"
        + "  <td>" + row.detail + "</td>"
        + "</tr>";
    }).join("");
  }

  function renderProjectContainersCheck(payload) {
    var listEl = doc.getElementById("apLiveProjectContainersList");
    if (!listEl) {
      return;
    }

    var check = getIn(payload, ["sections", "checks", "project", "tests", "containers"], {});
    if (!check || typeof check !== "object" || Array.isArray(check) || !Object.keys(check).length) {
      setTitleStateIcon("apLiveProjectContainersStateIcon", "");
      listEl.innerHTML = '<li class="ap-live-item-muted">No project containers check data.</li>';
      return;
    }

    setTitleStateIcon("apLiveProjectContainersStateIcon", check.state);

    var counts = check.counts || {};
    listEl.innerHTML = [
      '<li class="ap-live-item"><span>Total</span><span class="ap-live-item-value">' + numberFmt(counts.total || 0) + "</span></li>",
      '<li class="ap-live-item"><span>Running</span><span class="ap-live-item-value">' + numberFmt(counts.running || 0) + "</span></li>",
      '<li class="ap-live-item"><span>Healthy</span><span class="ap-live-item-value">' + numberFmt(counts.healthy || 0) + "</span></li>",
      '<li class="ap-live-item"><span>No Health</span><span class="ap-live-item-value">' + numberFmt(counts.no_health || 0) + "</span></li>",
      '<li class="ap-live-item"><span>Starting</span><span class="ap-live-item-value">' + numberFmt(counts.starting || 0) + "</span></li>",
      '<li class="ap-live-item"><span>Unhealthy</span><span class="ap-live-item-value">' + numberFmt(counts.unhealthy || 0) + "</span></li>",
      '<li class="ap-live-item"><span>Restarting</span><span class="ap-live-item-value">' + numberFmt(counts.restarting || 0) + "</span></li>",
      '<li class="ap-live-item"><span>Exited</span><span class="ap-live-item-value">' + numberFmt(counts.exited || 0) + "</span></li>",
      '<li class="ap-live-item"><span>Other</span><span class="ap-live-item-value">' + numberFmt(counts.other || 0) + "</span></li>"
    ].join("");
  }

  function renderProjectArtifactsCheck(payload) {
    var listEl = doc.getElementById("apLiveProjectArtifactsList");
    if (!listEl) {
      return;
    }

    var check = getIn(payload, ["sections", "checks", "project", "tests", "artifacts"], {});
    if (!check || typeof check !== "object" || Array.isArray(check) || !Object.keys(check).length) {
      setTitleStateIcon("apLiveProjectArtifactsStateIcon", "");
      listEl.innerHTML = '<li class="ap-live-item-muted">No project artifacts check data.</li>';
      return;
    }

    setTitleStateIcon("apLiveProjectArtifactsStateIcon", check.state);

    var counts = check.counts || {};
    var missing = asArray(check.missing_dirs || []);

    var items = [
      '<li class="ap-live-item"><span>Nginx conf</span><span class="ap-live-item-value">' + numberFmt(counts.nginx_conf || 0) + "</span></li>",
      '<li class="ap-live-item"><span>Apache conf</span><span class="ap-live-item-value">' + numberFmt(counts.apache_conf || 0) + "</span></li>",
      '<li class="ap-live-item"><span>Node yaml</span><span class="ap-live-item-value">' + numberFmt(counts.node_yaml || 0) + "</span></li>",
      '<li class="ap-live-item"><span>FPM conf</span><span class="ap-live-item-value">' + numberFmt(counts.fpm_conf || 0) + "</span></li>",
      '<li class="ap-live-item"><span>Cert files</span><span class="ap-live-item-value">' + numberFmt(counts.cert_files || 0) + "</span></li>",
      '<li class="ap-live-item"><span>RootCA files</span><span class="ap-live-item-value">' + numberFmt(counts.rootca_files || 0) + "</span></li>",
      '<li class="ap-live-item"><span>Logs total</span><span class="ap-live-item-value">' + numberFmt(counts.logs_total || 0) + "</span></li>",
      '<li class="ap-live-item"><span>Logs plain</span><span class="ap-live-item-value">' + numberFmt(counts.logs_plain || 0) + "</span></li>",
      '<li class="ap-live-item"><span>Logs gz</span><span class="ap-live-item-value">' + numberFmt(counts.logs_gz || 0) + "</span></li>"
    ];
    if (missing.length) {
      items.push('<li class="ap-live-item-muted">Missing dirs: ' + escapeHtml(missing.join(", ")) + "</li>");
    }

    listEl.innerHTML = items.join("");
  }

  function renderProjectMountsCheck(payload) {
    var listEl = doc.getElementById("apLiveProjectMountList");
    if (!listEl) {
      return;
    }

    var check = getIn(payload, ["sections", "checks", "project", "tests", "mounts"], {});
    var items = asArray(check.items || []);
    setTitleStateIcon("apLiveProjectMountsStateIcon", check && check.state ? check.state : "");
    if (!items.length) {
      listEl.innerHTML = '<li class="ap-live-item-muted">No project mounts check data.</li>';
      return;
    }

    listEl.innerHTML = items.map(function (item) {
      var flag = String(item && item.flag ? item.flag : "").trim();
      var entriesMatch = flag.match(/entries\s*=\s*(\d+)/i);
      var value = "";

      if (entriesMatch) {
        value = numberFmt(entriesMatch[1]);
      } else if (flag && flag !== "-") {
        value = flag;
      } else if (typeof item.entry_count === "number" && isFinite(item.entry_count)) {
        value = numberFmt(item.entry_count);
      }

      return '<li class="ap-live-item"><span>' + escapeHtml(item.key || "-") + '</span><span class="ap-live-item-value">' + escapeHtml(value) + "</span></li>";
    }).join("");
  }

  function buildLogViewerUrl(service, containerName) {
    var svc = String(service || "").trim();
    var name = String(containerName || "").trim();
    var filter = svc || name;
    if (!filter) {
      return "";
    }
    return basePath + "/logs?svc=" + encodeURIComponent(filter);
  }

  function showContainerDetails(detailKey) {
    var key = String(detailKey || "").trim();
    if (!key || !(key in liveMatrixDetailMap)) {
      return;
    }
    var detail = liveMatrixDetailMap[key];
    var titleEl = doc.getElementById("apLiveContainerDetailsTitle");
    var gridEl = doc.getElementById("apLiveContainerDetailsGrid");
    if (!gridEl) {
      return;
    }

    if (titleEl) {
      titleEl.textContent = String(detail.container || "Container Details");
    }

    var rows = [
      { key: "Container", value: detail.container || "-" },
      { key: "Service", value: detail.service || "-" },
      { key: "State", value: detail.state || "-" },
      { key: "Health", value: detail.health || "-" },
      { key: "CPU %", value: detail.cpu || "-" },
      { key: "Memory", value: detail.memory || "-" },
      { key: "Exposed Ports", value: detail.exposedPorts || "none" },
      { key: "Access Ports", value: detail.accessPorts || "none" },
      { key: "Networks", value: detail.networks || "none" }
    ];

    gridEl.innerHTML = rows.map(function (row) {
      return ""
        + "<dt>" + escapeHtml(row.key) + "</dt>"
        + "<dd>" + escapeHtml(row.value) + "</dd>";
    }).join("");

    var modalEl = doc.getElementById("apLiveContainerDetailsModal");
    if (!modalEl || !window.bootstrap || typeof window.bootstrap.Modal !== "function") {
      return;
    }

    var modal = window.bootstrap.Modal.getOrCreateInstance(modalEl);
    modal.show();
  }

  function renderNetworkMatrix(payload) {
    var headEl = doc.getElementById("apLiveNetworkMatrixHead");
    var rowsEl = doc.getElementById("apLiveNetworkMatrixRows");
    if (!headEl || !rowsEl) {
      return;
    }

    var containers = asArray(getIn(payload, ["sections", "containers", "core", "items"], []));
    var columns = asArray(getIn(payload, ["sections", "networks", "matrix", "columns"], []));
    var rows = asArray(getIn(payload, ["sections", "networks", "matrix", "rows"], []));
    var networks = asArray(getIn(payload, ["sections", "networks", "networks"], []));
    var topConsumers = asArray(getIn(payload, ["sections", "containers", "top_consumers", "all"], []));
    var portRows = asArray(getIn(payload, ["core", "ports_by_container"], []));
    var networkByName = {};
    var containerByName = {};
    var matrixByName = {};
    var topByName = {};
    var portsByName = {};

    networks.forEach(function (network) {
      var key = String(network && network.name ? network.name : "").toLowerCase();
      if (key !== "") {
        networkByName[key] = network;
      }
    });

    containers.forEach(function (container) {
      var key = String(container && container.name ? container.name : "").toUpperCase();
      if (key !== "") {
        containerByName[key] = container;
      }
    });

    rows.forEach(function (row) {
      var key = String(row && row.name ? row.name : "").toUpperCase();
      if (key !== "") {
        matrixByName[key] = row;
      }
    });

    topConsumers.forEach(function (row) {
      var key = String(row && row.name ? row.name : "").toUpperCase();
      if (key !== "") {
        topByName[key] = row;
      }
    });

    portRows.forEach(function (row) {
      var key = String(row && row.name ? row.name : "").toUpperCase();
      if (key !== "") {
        portsByName[key] = parsePortGroups(row && row.ports ? row.ports : "");
      }
    });

    var names = [];
    Object.keys(containerByName).forEach(function (key) {
      names.push(key);
    });
    Object.keys(matrixByName).forEach(function (key) {
      if (names.indexOf(key) === -1) {
        names.push(key);
      }
    });
    Object.keys(topByName).forEach(function (key) {
      if (names.indexOf(key) === -1) {
        names.push(key);
      }
    });
    Object.keys(portsByName).forEach(function (key) {
      if (names.indexOf(key) === -1) {
        names.push(key);
      }
    });

    var controls = readMatrixControls();
    var matrixColumns = columns.length ? columns.slice() : ["Networks"];
    var networkHeaderCells = matrixColumns.map(function (col) {
      if (!columns.length) {
        return '<th class="text-end">Networks</th>';
      }

      var key = String(col || "").toLowerCase();
      var meta = key in networkByName ? networkByName[key] : {};
      var containersCount = meta && meta.containers != null ? numberFmt(meta.containers) : "-";
      var subnet = meta && meta.subnet ? String(meta.subnet) : "-";
      var title = String(col || "-") + " (" + containersCount + ")";

      return ""
        + '<th class="text-end ap-matrix-col">'
        + '<span class="ap-matrix-main">' + escapeHtml(title) + "</span>"
        + '<span class="ap-matrix-sub">' + escapeHtml(subnet) + "</span>"
        + "</th>";
    }).join("");

    headEl.innerHTML = "<tr><th>Container / Service</th><th>State</th><th>Ports</th><th class=\"text-end\">CPU %</th><th class=\"text-end\">Mem Usage</th>" + networkHeaderCells + "</tr>";

    if (!names.length) {
      liveMatrixDetailMap = {};
      rowsEl.innerHTML = '<tr><td colspan="' + String(5 + matrixColumns.length) + '" class="text-center ap-page-sub py-4">No container, consumer, or matrix data.</td></tr>';
      return;
    }

    var rowsData = names.map(function (name) {
      var container = containerByName[name] || {};
      var matrixRow = matrixByName[name] || {};
      var topConsumer = topByName[name] || {};
      var ips = matrixRow && typeof matrixRow === "object" && matrixRow.ips ? matrixRow.ips : {};
      var containerName = String(container.name || matrixRow.name || topConsumer.name || name || "-");
      var service = String(container.service || "-");
      var state = String(container.state || "-");
      var health = String(container.health || "-");
      var healthIcon = String(container.health_icon || "!");
      var cpuPercent = String(topConsumer.cpu_percent || "-");
      var cpuValue = percentToNumber(cpuPercent);
      var memUsage = String(topConsumer.mem_usage || "-");
      var memMiB = parseMemUsageToMiB(memUsage);
      var portGroups = portsByName[name] || { exposed: [], mapped: [] };

      return {
        name: name,
        containerName: containerName,
        service: service,
        state: state,
        health: health,
        healthIcon: healthIcon,
        cpuPercent: cpuPercent,
        cpuValue: cpuValue,
        memUsage: memUsage,
        memMiB: memMiB,
        portGroups: portGroups,
        ips: ips,
        bucket: stateBucket(state, health)
      };
    }).filter(function (row) {
      var matchesState = controls.state === "all" || row.bucket === controls.state;
      if (!matchesState) {
        return false;
      }
      if (!controls.query) {
        return true;
      }
      var searchable = (row.containerName + " " + row.service + " " + row.name).toLowerCase();
      return searchable.indexOf(controls.query) !== -1;
    });

    if (controls.sort === "mem_desc") {
      rowsData.sort(function (a, b) {
        if (b.memMiB !== a.memMiB) {
          return b.memMiB - a.memMiB;
        }
        return String(a.containerName).localeCompare(String(b.containerName));
      });
    } else if (controls.sort === "name_asc") {
      rowsData.sort(function (a, b) {
        return String(a.containerName).localeCompare(String(b.containerName));
      });
    } else {
      rowsData.sort(function (a, b) {
        if (b.cpuValue !== a.cpuValue) {
          return b.cpuValue - a.cpuValue;
        }
        return String(a.containerName).localeCompare(String(b.containerName));
      });
    }

    if (!rowsData.length) {
      liveMatrixDetailMap = {};
      rowsEl.innerHTML = '<tr><td colspan="' + String(5 + matrixColumns.length) + '" class="text-center ap-page-sub py-4">No rows matching current filters.</td></tr>';
      return;
    }

    var detailsMap = {};
    rowsEl.innerHTML = rowsData.map(function (row, index) {
      var state = row.state;
      var health = row.health;
      var healthIcon = row.healthIcon;
      var cells = matrixColumns.map(function (col) {
        var value = columns.length && row.ips && typeof row.ips === "object" && (col in row.ips) ? row.ips[col] : null;
        return '<td class="text-end">' + escapeHtml(value || "-") + "</td>";
      }).join("");

      var stateMeta = stateIconMeta(state);
      var stateSpin = stateMeta.spin ? " ap-state-icon-spin" : "";
      var stateCell = ""
        + '<span class="ap-state-icon ' + stateMeta.tone + stateSpin + '"'
        + ' title="state: ' + escapeHtml(stateMeta.label) + '"'
        + ' aria-label="state: ' + escapeHtml(stateMeta.label) + '">'
        + '<i class="bi ' + stateMeta.icon + '"></i>'
        + "</span>";
      var healthClass = health === "healthy"
        ? "ap-live-health-healthy"
        : (health === "unhealthy" ? "ap-live-health-failing" : "ap-live-health-degraded");
      var healthPulse = health === "healthy" ? "" : " ap-health-icon-pulse";
      var healthLabel = toTitleWords(health || "unknown");
      var healthCell = '<span class="ap-health-icon ' + healthClass + healthPulse + '"'
        + ' title="health: ' + escapeHtml(healthLabel) + '"'
        + ' aria-label="health: ' + escapeHtml(healthLabel) + '">'
        + escapeHtml(healthIcon || "!")
        + "</span>";
      var detailKey = "row_" + String(index) + "_" + String(row.name || "");
      var networksText = matrixColumns.map(function (col) {
        var value = columns.length && row.ips && typeof row.ips === "object" && (col in row.ips) ? row.ips[col] : "";
        if (!value || value === "-") {
          return "";
        }
        return String(col) + ":" + String(value);
      }).filter(function (part) { return part !== ""; }).join(", ");
      detailsMap[detailKey] = {
        container: row.containerName,
        service: row.service,
        state: toTitleWords(state || "unknown"),
        health: healthLabel,
        cpu: row.cpuPercent,
        memory: row.memUsage,
        exposedPorts: asArray(row.portGroups.exposed || []).join(", "),
        accessPorts: asArray(row.portGroups.mapped || []).join(", "),
        networks: networksText
      };
      var logsUrl = buildLogViewerUrl(row.service, row.containerName);
      var actions = ""
        + '<div class="ap-matrix-actions">'
        + (logsUrl
          ? '<a class="ap-matrix-action-btn" href="' + escapeHtml(logsUrl) + '" title="Inspect logs" aria-label="Inspect logs"><i class="bi bi-journal-text"></i></a>'
          : "")
        + '<button class="btn ap-matrix-action-btn ap-matrix-details-btn" type="button" data-detail-key="' + escapeHtml(detailKey) + '" title="Open container details" aria-label="Open container details"><i class="bi bi-info-circle"></i></button>'
        + "</div>";
      var identityCell = ""
        + '<div class="ap-matrix-identity">'
        + '  <span class="ap-matrix-name">' + escapeHtml(row.containerName) + "</span>"
        + '  <span class="ap-matrix-service">' + escapeHtml(row.service) + "</span>"
        + "  " + actions
        + "</div>";
      var stateCellMerged = ""
        + '<div class="ap-matrix-state">'
        + "  <span>" + stateCell + "</span>"
        + "  <span>" + healthCell + "</span>"
        + "</div>";
      var exposedPortsHtml = renderPortBadges(row.portGroups.exposed, "ap-port-badge ap-port-badge-exposed");
      var mappedPortsHtml = renderPortBadges(row.portGroups.mapped, "ap-port-badge ap-port-badge-mapped");
      var portRowsHtml = "";
      if (exposedPortsHtml) {
        portRowsHtml += '<div class="ap-matrix-port-row"><span class="ap-matrix-port-values">' + exposedPortsHtml + "</span></div>";
      }
      if (mappedPortsHtml) {
        portRowsHtml += '<div class="ap-matrix-port-row"><span class="ap-matrix-port-values">' + mappedPortsHtml + "</span></div>";
      }
      var portsCell = portRowsHtml ? ('<div class="ap-matrix-ports">' + portRowsHtml + "</div>") : "";

      return ""
        + "<tr>"
        + "  <td>" + identityCell + "</td>"
        + "  <td>" + stateCellMerged + "</td>"
        + "  <td>" + portsCell + "</td>"
        + '  <td class="text-end">' + escapeHtml(row.cpuPercent) + "</td>"
        + '  <td class="text-end">' + escapeHtml(row.memUsage) + "</td>"
        + cells
        + "</tr>";
    }).join("");
    liveMatrixDetailMap = detailsMap;
  }

  function normalizeIssueText(item) {
    if (typeof item === "string") {
      return item;
    }
    if (item && typeof item === "object") {
      if (item.message) {
        return String(item.message);
      }
      if (item.detail) {
        return String(item.detail);
      }
      if (item.error) {
        return String(item.error);
      }
      if (item.url && item.status_code) {
        return String(item.url) + " (status " + String(item.status_code) + ")";
      }
      return JSON.stringify(item);
    }
    return String(item);
  }

  function renderUrlProbeTable(payload) {
    var rowsEl = doc.getElementById("apLiveUrlProbeRows");
    if (!rowsEl) {
      return;
    }

    var urls = asArray(getIn(payload, ["core", "urls"], []))
      .map(function (url) { return String(url || "").trim(); })
      .filter(function (url) { return url !== ""; });
    var probes = asArray(getIn(payload, ["sections", "probes", "items"], []));
    var probeByUrl = {};
    var orderedUrls = [];
    var seen = {};

    urls.forEach(function (url) {
      var key = url.toLowerCase();
      if (!seen[key]) {
        seen[key] = true;
        orderedUrls.push(url);
      }
    });

    probes.forEach(function (probe) {
      var url = String(probe && probe.url ? probe.url : "").trim();
      if (!url) {
        return;
      }
      var key = url.toLowerCase();
      if (!(key in probeByUrl)) {
        probeByUrl[key] = probe;
      }
      if (!seen[key]) {
        seen[key] = true;
        orderedUrls.push(url);
      }
    });

    if (!orderedUrls.length) {
      rowsEl.innerHTML = '<tr><td colspan="3" class="text-center ap-page-sub py-4">No URL/probe data.</td></tr>';
      return;
    }

    rowsEl.innerHTML = orderedUrls.map(function (url) {
      var probe = probeByUrl[url.toLowerCase()] || {};
      var statusRaw = String(probe.status_code || probe.status || "").trim();
      var timeRaw = String(probe.time_seconds || probe.time || "").trim();
      var statusText = statusRaw || "-";
      var timeText = timeRaw || "-";
      var statusNum = Number(statusRaw);
      var statusClass = "ap-live-state-no-health";
      var visitHtml = isSafeHttpUrl(url)
        ? ('<a class="ap-url-visit" href="' + escapeHtml(url) + '" target="_blank" rel="noopener noreferrer" title="Visit URL" aria-label="Visit URL"><i class="bi bi-box-arrow-up-right"></i></a>')
        : "";

      if (isFinite(statusNum)) {
        if (statusNum >= 200 && statusNum < 400) {
          statusClass = "ap-live-state-running";
        } else if (statusNum >= 400) {
          statusClass = "ap-live-state-unhealthy";
        } else {
          statusClass = "ap-live-state-starting";
        }
      } else if (statusRaw === "-") {
        statusClass = "ap-live-state-no-health";
      }

      return ""
        + "<tr>"
        + '  <td><span class="ap-url-cell">' + escapeHtml(url) + visitHtml + "</span></td>"
        + '  <td class="text-end"><span class="ap-badge ' + statusClass + '">' + escapeHtml(statusText) + "</span></td>"
        + '  <td class="text-end">' + escapeHtml(timeText) + "</td>"
        + "</tr>";
    }).join("");
  }

  function renderIssueFeed(payload) {
    var listEl = doc.getElementById("apLiveIssueFeed");
    if (!listEl) {
      return;
    }

    var problemRows = asArray(getIn(payload, ["sections", "problems", "items"], []));
    var recentRows = asArray(getIn(payload, ["sections", "recent_errors", "items"], []));
    var items = [];

    problemRows.forEach(function (row) {
      items.push({
        type: "Problem",
        tone: "ap-live-state-unhealthy",
        text: normalizeIssueText(row)
      });
    });

    recentRows.forEach(function (row) {
      items.push({
        type: "Recent",
        tone: "ap-live-state-starting",
        text: normalizeIssueText(row)
      });
    });

    if (!items.length) {
      listEl.innerHTML = '<li class="ap-live-item-muted">No problems or recent errors.</li>';
      return;
    }

    listEl.innerHTML = items.slice(0, 20).map(function (item) {
      return '<li class="ap-live-item"><span>' + escapeHtml(item.text || "-") + '</span><span class="ap-badge ' + item.tone + '">' + escapeHtml(item.type) + "</span></li>";
    }).join("");
  }

  function renderSummary(payload, summary, generatedAt) {
    var checks = getIn(payload, ["sections", "checks"], {});
    var systemChecks = getIn(checks, ["system", "summary"], summary.system_checks || {});
    var projectChecks = getIn(checks, ["project", "summary"], summary.project_checks || {});

    setText("apLiveRunning", numberFmt(summary.running) + " / " + numberFmt(summary.total));
    setText("apLiveHealth", numberFmt(summary.healthy) + " / " + numberFmt(summary.unhealthy) + " / " + numberFmt(summary.no_health));
    setText("apLiveUrls", numberFmt(summary.url_count));
    setText("apLivePorts", numberFmt(summary.port_count));
    setText("apLiveProblems", numberFmt(summary.problem_count));
    var systemTotalChecks = Number(systemChecks.pass || 0) + Number(systemChecks.warn || 0) + Number(systemChecks.fail || 0);
    var projectTotalChecks = Number(projectChecks.pass || 0) + Number(projectChecks.warn || 0) + Number(projectChecks.fail || 0);
    var systemHasNonZeroChip = Number(systemChecks.pass || 0) > 0 || Number(systemChecks.warn || 0) > 0 || Number(systemChecks.fail || 0) > 0;
    var projectHasNonZeroChip = Number(projectChecks.pass || 0) > 0 || Number(projectChecks.warn || 0) > 0 || Number(projectChecks.fail || 0) > 0;
    setHidden("apLiveSystemChecks", systemHasNonZeroChip);
    setHidden("apLiveProjectChecks", projectHasNonZeroChip);
    if (systemHasNonZeroChip) {
      setText("apLiveSystemChecks", "");
    } else {
      setText("apLiveSystemChecks", numberFmt(systemTotalChecks));
    }
    if (projectHasNonZeroChip) {
      setText("apLiveProjectChecks", "");
    } else {
      setText("apLiveProjectChecks", numberFmt(projectTotalChecks));
    }
    renderCheckCountCapsules("apLiveSystemChecksCaps", systemChecks);
    renderCheckCountCapsules("apLiveProjectChecksCaps", projectChecks);
    setText("apLiveUpdatedAt", generatedAt ? "Updated: " + generatedAt : "Updated: -");

    renderUrlProbeTable(payload);
    renderIssueFeed(payload);
  }

  function renderCharts() {
    if (typeof window.Chart === "undefined") {
      return;
    }

    clearCharts();

    var mutedColor = cssVar("--ap-muted", "#6b7280");
    var textColor = cssVar("--ap-text", "#111827");
    var borderColor = cssVar("--ap-border", "#e5e9f2");
    var primary = cssVar("--ap-primary", "#465fff");
    var success = cssVar("--ap-success", "#16a34a");
    var warn = cssVar("--ap-warning", "#d97706");
    var danger = cssVar("--ap-danger", "#dc2626");
    var accentPalette = [primary, success, warn, danger, "#06b6d4", "#84cc16", "#f97316", "#14b8a6"];

    var revenueEl = doc.getElementById("apRevenueChart");
    if (revenueEl) {
      charts.push(new window.Chart(revenueEl, {
        type: "line",
        data: {
          labels: ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"],
          datasets: [
            {
              label: "Revenue",
              data: [42, 46, 48, 51, 55, 58, 60, 64, 66, 70, 73, 87],
              borderColor: primary,
              backgroundColor: "rgba(70,95,255,0.12)",
              fill: true,
              tension: 0.34,
              pointRadius: 0,
              borderWidth: 2.5
            },
            {
              label: "Projects",
              data: [68, 72, 74, 78, 84, 89, 95, 98, 104, 110, 119, 126],
              borderColor: success,
              fill: false,
              tension: 0.34,
              pointRadius: 0,
              borderWidth: 2.2
            }
          ]
        },
        options: {
          maintainAspectRatio: false,
          plugins: {
            legend: {
              position: "top",
              align: "end",
              labels: {
                color: mutedColor,
                boxWidth: 10,
                usePointStyle: true,
                font: { size: 11, weight: "600" }
              }
            }
          },
          scales: {
            x: {
              grid: { display: false },
              ticks: { color: mutedColor, font: { size: 11 } }
            },
            y: {
              border: { display: false },
              grid: { color: borderColor },
              ticks: { color: mutedColor, font: { size: 11 } }
            }
          }
        }
      }));
    }

    var trafficEl = doc.getElementById("apTrafficChart");
    if (trafficEl) {
      charts.push(new window.Chart(trafficEl, {
        type: "bar",
        data: {
          labels: ["Proxy", "Direct", "CLI", "Scheduled"],
          datasets: [{
            data: [46, 28, 17, 9],
            backgroundColor: [primary, success, warn, danger],
            borderRadius: 8,
            barThickness: 20
          }]
        },
        options: {
          plugins: {
            legend: { display: false }
          },
          scales: {
            x: {
              grid: { display: false },
              ticks: { color: mutedColor, font: { size: 11 } }
            },
            y: {
              border: { display: false },
              grid: { color: borderColor },
              ticks: { color: mutedColor, font: { size: 11 } }
            }
          }
        }
      }));
    }

    var orderEl = doc.getElementById("apOrderStatusChart");
    if (orderEl) {
      charts.push(new window.Chart(orderEl, {
        type: "bar",
        data: {
          labels: ["Completed", "Processing", "Failed"],
          datasets: [{
            data: [64, 21, 8],
            backgroundColor: [success, warn, danger],
            borderRadius: 8,
            barThickness: 26
          }]
        },
        options: {
          maintainAspectRatio: false,
          plugins: {
            legend: { display: false }
          },
          scales: {
            x: {
              grid: { display: false },
              ticks: { color: mutedColor, font: { size: 11 } }
            },
            y: {
              border: { display: false },
              grid: { color: borderColor },
              ticks: { color: mutedColor, font: { size: 11 }, stepSize: 20 }
            }
          }
        }
      }));
    }

    var liveStatsEl = doc.getElementById("apLiveStatsChart");
    if (liveStatsEl) {
      var statsRows = asArray(getIn(livePayload, ["sections", "containers", "stats", "items"], []))
        .map(function (row) {
          var memText = row.mem_usage || String(row.mem_raw || "").split("/")[0].trim();
          return {
            name: row.name || "-",
            cpu: row.cpu_value != null ? Number(row.cpu_value) : percentToNumber(row.cpu_percent),
            memMiB: sizeToMiB(memText),
            netMiB: ioPairToMiB(row.net_io),
            blockMiB: ioPairToMiB(row.block_io)
          };
        })
        .filter(function (row) { return isFinite(row.cpu); })
        .sort(function (a, b) { return b.cpu - a.cpu; })
        .slice(0, 8);

      var statsLabels = statsRows.map(function (row) { return row.name; });
      var statsCpuRaw = statsRows.map(function (row) { return Math.max(0, row.cpu); });
      var statsMemRaw = statsRows.map(function (row) { return Math.max(0, row.memMiB); });
      var statsNetRaw = statsRows.map(function (row) { return Math.max(0, row.netMiB); });
      var statsBlockRaw = statsRows.map(function (row) { return Math.max(0, row.blockMiB); });

      var cpuMax = Math.max.apply(null, statsCpuRaw.concat([1]));
      var memMax = Math.max.apply(null, statsMemRaw.concat([1]));
      var netMax = Math.max.apply(null, statsNetRaw.concat([1]));
      var blockMax = Math.max.apply(null, statsBlockRaw.concat([1]));

      var statsCpuValues = statsCpuRaw.map(function (value) { return (value / cpuMax) * 100; });
      var statsMemValues = statsMemRaw.map(function (value) { return (value / memMax) * 100; });
      var statsNetValues = statsNetRaw.map(function (value) { return (value / netMax) * 100; });
      var statsBlockValues = statsBlockRaw.map(function (value) { return (value / blockMax) * 100; });
      if (!statsLabels.length) {
        statsLabels = ["No data"];
        statsCpuValues = [0];
        statsMemValues = [0];
        statsNetValues = [0];
        statsBlockValues = [0];
        statsCpuRaw = [0];
        statsMemRaw = [0];
        statsNetRaw = [0];
        statsBlockRaw = [0];
      }

      var statsPrefs = getStatsSeriesPrefs();
      updateStatsSeriesButtons(statsPrefs);
      var statsDatasets = [];
      if (statsPrefs.cpu) {
        statsDatasets.push({
          label: "CPU %",
          data: statsCpuValues,
          rawValues: statsCpuRaw,
          rawUnit: "%",
          backgroundColor: primary,
          borderRadius: 6,
          barThickness: 10
        });
      }
      if (statsPrefs.memory) {
        statsDatasets.push({
          label: "Memory (MiB)",
          data: statsMemValues,
          rawValues: statsMemRaw,
          rawUnit: "MiB",
          backgroundColor: success,
          borderRadius: 6,
          barThickness: 10
        });
      }
      if (statsPrefs.network) {
        statsDatasets.push({
          label: "Net I/O (MiB)",
          data: statsNetValues,
          rawValues: statsNetRaw,
          rawUnit: "MiB",
          backgroundColor: warn,
          borderRadius: 6,
          barThickness: 10
        });
      }
      if (statsPrefs.block) {
        statsDatasets.push({
          label: "Block I/O (MiB)",
          data: statsBlockValues,
          rawValues: statsBlockRaw,
          rawUnit: "MiB",
          backgroundColor: danger,
          borderRadius: 6,
          barThickness: 10
        });
      }
      if (!statsDatasets.length) {
        statsDatasets.push({
          label: "CPU %",
          data: statsCpuValues,
          rawValues: statsCpuRaw,
          rawUnit: "%",
          backgroundColor: primary,
          borderRadius: 6,
          barThickness: 10
        });
      }

      charts.push(new window.Chart(liveStatsEl, {
        type: "bar",
        data: {
          labels: statsLabels,
          datasets: statsDatasets
        },
        options: {
          maintainAspectRatio: false,
          interaction: {
            mode: "index",
            intersect: false
          },
          plugins: {
            legend: {
              position: "top",
              align: "start",
              labels: {
                color: textColor,
                boxWidth: 10,
                font: { size: 11, weight: "600" }
              }
            },
            tooltip: {
              callbacks: {
                label: function (context) {
                  var ds = context.dataset || {};
                  var index = context.dataIndex || 0;
                  var rawValues = ds.rawValues || [];
                  var raw = Number(rawValues[index] || 0);
                  var unit = String(ds.rawUnit || "");
                  var formatted = Math.round(raw * 100) / 100;
                  return String(ds.label || "") + ": " + formatted + (unit ? " " + unit : "");
                }
              }
            }
          },
          scales: {
            x: {
              grid: { display: false },
              ticks: { color: textColor, font: { size: 11 }, maxRotation: 25, minRotation: 0 }
            },
            y: {
              type: "linear",
              beginAtZero: true,
              max: 100,
              border: { display: false },
              grid: { color: borderColor },
              ticks: {
                color: textColor,
                font: { size: 11 },
                callback: function (value) {
                  return value + "%";
                }
              },
              title: {
                display: true,
                text: "Percent of max per metric",
                color: textColor,
                font: { size: 10, weight: "600" }
              }
            }
          }
        }
      }));
    }

    var liveDiskEl = doc.getElementById("apLiveDiskChart");
    if (liveDiskEl) {
      var diskRows = asArray(getIn(livePayload, ["sections", "disk", "items"], []))
        .map(function (row) {
          return {
            label: row.type || "-",
            gib: sizeToMiB(row.size) / 1024
          };
        })
        .filter(function (row) { return row.gib > 0; });

      var diskLabels = diskRows.map(function (row) { return row.label; });
      var diskValues = diskRows.map(function (row) { return Math.round(row.gib * 100) / 100; });
      if (!diskLabels.length) {
        diskLabels = ["No data"];
        diskValues = [1];
      }

      charts.push(new window.Chart(liveDiskEl, {
        type: "bar",
        data: {
          labels: diskLabels,
          datasets: [{
            label: "GiB",
            data: diskValues,
            backgroundColor: accentPalette.slice(0, diskLabels.length),
            borderRadius: 8,
            barThickness: 22
          }]
        },
        options: {
          indexAxis: "y",
          maintainAspectRatio: false,
          plugins: {
            legend: { display: false }
          },
          scales: {
            x: {
              border: { display: false },
              grid: { color: borderColor },
              ticks: { color: textColor, font: { size: 10 } }
            },
            y: {
              border: { display: false },
              grid: { display: false },
              ticks: { color: textColor, font: { size: 10 } }
            }
          }
        }
      }));
    }

    var liveVolumeEl = doc.getElementById("apLiveVolumeChart");
    if (liveVolumeEl) {
      var volumeRows = asArray(getIn(livePayload, ["sections", "volumes", "items"], []))
        .map(function (row) {
          return {
            label: row.name || "-",
            mib: sizeToMiB(row.size)
          };
        })
        .sort(function (a, b) { return b.mib - a.mib; })
        .slice(0, 8);

      var volumeLabels = volumeRows.map(function (row) { return row.label; });
      var volumeValues = volumeRows.map(function (row) { return Math.round(row.mib * 100) / 100; });
      if (!volumeLabels.length) {
        volumeLabels = ["No data"];
        volumeValues = [0];
      }

      charts.push(new window.Chart(liveVolumeEl, {
        type: "bar",
        data: {
          labels: volumeLabels,
          datasets: [{
            label: "Size MiB",
            data: volumeValues,
            backgroundColor: success,
            borderRadius: 8,
            barThickness: 14
          }]
        },
        options: {
          indexAxis: "y",
          maintainAspectRatio: false,
          plugins: {
            legend: { display: false }
          },
          scales: {
            x: {
              border: { display: false },
              grid: { color: borderColor },
              ticks: { color: textColor, font: { size: 10 } }
            },
            y: {
              border: { display: false },
              grid: { display: false },
              ticks: { color: textColor, font: { size: 10 } }
            }
          }
        }
      }));
    }
  }

  function updateThemeUI(mode) {
    var iconClass = "bi-circle-half";
    if (mode === "light") {
      iconClass = "bi-sun-fill";
    } else if (mode === "dark") {
      iconClass = "bi-moon-stars-fill";
    }

    if (themeIcon) {
      themeIcon.className = "bi " + iconClass;
    }

    themeItems.forEach(function (item) {
      var isActive = item.getAttribute("data-theme-mode") === mode;
      item.classList.toggle("active", isActive);
      item.setAttribute("aria-current", isActive ? "true" : "false");
    });
  }

  function applyTheme(mode, persist) {
    var nextMode = mode === "light" || mode === "dark" ? mode : "auto";
    var resolved = resolveTheme(nextMode);
    root.setAttribute("data-bs-theme", resolved);
    updateThemeUI(nextMode);

    if (persist !== false) {
      try {
        localStorage.setItem(THEME_KEY, nextMode);
      } catch (e) {
        // ignore storage errors
      }
    }
  }

  function getThemeMode() {
    try {
      return localStorage.getItem(THEME_KEY) || "auto";
    } catch (e) {
      return "auto";
    }
  }

  function initTheme() {
    applyTheme(getThemeMode(), false);

    themeItems.forEach(function (item) {
      item.addEventListener("click", function () {
        var mode = item.getAttribute("data-theme-mode") || "auto";
        applyTheme(mode, true);
        renderCharts();
      });
    });

    if (window.matchMedia) {
      window.matchMedia("(prefers-color-scheme: dark)").addEventListener("change", function () {
        if (getThemeMode() === "auto") {
          applyTheme("auto", false);
          renderCharts();
        }
      });
    }

    if (themeBtn) {
      themeBtn.addEventListener("dblclick", function () {
        applyTheme("auto", true);
        renderCharts();
      });
    }
  }

  function openMobileSidebar() {
    body.classList.add("ap-sidebar-open");
  }

  function closeMobileSidebar() {
    body.classList.remove("ap-sidebar-open");
  }

  function toggleDesktopSidebar() {
    if (!desktopMql.matches) {
      return;
    }

    body.classList.toggle("ap-sidebar-collapsed");
    try {
      localStorage.setItem(SIDEBAR_KEY, body.classList.contains("ap-sidebar-collapsed") ? "1" : "0");
    } catch (e) {
      // ignore storage errors
    }
  }

  function setNavSubmenuState(toggleBtn, submenuEl, isOpen) {
    var expanded = !!isOpen;
    toggleBtn.setAttribute("aria-expanded", expanded ? "true" : "false");
    submenuEl.classList.toggle("is-open", expanded);
    var tree = toggleBtn.closest(".ap-nav-tree");
    if (tree) {
      tree.classList.toggle("is-open", expanded);
    }
  }

  function initNavSubmenus() {
    var toggles = Array.prototype.slice.call(doc.querySelectorAll(".ap-nav-link-toggle[data-nav-toggle]"));
    toggles.forEach(function (toggleBtn) {
      var targetId = toggleBtn.getAttribute("aria-controls");
      if (!targetId) {
        return;
      }

      var submenuEl = doc.getElementById(targetId);
      if (!submenuEl) {
        return;
      }

      var initiallyOpen = toggleBtn.getAttribute("aria-expanded") === "true" || submenuEl.classList.contains("is-open");
      setNavSubmenuState(toggleBtn, submenuEl, initiallyOpen);

      toggleBtn.addEventListener("click", function (ev) {
        ev.preventDefault();

        if (desktopMql.matches && body.classList.contains("ap-sidebar-collapsed")) {
          body.classList.remove("ap-sidebar-collapsed");
          try {
            localStorage.setItem(SIDEBAR_KEY, "0");
          } catch (e) {
            // ignore storage errors
          }
        }

        var nextOpen = toggleBtn.getAttribute("aria-expanded") !== "true";
        setNavSubmenuState(toggleBtn, submenuEl, nextOpen);
      });
    });
  }

  function initSidebar() {
    try {
      if (localStorage.getItem(SIDEBAR_KEY) === "1" && desktopMql.matches) {
        body.classList.add("ap-sidebar-collapsed");
      }
    } catch (e) {
      // ignore storage errors
    }

    if (sidebarToggle) {
      sidebarToggle.addEventListener("click", function () {
        if (body.classList.contains("ap-sidebar-open")) {
          closeMobileSidebar();
        } else {
          openMobileSidebar();
        }
      });
    }

    if (sidebarDesktopToggle) {
      sidebarDesktopToggle.addEventListener("click", toggleDesktopSidebar);
    }

    if (sidebarDesktopToggleTop) {
      sidebarDesktopToggleTop.addEventListener("click", toggleDesktopSidebar);
    }

    if (overlay) {
      overlay.addEventListener("click", closeMobileSidebar);
    }

    initNavSubmenus();

    doc.querySelectorAll(".ap-nav-link").forEach(function (link) {
      link.addEventListener("click", function () {
        if (link.hasAttribute("data-nav-toggle")) {
          return;
        }
        if (!desktopMql.matches) {
          closeMobileSidebar();
        }
      });
    });

    doc.addEventListener("keydown", function (ev) {
      if (ev.key === "Escape") {
        closeMobileSidebar();
      }
    });

    desktopMql.addEventListener("change", function (e) {
      if (e.matches) {
        closeMobileSidebar();
      } else {
        body.classList.remove("ap-sidebar-collapsed");
      }
    });
  }

  function applyLivePayload(payloadEnvelope) {
    var payload = getIn(payloadEnvelope, ["data"], {});
    var summary = getIn(payloadEnvelope, ["summary"], {});
    var generatedAt = String(payloadEnvelope.generated_at || "");

    livePayload = payload;

    renderSummary(payload, summary, generatedAt);
    renderNetworkMatrix(payload);
    renderSystemTestsTable(payload);
    renderProjectContainersCheck(payload);
    renderProjectArtifactsCheck(payload);
    renderProjectMountsCheck(payload);
    renderCharts();
    updateLiveStickyOffsets();
  }

  function fetchLiveStats() {
    if (!doc.getElementById("apLiveStatsPage") || typeof window.fetch !== "function") {
      return;
    }

    setLiveLoading(true);
    setLiveError("");

    window.fetch(liveStatsApiUrl + "?ajax=1&format=json", {
      headers: {
        "X-Requested-With": "XMLHttpRequest",
        "Accept": "application/json"
      }
    })
      .then(function (res) {
        if (!res.ok) {
          throw new Error("HTTP " + res.status);
        }
        return res.json();
      })
      .then(function (payload) {
        if (!payload || payload.ok !== true) {
          var message = payload && payload.message ? payload.message : "Unable to load live stats.";
          throw new Error(message);
        }
        applyLivePayload(payload);
      })
      .catch(function (err) {
        var message = err && err.message ? err.message : "Failed to load live stats.";
        setLiveError(message);
      })
      .finally(function () {
        setLiveLoading(false);
      });
  }

  function initRuntimeMatrixControls() {
    var search = doc.getElementById("apLiveMatrixSearch");
    var stateFilter = doc.getElementById("apLiveMatrixStateFilter");
    var sort = doc.getElementById("apLiveMatrixSort");
    setActiveChip("apLiveMatrixStateFilter", "data-runtime-state", getActiveChipValue("apLiveMatrixStateFilter", "data-runtime-state", "all"));

    function rerenderMatrix() {
      if (livePayload) {
        renderNetworkMatrix(livePayload);
      }
    }

    if (search) {
      search.addEventListener("input", rerenderMatrix);
    }
    if (stateFilter) {
      stateFilter.addEventListener("click", function (ev) {
        var btn = ev.target && ev.target.closest ? ev.target.closest(".ap-chip-btn[data-runtime-state]") : null;
        if (!btn) {
          return;
        }
        var value = String(btn.getAttribute("data-runtime-state") || "all");
        setActiveChip("apLiveMatrixStateFilter", "data-runtime-state", value);
        rerenderMatrix();
      });
    }
    if (sort) {
      sort.addEventListener("change", rerenderMatrix);
    }

    doc.addEventListener("click", function (ev) {
      var btn = ev.target && ev.target.closest ? ev.target.closest(".ap-matrix-details-btn[data-detail-key]") : null;
      if (!btn) {
        return;
      }
      showContainerDetails(btn.getAttribute("data-detail-key"));
    });
  }

  function initChecksControls() {
    var filter = doc.getElementById("apLiveChecksFilter");
    var search = doc.getElementById("apLiveChecksSearch");
    setActiveChip("apLiveChecksFilter", "data-check-state", getActiveChipValue("apLiveChecksFilter", "data-check-state", "all"));

    function rerenderChecks() {
      if (livePayload) {
        renderSystemTestsTable(livePayload);
      }
    }

    if (filter) {
      filter.addEventListener("click", function (ev) {
        var btn = ev.target && ev.target.closest ? ev.target.closest(".ap-chip-btn[data-check-state]") : null;
        if (!btn) {
          return;
        }
        var value = String(btn.getAttribute("data-check-state") || "all");
        setActiveChip("apLiveChecksFilter", "data-check-state", value);
        rerenderChecks();
      });
    }

    if (search) {
      search.addEventListener("input", rerenderChecks);
    }
  }

  function initStatsSeriesControls() {
    var scope = doc.getElementById("apLiveStatsSeriesControls");
    if (!scope) {
      return;
    }

    var prefs = getStatsSeriesPrefs();
    updateStatsSeriesButtons(prefs);

    scope.addEventListener("click", function (ev) {
      var btn = ev.target && ev.target.closest ? ev.target.closest(".ap-chip-btn[data-series]") : null;
      if (!btn) {
        return;
      }
      var key = String(btn.getAttribute("data-series") || "");
      if (!key) {
        return;
      }

      var next = getStatsSeriesPrefs();
      next[key] = !next[key];
      if (!next.cpu && !next.memory && !next.network && !next.block) {
        next.cpu = true;
      }
      setStatsSeriesPrefs(next);
      updateStatsSeriesButtons(next);
      renderCharts();
    });
  }

  function initLiveStats() {
    if (!doc.getElementById("apLiveStatsPage")) {
      return;
    }

    initSectionCollapseControls();
    initCompactToggle();
    initRuntimeMatrixControls();
    initChecksControls();
    initStatsSeriesControls();
    updateLiveStickyOffsets();
    window.addEventListener("resize", updateLiveStickyOffsets);

    var refreshBtn = doc.getElementById("apLiveRefreshBtn");
    if (refreshBtn) {
      refreshBtn.addEventListener("click", fetchLiveStats);
    }

    fetchLiveStats();

    if (liveTimer) {
      window.clearInterval(liveTimer);
    }
    liveTimer = window.setInterval(fetchLiveStats, 30000);
  }

  initTheme();
  initSidebar();
  initLiveStats();
  renderCharts();
})();
