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
  var desktopMql = window.matchMedia("(min-width: 992px)");

  var basePath = (body && body.getAttribute("data-ap-base")) || "";
  if (basePath === "/") {
    basePath = "";
  }
  var liveStatsApiUrl = basePath + "/api/live-stats";

  var livePayload = null;
  var liveTimer = null;
  var charts = [];

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

  function stateBadgeClass(state) {
    var s = String(state || "").toLowerCase();
    if (s === "running") {
      return "ap-live-state-running";
    }
    if (s === "exited" || s === "dead" || s === "stopped") {
      return "ap-live-state-exited";
    }
    if (s === "starting" || s === "created") {
      return "ap-live-state-starting";
    }
    return "ap-live-state-no-health";
  }

  function healthBadgeClass(health) {
    var h = String(health || "").toLowerCase();
    if (h === "healthy") {
      return "ap-live-state-running";
    }
    if (h === "unhealthy") {
      return "ap-live-state-unhealthy";
    }
    if (h === "-" || h === "") {
      return "ap-live-state-no-health";
    }
    return "ap-live-state-starting";
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

  function renderSimpleList(id, values, fallbackText) {
    var target = doc.getElementById(id);
    if (!target) {
      return;
    }
    var items = asArray(values);
    if (!items.length) {
      target.innerHTML = '<li class="ap-live-item-muted">' + escapeHtml(fallbackText || "No data") + "</li>";
      return;
    }
    target.innerHTML = items.map(function (value) {
      return '<li class="ap-live-item">' + escapeHtml(value) + "</li>";
    }).join("");
  }

  function renderChecks(payload, summary) {
    var checksSummaryEl = doc.getElementById("apLiveChecksSummary");
    var checksDetailsEl = doc.getElementById("apLiveChecksDetails");
    if (!checksSummaryEl || !checksDetailsEl) {
      return;
    }

    var systemSummary = summary.system_checks || {};
    var projectSummary = summary.project_checks || {};
    var buildCache = summary.build_cache_reclaimable || "-";
    var egressIp = summary.egress_ip || "-";

    checksSummaryEl.innerHTML = [
      '<li class="ap-live-item"><span>System checks</span><span class="ap-live-item-value">P ' + numberFmt(systemSummary.pass || 0) + ' / W ' + numberFmt(systemSummary.warn || 0) + ' / F ' + numberFmt(systemSummary.fail || 0) + "</span></li>",
      '<li class="ap-live-item"><span>Project checks</span><span class="ap-live-item-value">P ' + numberFmt(projectSummary.pass || 0) + ' / W ' + numberFmt(projectSummary.warn || 0) + ' / F ' + numberFmt(projectSummary.fail || 0) + "</span></li>",
      '<li class="ap-live-item"><span>Egress IP</span><span class="ap-live-item-value">' + escapeHtml(egressIp) + "</span></li>",
      '<li class="ap-live-item"><span>Build cache reclaimable</span><span class="ap-live-item-value">' + escapeHtml(buildCache) + "</span></li>"
    ].join("");

    var systemTests = getIn(payload, ["checks", "system", "tests"], {});
    var projectTests = getIn(payload, ["checks", "project", "tests"], {});
    var detailRows = [];
    Object.keys(systemTests || {}).forEach(function (key) {
      var test = systemTests[key] || {};
      var state = String(test.state || "unknown").toUpperCase();
      var detail = String(test.detail || test.value || "");
      detailRows.push(
        '<li class="ap-live-item"><span>' + escapeHtml(key) + "</span><span class=\"ap-badge " + checkStateClass(test.state) + '">' + escapeHtml(state) + "</span></li>"
        + (detail ? '<li class="ap-live-item-muted">' + escapeHtml(detail) + "</li>" : "")
      );
    });
    Object.keys(projectTests || {}).forEach(function (key) {
      var test = projectTests[key] || {};
      var state = String(test.state || "unknown").toUpperCase();
      var detail = String(test.detail || "");
      detailRows.push(
        '<li class="ap-live-item"><span>project.' + escapeHtml(key) + "</span><span class=\"ap-badge " + checkStateClass(test.state) + '">' + escapeHtml(state) + "</span></li>"
        + (detail ? '<li class="ap-live-item-muted">' + escapeHtml(detail) + "</li>" : "")
      );
    });

    checksDetailsEl.innerHTML = detailRows.length
      ? detailRows.join("")
      : '<li class="ap-live-item-muted">No check details.</li>';
  }

  function renderSystemTestsTable(payload) {
    var rowsEl = doc.getElementById("apLiveSystemTestsRows");
    if (!rowsEl) {
      return;
    }

    var tests = getIn(payload, ["checks", "system", "tests"], {});
    var keys = Object.keys(tests || {});
    if (!keys.length) {
      rowsEl.innerHTML = '<tr><td colspan="3" class="text-center ap-page-sub py-4">No system tests.</td></tr>';
      return;
    }

    rowsEl.innerHTML = keys.map(function (key) {
      var test = tests[key] || {};
      var state = String(test.state || "unknown").toUpperCase();
      var detail = String(test.detail || test.value || "");
      return ""
        + "<tr>"
        + "  <td>" + escapeHtml(key) + "</td>"
        + '  <td class="text-end"><span class="ap-badge ' + checkStateClass(test.state) + '">' + escapeHtml(state) + "</span></td>"
        + "  <td>" + escapeHtml(detail) + "</td>"
        + "</tr>";
    }).join("");
  }

  function renderProjectContainersCheck(payload) {
    var listEl = doc.getElementById("apLiveProjectContainersList");
    if (!listEl) {
      return;
    }

    var check = getIn(payload, ["checks", "project", "tests", "containers"], {});
    if (!check || typeof check !== "object" || Array.isArray(check) || !Object.keys(check).length) {
      listEl.innerHTML = '<li class="ap-live-item-muted">No project containers check data.</li>';
      return;
    }

    var counts = check.counts || {};
    listEl.innerHTML = [
      '<li class="ap-live-item"><span>State</span><span class="ap-badge ' + checkStateClass(check.state) + '">' + escapeHtml(String((check.state || "unknown")).toUpperCase()) + "</span></li>",
      '<li class="ap-live-item-muted">' + escapeHtml(String(check.detail || "")) + "</li>",
      '<li class="ap-live-item"><span>Total</span><span class="ap-live-item-value">' + numberFmt(counts.total || 0) + "</span></li>",
      '<li class="ap-live-item"><span>Running</span><span class="ap-live-item-value">' + numberFmt(counts.running || 0) + "</span></li>",
      '<li class="ap-live-item"><span>Healthy</span><span class="ap-live-item-value">' + numberFmt(counts.healthy || 0) + "</span></li>",
      '<li class="ap-live-item"><span>No Health</span><span class="ap-live-item-value">' + numberFmt(counts.no_health || 0) + "</span></li>"
    ].join("");
  }

  function renderProjectArtifactsCheck(payload) {
    var listEl = doc.getElementById("apLiveProjectArtifactsList");
    if (!listEl) {
      return;
    }

    var check = getIn(payload, ["checks", "project", "tests", "artifacts"], {});
    if (!check || typeof check !== "object" || Array.isArray(check) || !Object.keys(check).length) {
      listEl.innerHTML = '<li class="ap-live-item-muted">No project artifacts check data.</li>';
      return;
    }

    var counts = check.counts || {};
    var missing = asArray(check.missing_dirs || []);

    var items = [
      '<li class="ap-live-item"><span>State</span><span class="ap-badge ' + checkStateClass(check.state) + '">' + escapeHtml(String((check.state || "unknown")).toUpperCase()) + "</span></li>",
      '<li class="ap-live-item-muted">' + escapeHtml(String(check.detail || "")) + "</li>",
      '<li class="ap-live-item"><span>Nginx conf</span><span class="ap-live-item-value">' + numberFmt(counts.nginx_conf || 0) + "</span></li>",
      '<li class="ap-live-item"><span>Apache conf</span><span class="ap-live-item-value">' + numberFmt(counts.apache_conf || 0) + "</span></li>",
      '<li class="ap-live-item"><span>Node yaml</span><span class="ap-live-item-value">' + numberFmt(counts.node_yaml || 0) + "</span></li>",
      '<li class="ap-live-item"><span>FPM conf</span><span class="ap-live-item-value">' + numberFmt(counts.fpm_conf || 0) + "</span></li>"
    ];
    if (missing.length) {
      items.push('<li class="ap-live-item-muted">Missing dirs: ' + escapeHtml(missing.join(", ")) + "</li>");
    } else {
      items.push('<li class="ap-live-item-muted">Missing dirs: none</li>');
    }

    listEl.innerHTML = items.join("");
  }

  function renderProjectMountsCheck(payload) {
    var rowsEl = doc.getElementById("apLiveProjectMountRows");
    if (!rowsEl) {
      return;
    }

    var check = getIn(payload, ["checks", "project", "tests", "mounts"], {});
    var items = asArray(check.items || []);
    if (!items.length) {
      rowsEl.innerHTML = '<tr><td colspan="4" class="text-center ap-page-sub py-4">No project mounts check data.</td></tr>';
      return;
    }

    rowsEl.innerHTML = items.map(function (item) {
      return ""
        + "<tr>"
        + "  <td>" + escapeHtml(item.key || "-") + "</td>"
        + "  <td>" + escapeHtml(item.path || "-") + "</td>"
        + '  <td class="text-end"><span class="ap-badge ' + checkStateClass(item.state) + '">' + escapeHtml(String((item.state || "unknown")).toUpperCase()) + "</span></td>"
        + "  <td>" + escapeHtml(item.flag || "-") + "</td>"
        + "</tr>";
    }).join("");
  }

  function renderNetworkMatrix(payload) {
    var headEl = doc.getElementById("apLiveNetworkMatrixHead");
    var rowsEl = doc.getElementById("apLiveNetworkMatrixRows");
    if (!headEl || !rowsEl) {
      return;
    }

    var containers = asArray(getIn(payload, ["core", "containers"], []));
    var columns = asArray(getIn(payload, ["sections", "networks", "matrix", "columns"], []));
    var rows = asArray(getIn(payload, ["sections", "networks", "matrix", "rows"], []));
    var networks = asArray(getIn(payload, ["sections", "networks", "networks"], []));
    var topConsumers = asArray(getIn(payload, ["sections", "top_consumers", "all"], []));
    var networkByName = {};
    var containerByName = {};
    var matrixByName = {};
    var topByName = {};

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

    if (!names.length) {
      headEl.innerHTML = "<tr><th>Container</th><th>Service</th><th>State</th><th>Health</th><th class=\"text-end\">CPU %</th><th class=\"text-end\">Mem Usage</th><th class=\"text-end\">Networks</th></tr>";
      rowsEl.innerHTML = '<tr><td colspan="7" class="text-center ap-page-sub py-4">No container, consumer, or matrix data.</td></tr>';
      return;
    }

    var matrixColumns = columns.length ? columns.slice() : ["Networks"];
    var networkHeaderCells = matrixColumns.map(function (col) {
      if (!columns.length) {
        return '<th class="text-end">Networks</th>';
      }

      var key = String(col || "").toLowerCase();
      var meta = key in networkByName ? networkByName[key] : {};
      var containers = meta && meta.containers != null ? numberFmt(meta.containers) : "-";
      var subnet = meta && meta.subnet ? String(meta.subnet) : "-";
      var title = String(col || "-") + " (" + containers + ")";

      return ""
        + '<th class="text-end ap-matrix-col">'
        + '<span class="ap-matrix-main">' + escapeHtml(title) + "</span>"
        + '<span class="ap-matrix-sub">' + escapeHtml(subnet) + "</span>"
        + "</th>";
    }).join("");

    headEl.innerHTML = "<tr><th>Container</th><th>Service</th><th>State</th><th>Health</th><th class=\"text-end\">CPU %</th><th class=\"text-end\">Mem Usage</th>" + networkHeaderCells + "</tr>";

    rowsEl.innerHTML = names.map(function (name) {
      var container = containerByName[name] || {};
      var matrixRow = matrixByName[name] || {};
      var topConsumer = topByName[name] || {};
      var ips = matrixRow && typeof matrixRow === "object" && matrixRow.ips ? matrixRow.ips : {};
      var service = String(container.service || "-");
      var state = String(container.state || "-");
      var health = String(container.health || "-");
      var cpuPercent = String(topConsumer.cpu_percent || "-");
      var memUsage = String(topConsumer.mem_usage || "-");
      var cells = matrixColumns.map(function (col) {
        var value = columns.length && ips && typeof ips === "object" && (col in ips) ? ips[col] : null;
        return '<td class="text-end">' + escapeHtml(value || "-") + "</td>";
      }).join("");

      var stateCell = state === "-"
        ? "-"
        : '<span class="ap-badge ' + stateBadgeClass(state) + '">' + escapeHtml(state) + "</span>";
      var healthCell = health === "-"
        ? "-"
        : '<span class="ap-badge ' + healthBadgeClass(health) + '">' + escapeHtml(health) + "</span>";

      return ""
        + "<tr>"
        + '  <td class="fw-semibold">' + escapeHtml(name) + "</td>"
        + "  <td>" + escapeHtml(service) + "</td>"
        + "  <td>" + stateCell + "</td>"
        + "  <td>" + healthCell + "</td>"
        + '  <td class="text-end">' + escapeHtml(cpuPercent) + "</td>"
        + '  <td class="text-end">' + escapeHtml(memUsage) + "</td>"
        + cells
        + "</tr>";
    }).join("");
  }

  function renderDriftDetails(payload) {
    renderSimpleList(
      "apLiveDriftOrphans",
      getIn(payload, ["sections", "drift", "orphan_containers"], []),
      "No orphan containers"
    );
    renderSimpleList(
      "apLiveDriftLabeledVolumes",
      getIn(payload, ["sections", "drift", "labeled_volumes"], []),
      "No labeled volumes"
    );
    renderSimpleList(
      "apLiveDriftUnusedVolumes",
      getIn(payload, ["sections", "drift", "unused_labeled_volumes"], []),
      "No unused labeled volumes"
    );
  }

  function renderProbes(payload) {
    var rowsEl = doc.getElementById("apLiveProbeRows");
    if (!rowsEl) {
      return;
    }
    var rows = asArray(getIn(payload, ["sections", "probes", "items"], []));
    if (!rows.length) {
      rowsEl.innerHTML = '<tr><td colspan="3" class="text-center ap-page-sub py-4">No probe data.</td></tr>';
      return;
    }
    rowsEl.innerHTML = rows.map(function (row) {
      return ""
        + "<tr>"
        + "  <td>" + escapeHtml(row.url || "-") + "</td>"
        + '  <td class="text-end">' + escapeHtml(row.status_code || "-") + "</td>"
        + '  <td class="text-end">' + escapeHtml(row.time_seconds || "-") + "</td>"
        + "</tr>";
    }).join("");
  }

  function renderRecentErrors(payload) {
    var listEl = doc.getElementById("apLiveRecentErrors");
    if (!listEl) {
      return;
    }
    var rows = asArray(getIn(payload, ["sections", "recent_errors", "items"], []));
    if (!rows.length) {
      listEl.innerHTML = '<li class="ap-live-item-muted">No recent errors.</li>';
      return;
    }
    listEl.innerHTML = rows.slice(0, 8).map(function (row) {
      if (typeof row === "string") {
        return '<li class="ap-live-item">' + escapeHtml(row) + "</li>";
      }
      return '<li class="ap-live-item">' + escapeHtml(JSON.stringify(row)) + "</li>";
    }).join("");
  }

  function renderRawPayload(payload) {
    var el = doc.getElementById("apLiveRawJson");
    if (!el) {
      return;
    }
    try {
      el.textContent = JSON.stringify(payload, null, 2);
    } catch (e) {
      el.textContent = "Unable to render raw payload.";
    }
  }

  function renderSummary(payload, summary, generatedAt) {
    setText("apLiveRunning", numberFmt(summary.running) + " / " + numberFmt(summary.total));
    setText("apLiveHealth", numberFmt(summary.healthy) + " / " + numberFmt(summary.unhealthy) + " / " + numberFmt(summary.no_health));
    setText("apLiveUrls", numberFmt(summary.url_count));
    setText("apLivePorts", numberFmt(summary.port_count));
    setText("apLiveProblems", numberFmt(summary.problem_count));
    setText("apLiveUpdatedAt", generatedAt ? "Updated: " + generatedAt : "Updated: -");

    renderChecks(payload, summary);
    renderSimpleList("apLiveUrlList", getIn(payload, ["core", "urls"], []), "No URLs");
    renderSimpleList("apLivePortList", getIn(payload, ["core", "ports"], []), "No ports");
    renderSimpleList("apLivePortContainerList", asArray(getIn(payload, ["core", "ports_by_container"], [])).map(function (item) {
      return String(item.name || "-") + ": " + String(item.ports || "-");
    }), "No ports-by-container");

    var driftList = [];
    var reclaimable = summary.build_cache_reclaimable || "-";
    var egressIp = summary.egress_ip || "-";
    var builderPruneHint = !!getIn(payload, ["sections", "drift", "builder_prune_hint"], false);
    var orphanCount = asArray(getIn(payload, ["sections", "drift", "orphan_containers"], [])).length;
    var unusedVolumeCount = asArray(getIn(payload, ["sections", "drift", "unused_labeled_volumes"], [])).length;

    driftList.push("Build cache reclaimable: " + reclaimable);
    driftList.push("Egress IP: " + egressIp);
    driftList.push("Orphan containers: " + numberFmt(orphanCount));
    driftList.push("Unused labeled volumes: " + numberFmt(unusedVolumeCount));
    driftList.push("Builder prune hint: " + (builderPruneHint ? "yes" : "no"));
    renderSimpleList("apLiveDriftList", driftList, "No drift info");

    var problemItems = asArray(getIn(payload, ["sections", "problems", "items"], [])).map(function (item) {
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
        return JSON.stringify(item);
      }
      return String(item);
    });
    renderSimpleList("apLiveProblemList", problemItems, "No problem items");
  }

  function renderCharts() {
    if (typeof window.Chart === "undefined") {
      return;
    }

    clearCharts();

    var mutedColor = cssVar("--ap-muted", "#6b7280");
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

    var cpuEl = doc.getElementById("apLiveCpuChart");
    if (cpuEl) {
      var cpuRows = asArray(getIn(livePayload, ["sections", "top_consumers", "by_cpu"], []));
      var cpuLabels = cpuRows.map(function (row) { return row.name; });
      var cpuValues = cpuRows.map(function (row) { return Number(row.cpu_value || 0); });
      if (!cpuLabels.length) {
        cpuLabels = ["No data"];
        cpuValues = [0];
      }

      charts.push(new window.Chart(cpuEl, {
        type: "bar",
        data: {
          labels: cpuLabels,
          datasets: [{
            label: "CPU %",
            data: cpuValues,
            backgroundColor: primary,
            borderRadius: 8,
            barThickness: 24
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
              ticks: { color: mutedColor, font: { size: 11 } }
            }
          }
        }
      }));
    }

    var memEl = doc.getElementById("apLiveMemoryChart");
    if (memEl) {
      var memRows = asArray(getIn(livePayload, ["sections", "top_consumers", "by_mem"], []));
      var memLabels = memRows.map(function (row) { return row.name; });
      var memValues = memRows.map(function (row) {
        var bytes = Number(row.mem_bytes || 0);
        return Math.max(0.1, Math.round((bytes / 1048576) * 100) / 100);
      });
      if (!memLabels.length) {
        memLabels = ["No data"];
        memValues = [1];
      }

      charts.push(new window.Chart(memEl, {
        type: "bar",
        data: {
          labels: memLabels,
          datasets: [{
            label: "Memory MiB",
            data: memValues,
            backgroundColor: accentPalette.slice(0, memLabels.length),
            borderRadius: 8,
            barThickness: 14
          }]
        },
        options: {
          indexAxis: "y",
          plugins: {
            legend: {
              display: false
            }
          },
          scales: {
            x: {
              border: { display: false },
              grid: { color: borderColor },
              ticks: { color: mutedColor, font: { size: 10 } }
            },
            y: {
              border: { display: false },
              grid: { display: false },
              ticks: { color: mutedColor, font: { size: 10 } }
            }
          }
        }
      }));
    }

    var liveStatsEl = doc.getElementById("apLiveStatsChart");
    if (liveStatsEl) {
      var statsRows = asArray(getIn(livePayload, ["sections", "stats", "items"], []))
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
        .slice(0, 12);

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

      charts.push(new window.Chart(liveStatsEl, {
        type: "bar",
        data: {
          labels: statsLabels,
          datasets: [
            {
              label: "CPU %",
              data: statsCpuValues,
              rawValues: statsCpuRaw,
              rawUnit: "%",
              backgroundColor: primary,
              borderRadius: 6,
              barThickness: 10
            },
            {
              label: "Memory (MiB)",
              data: statsMemValues,
              rawValues: statsMemRaw,
              rawUnit: "MiB",
              backgroundColor: success,
              borderRadius: 6,
              barThickness: 10
            },
            {
              label: "Net I/O (MiB)",
              data: statsNetValues,
              rawValues: statsNetRaw,
              rawUnit: "MiB",
              backgroundColor: warn,
              borderRadius: 6,
              barThickness: 10
            },
            {
              label: "Block I/O (MiB)",
              data: statsBlockValues,
              rawValues: statsBlockRaw,
              rawUnit: "MiB",
              backgroundColor: danger,
              borderRadius: 6,
              barThickness: 10
            }
          ]
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
                color: mutedColor,
                boxWidth: 10,
                font: { size: 10, weight: "600" }
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
              ticks: { color: mutedColor, font: { size: 10 }, maxRotation: 45, minRotation: 25 }
            },
            y: {
              type: "linear",
              beginAtZero: true,
              max: 100,
              border: { display: false },
              grid: { color: borderColor },
              ticks: {
                color: mutedColor,
                font: { size: 10 },
                callback: function (value) {
                  return value + "%";
                }
              },
              title: {
                display: true,
                text: "Percent of max per metric",
                color: mutedColor,
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
              ticks: { color: mutedColor, font: { size: 10 } }
            },
            y: {
              border: { display: false },
              grid: { display: false },
              ticks: { color: mutedColor, font: { size: 10 } }
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
              ticks: { color: mutedColor, font: { size: 10 } }
            },
            y: {
              border: { display: false },
              grid: { display: false },
              ticks: { color: mutedColor, font: { size: 10 } }
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

    doc.querySelectorAll(".ap-nav-link").forEach(function (link) {
      link.addEventListener("click", function () {
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
    renderDriftDetails(payload);
    renderProbes(payload);
    renderRecentErrors(payload);
    renderSystemTestsTable(payload);
    renderProjectContainersCheck(payload);
    renderProjectArtifactsCheck(payload);
    renderProjectMountsCheck(payload);
    renderRawPayload(payload);
    renderCharts();
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

  function initLiveStats() {
    if (!doc.getElementById("apLiveStatsPage")) {
      return;
    }

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
