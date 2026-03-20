<?php
declare(strict_types=1);
?>

<section class="ap-page-head">
  <div>
    <p class="ap-breadcrumb mb-1">Home / Host Manager</p>
    <h2 class="ap-page-title mb-1">Host Manager</h2>
    <p class="ap-page-sub mb-0">Manage vhost entries with add, edit, and delete actions.</p>
  </div>
  <div class="d-flex align-items-center gap-2 flex-wrap">
    <button id="apHostRefreshBtn" class="btn ap-ghost-btn" type="button">
      <i class="bi bi-arrow-repeat me-1"></i> Refresh
    </button>
    <button id="apHostAddBtn" class="btn btn-primary" type="button">
      <i class="bi bi-plus-circle me-1"></i> Add Host
    </button>
  </div>
</section>

<style>
  .ap-host-actions .btn {
    width: 2rem;
    height: 2rem;
    padding: 0;
    display: inline-flex;
    align-items: center;
    justify-content: center;
  }

  .ap-host-modal .modal-content {
    background: var(--ap-surface);
    border: 1px solid var(--ap-border);
    box-shadow: 0 24px 64px color-mix(in srgb, var(--ap-bg) 58%, transparent);
  }

  .ap-host-modal .modal-header,
  .ap-host-modal .modal-footer {
    background: color-mix(in srgb, var(--ap-surface-2) 86%, transparent);
    border-color: var(--ap-border);
  }

  .ap-host-modal .modal-body {
    background: var(--ap-surface);
  }
</style>

<div id="apHostMessage" class="d-none mb-3"></div>

<section class="row g-3 mt-1">
  <div class="col-12">
    <article class="card ap-card h-100">
      <header class="card-header ap-card-head ap-card-head-wrap">
        <div>
          <h4 class="ap-card-title mb-1"><i class="bi bi-hdd-network me-1"></i>Hosts</h4>
          <p id="apHostMeta" class="ap-card-sub mb-0">Listing generated nginx host configs.</p>
        </div>
      </header>
      <div class="card-body">
        <div id="apHostSummary" class="ap-monitor-summary mb-3"></div>
        <div class="table-responsive ap-local-sticky">
          <table class="table ap-table ap-table-sticky ap-table-emphasis mb-0">
            <thead>
            <tr>
              <th>Domain</th>
              <th>App</th>
              <th>Server</th>
              <th>Protocol</th>
              <th>Doc Root</th>
              <th>Runtime</th>
              <th>Updated</th>
              <th class="text-end"><i class="bi bi-gear me-1"></i>Actions</th>
            </tr>
            </thead>
            <tbody id="apHostRows">
            <tr><td colspan="8" class="text-center ap-page-sub py-4">Loading...</td></tr>
            </tbody>
          </table>
        </div>
      </div>
    </article>
  </div>
</section>

<div class="modal fade ap-host-modal" id="apHostModal" tabindex="-1" aria-hidden="true">
  <div class="modal-dialog modal-lg modal-dialog-scrollable">
    <div class="modal-content ap-card">
      <form id="apHostForm" novalidate>
        <div class="modal-header ap-card-head">
          <h5 class="modal-title"><i class="bi bi-hdd-network me-2"></i><span id="apHostModalTitle">Add Host</span></h5>
          <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
        </div>
        <div class="modal-body">
          <div id="apHostFormError" class="alert alert-danger d-none" role="alert"></div>
          <input type="hidden" id="apHostOriginalDomain" value="">

          <div class="mb-2">
            <h6 class="fw-semibold mb-1"><i class="bi bi-ui-radios-grid me-1"></i>Base</h6>
          </div>
          <div class="row g-3 align-items-end">
            <div class="col-md-6">
              <label for="apHostAppType" class="form-label">App Type</label>
              <select class="form-select" id="apHostAppType">
                <option value="php" selected>PHP</option>
                <option value="node">Node</option>
                <option value="proxyip">Proxy (Fixed IP)</option>
              </select>
            </div>
            <div class="col-md-6">
              <label for="apHostDomain" class="form-label">Domain</label>
              <input type="text" class="form-control" id="apHostDomain" placeholder="example.localhost" required>
            </div>
          </div>

          <hr class="my-4">

          <div class="mb-2">
            <h6 class="fw-semibold mb-1"><i class="bi bi-cpu me-1"></i>Runtime</h6>
          </div>
          <div class="row g-3">
            <div id="apHostPhpVersionWrap" class="col-md-6">
              <label for="apHostPhpRuntimeIndex" class="form-label">PHP Runtime</label>
              <select class="form-select" id="apHostPhpRuntimeIndex"></select>
              <input type="text" class="form-control mt-2 d-none" id="apHostPhpVersionCustom" placeholder="Custom PHP version (>=5.5, e.g. 8.4)">
            </div>
            <div id="apHostServerWrap" class="col-md-6">
              <label for="apHostServerType" class="form-label">Server Type (PHP)</label>
              <select class="form-select" id="apHostServerType">
                <option value="nginx" selected>Nginx</option>
                <option value="apache">Apache</option>
              </select>
            </div>
            <div id="apHostNodeVersionWrap" class="col-md-6 d-none">
              <label for="apHostNodeRuntimeIndex" class="form-label">Node Runtime</label>
              <select class="form-select" id="apHostNodeRuntimeIndex"></select>
              <input type="text" class="form-control mt-2 d-none" id="apHostNodeVersionCustom" placeholder="Custom Node major (e.g. 24)">
            </div>
            <div id="apHostNodeCommandWrap" class="col-md-6 d-none">
              <label for="apHostNodeCommand" class="form-label">Node Command (optional)</label>
              <input type="text" class="form-control" id="apHostNodeCommand" placeholder="npm run dev">
            </div>
            <div id="apHostProxyPrimaryWrap" class="col-12 d-none">
              <div class="row g-3">
                <div class="col-md-6">
                  <label for="apHostProxyHost" class="form-label">Proxy Host</label>
                  <input type="text" class="form-control" id="apHostProxyHost" placeholder="upstream.example.com">
                </div>
                <div class="col-md-6">
                  <label for="apHostProxyIp" class="form-label">Proxy IP</label>
                  <input type="text" class="form-control" id="apHostProxyIp" placeholder="192.168.10.5">
                </div>
              </div>
            </div>
          </div>

          <hr class="my-4">

          <div class="mb-2">
            <h6 class="fw-semibold mb-1"><i class="bi bi-shield-lock me-1"></i>Protocol & TLS</h6>
          </div>
          <div class="row g-3">
            <div class="col-md-6">
              <label for="apHostProtocol" class="form-label">Protocol</label>
              <select class="form-select" id="apHostProtocol">
                <option value="both" selected>Both (HTTP + HTTPS)</option>
                <option value="https">HTTPS only</option>
                <option value="http">HTTP only</option>
              </select>
            </div>
            <div id="apHostRedirectWrap" class="col-md-6">
              <div class="form-check mt-md-4 pt-md-2">
                <input class="form-check-input" type="checkbox" id="apHostRedirectHttps" checked>
                <label class="form-check-label" for="apHostRedirectHttps">HTTP to HTTPS redirect</label>
              </div>
            </div>
            <div id="apHostProxyPortsWrap" class="col-12 d-none">
              <div class="row g-3">
                <div class="col-md-6">
                  <label for="apHostProxyHttpPort" class="form-label">Proxy HTTP Port</label>
                  <input type="number" class="form-control" id="apHostProxyHttpPort" value="80" min="1" max="65535">
                </div>
                <div class="col-md-6">
                  <label for="apHostProxyHttpsPort" class="form-label">Proxy HTTPS Port</label>
                  <input type="number" class="form-control" id="apHostProxyHttpsPort" value="443" min="1" max="65535">
                </div>
              </div>
            </div>
            <div id="apHostMtlsWrap" class="col-md-6">
              <div class="form-check mt-md-4 pt-md-2">
                <input class="form-check-input" type="checkbox" id="apHostMtls">
                <label class="form-check-label" for="apHostMtls">Client cert verification (mTLS)</label>
              </div>
            </div>
          </div>

          <hr class="my-4">

          <div class="mb-2">
            <h6 class="fw-semibold mb-1"><i class="bi bi-folder2-open me-1"></i>Path & Limits</h6>
          </div>
          <div class="row g-3">
            <div id="apHostDocRootWrap" class="col-md-6">
              <label for="apHostDocRootIndex" class="form-label">Doc Root</label>
              <select class="form-select" id="apHostDocRootIndex"></select>
              <input type="text" class="form-control mt-2 d-none" id="apHostDocRootCustom" value="/app" placeholder="/site/public">
            </div>
            <div class="col-md-3">
              <label for="apHostBodySize" class="form-label">Client Body Size (MB)</label>
              <input type="number" class="form-control" id="apHostBodySize" value="10" min="1" max="4096">
            </div>
            <div class="col-md-3">
              <div class="form-check mt-md-4 pt-md-2">
                <input class="form-check-input" type="checkbox" id="apHostStreaming">
                <label class="form-check-label" for="apHostStreaming">Streaming / SSE mode</label>
              </div>
            </div>
          </div>

          <div id="apHostProxyAdvancedWrap" class="row g-3 d-none mt-1">
            <div class="col-12">
              <hr class="my-3">
              <h6 class="fw-semibold mb-1"><i class="bi bi-sliders2 me-1"></i>Proxy Advanced</h6>
            </div>
            <div class="col-md-6">
              <div class="form-check mt-md-4 pt-md-2">
                <input class="form-check-input" type="checkbox" id="apHostProxyWebsocket">
                <label class="form-check-label" for="apHostProxyWebsocket">Enable WebSocket/HMR support</label>
              </div>
            </div>
            <div class="col-md-6">
              <div class="form-check mt-md-4 pt-md-2">
                <input class="form-check-input" type="checkbox" id="apHostProxyRewrite" checked>
                <label class="form-check-label" for="apHostProxyRewrite">Rewrite cookies + redirects</label>
              </div>
            </div>
            <div id="apHostParentCookieWrap" class="col-md-6">
              <label for="apHostParentCookieDomain" class="form-label">Parent Cookie Domain (optional)</label>
              <input type="text" class="form-control" id="apHostParentCookieDomain" placeholder=".example.com">
            </div>
            <div class="col-md-6">
              <div class="form-check mt-md-4 pt-md-2">
                <input class="form-check-input" type="checkbox" id="apHostProxySubfilter">
                <label class="form-check-label" for="apHostProxySubfilter">Enable sub_filter rewrite</label>
              </div>
            </div>
            <div class="col-md-6">
              <div class="form-check">
                <input class="form-check-input" type="checkbox" id="apHostProxyCsp">
                <label class="form-check-label" for="apHostProxyCsp">Relax CSP (last resort)</label>
              </div>
            </div>
          </div>
        </div>
        <div class="modal-footer">
          <button type="button" class="btn btn-outline-secondary" data-bs-dismiss="modal">
            <i class="bi bi-x-circle me-1"></i>Cancel
          </button>
          <button id="apHostSubmitBtn" type="submit" class="btn btn-primary">
            <i class="bi bi-check2-circle me-1"></i>Save
          </button>
        </div>
      </form>
    </div>
  </div>
</div>

<script>
  (function () {
    "use strict";

    var basePath = (document.body && document.body.getAttribute("data-ap-base")) || "";
    if (basePath === "/") {
      basePath = "";
    }

    var apiUrl = basePath + "/api/hosts";
    var rowsEl = document.getElementById("apHostRows");
    if (!rowsEl) {
      return;
    }

    var summaryEl = document.getElementById("apHostSummary");
    var metaEl = document.getElementById("apHostMeta");
    var msgEl = document.getElementById("apHostMessage");
    var refreshBtn = document.getElementById("apHostRefreshBtn");
    var addBtn = document.getElementById("apHostAddBtn");
    var formEl = document.getElementById("apHostForm");
    var formErrEl = document.getElementById("apHostFormError");
    var submitBtn = document.getElementById("apHostSubmitBtn");
    var modalTitleEl = document.getElementById("apHostModalTitle");
    var originalDomainEl = document.getElementById("apHostOriginalDomain");

    var appTypeEl = document.getElementById("apHostAppType");
    var protocolEl = document.getElementById("apHostProtocol");
    var proxyRewriteEl = document.getElementById("apHostProxyRewrite");
    var serverWrapEl = document.getElementById("apHostServerWrap");
    var docRootWrapEl = document.getElementById("apHostDocRootWrap");
    var phpVersionWrapEl = document.getElementById("apHostPhpVersionWrap");
    var nodeVersionWrapEl = document.getElementById("apHostNodeVersionWrap");
    var nodeCommandWrapEl = document.getElementById("apHostNodeCommandWrap");
    var proxyPrimaryWrapEl = document.getElementById("apHostProxyPrimaryWrap");
    var proxyPortsWrapEl = document.getElementById("apHostProxyPortsWrap");
    var proxyAdvancedWrapEl = document.getElementById("apHostProxyAdvancedWrap");
    var redirectWrapEl = document.getElementById("apHostRedirectWrap");
    var mtlsWrapEl = document.getElementById("apHostMtlsWrap");
    var parentCookieWrapEl = document.getElementById("apHostParentCookieWrap");
    var phpRuntimeIndexEl = document.getElementById("apHostPhpRuntimeIndex");
    var phpVersionCustomEl = document.getElementById("apHostPhpVersionCustom");
    var nodeRuntimeIndexEl = document.getElementById("apHostNodeRuntimeIndex");
    var nodeVersionCustomEl = document.getElementById("apHostNodeVersionCustom");
    var docRootIndexEl = document.getElementById("apHostDocRootIndex");
    var docRootCustomEl = document.getElementById("apHostDocRootCustom");

    var modalEl = document.getElementById("apHostModal");
    var modal = null;
    var itemMap = Object.create(null);
    var optionsCache = { php_runtime: [], node_runtime: [], doc_root: [] };

    function getModal() {
      if (modal) {
        return modal;
      }
      if (modalEl && window.bootstrap && window.bootstrap.Modal) {
        modal = new window.bootstrap.Modal(modalEl);
      }
      return modal;
    }

    function esc(value) {
      return String(value || "")
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;")
        .replace(/'/g, "&#039;");
    }

    function showMessage(kind, text) {
      if (!msgEl) {
        return;
      }
      var t = String(text || "").trim();
      if (!t) {
        msgEl.className = "d-none mb-3";
        msgEl.textContent = "";
        return;
      }
      var cls = kind === "success" ? "alert alert-success mb-3" : "alert alert-danger mb-3";
      msgEl.className = cls;
      msgEl.textContent = t;
    }

    function showRebootAlert(payload) {
      if (!payload || !payload.reboot_required) {
        return;
      }
      var rebootCmd = String(payload.reboot_command || "lds reboot").trim() || "lds reboot";
      window.alert("Host change applied. Reboot required: `" + rebootCmd + "`");
    }

    function showFormError(text) {
      if (!formErrEl) {
        return;
      }
      var t = String(text || "").trim();
      if (!t) {
        formErrEl.classList.add("d-none");
        formErrEl.textContent = "";
        return;
      }
      formErrEl.classList.remove("d-none");
      formErrEl.textContent = t;
    }

    function toNumber(value, fallback) {
      var n = Number(value);
      if (!isFinite(n)) {
        return fallback;
      }
      return Math.round(n);
    }

    function clearSelect(node) {
      if (!node) {
        return;
      }
      while (node.firstChild) {
        node.removeChild(node.firstChild);
      }
    }

    function fillSelect(node, options) {
      if (!node) {
        return;
      }
      clearSelect(node);
      var list = Array.isArray(options) ? options : [];
      list.forEach(function (opt) {
        var option = document.createElement("option");
        option.value = String(opt && opt.index != null ? opt.index : "");
        option.textContent = String(opt && opt.label || "");
        node.appendChild(option);
      });
    }

    function hasIndex(options, idx) {
      var value = String(idx);
      return (Array.isArray(options) ? options : []).some(function (opt) {
        return String(opt && opt.index != null ? opt.index : "") === value;
      });
    }

    function findIndexByValue(options, value) {
      var list = Array.isArray(options) ? options : [];
      var target = String(value || "");
      for (var i = 0; i < list.length; i += 1) {
        var opt = list[i] || {};
        if (String(opt.kind || "") === "custom") {
          continue;
        }
        if (String(opt.value || "") === target) {
          return String(opt.index != null ? opt.index : "");
        }
      }
      return "";
    }

    function applyOptionDefaults() {
      if (phpRuntimeIndexEl) {
        phpRuntimeIndexEl.value = hasIndex(optionsCache.php_runtime, 1) ? "1" : "0";
      }
      if (nodeRuntimeIndexEl) {
        nodeRuntimeIndexEl.value = hasIndex(optionsCache.node_runtime, 2) ? "2" : (hasIndex(optionsCache.node_runtime, 1) ? "1" : "0");
      }
      if (docRootIndexEl) {
        docRootIndexEl.value = "0";
      }
    }

    function syncCustomFieldVisibility() {
      var app = String(appTypeEl && appTypeEl.value || "php").toLowerCase();
      var showPhpCustom = app === "php" && String(phpRuntimeIndexEl && phpRuntimeIndexEl.value || "") === "0";
      var showNodeCustom = app === "node" && String(nodeRuntimeIndexEl && nodeRuntimeIndexEl.value || "") === "0";
      var showDocRootCustom = app !== "proxyip" && String(docRootIndexEl && docRootIndexEl.value || "") === "0";

      if (phpVersionCustomEl) {
        phpVersionCustomEl.classList.toggle("d-none", !showPhpCustom);
      }
      if (nodeVersionCustomEl) {
        nodeVersionCustomEl.classList.toggle("d-none", !showNodeCustom);
      }
      if (docRootCustomEl) {
        docRootCustomEl.classList.toggle("d-none", !showDocRootCustom);
      }
    }

    function renderSummary(summary) {
      var s = summary && typeof summary === "object" ? summary : {};
      summaryEl.innerHTML = ""
        + '<span class="ap-kv-group ap-live-state-info"><span class="ap-kv-group-key">Hosts</span><span class="ap-kv-group-val">' + esc(String(s.hosts || 0)) + "</span></span>"
        + '<span class="ap-kv-group ap-live-state-info"><span class="ap-kv-group-key">PHP</span><span class="ap-kv-group-val">' + esc(String(s.php || 0)) + "</span></span>"
        + '<span class="ap-kv-group ap-live-state-info"><span class="ap-kv-group-key">Node</span><span class="ap-kv-group-val">' + esc(String(s.node || 0)) + "</span></span>"
        + '<span class="ap-kv-group ap-live-state-info"><span class="ap-kv-group-key">Proxy</span><span class="ap-kv-group-val">' + esc(String(s.proxyip || 0)) + "</span></span>"
        + '<span class="ap-kv-group ap-live-state-info"><span class="ap-kv-group-key">Unknown</span><span class="ap-kv-group-val">' + esc(String(s.unknown || 0)) + "</span></span>";
    }

    function renderRows(items) {
      if (!Array.isArray(items) || items.length === 0) {
        rowsEl.innerHTML = '<tr><td colspan="8" class="text-center ap-page-sub py-4">No hosts found.</td></tr>';
        return;
      }
      rowsEl.innerHTML = items.map(function (item) {
        var domain = String(item && item.domain || "");
        return ""
          + "<tr>"
          + "  <td>" + esc(domain) + "</td>"
          + "  <td>" + esc(String(item && item.app_type || "unknown")) + "</td>"
          + "  <td>" + esc(String(item && item.server_type || "-")) + "</td>"
          + "  <td>" + esc(String(item && item.protocol || "-")) + "</td>"
          + "  <td>" + esc(String(item && item.doc_root || "-")) + "</td>"
          + "  <td>" + esc(String(item && item.runtime || "-")) + "</td>"
          + "  <td>" + esc(String(item && item.updated_at || "-")) + "</td>"
          + '  <td class="text-end ap-host-actions">'
          + '    <button type="button" class="btn btn-sm btn-outline-primary me-1" title="Edit host" aria-label="Edit host" data-host-action="edit" data-domain="' + esc(domain) + '"><i class="bi bi-pencil-square"></i></button>'
          + '    <button type="button" class="btn btn-sm btn-outline-danger" title="Delete host" aria-label="Delete host" data-host-action="delete" data-domain="' + esc(domain) + '"><i class="bi bi-trash"></i></button>'
          + "  </td>"
          + "</tr>";
      }).join("");
    }

    function syncFieldVisibility() {
      var app = String(appTypeEl && appTypeEl.value || "php").toLowerCase();
      var protocol = String(protocolEl && protocolEl.value || "both").toLowerCase();
      var isProxy = app === "proxyip";
      var isNode = app === "node";
      var isPhp = app === "php";
      serverWrapEl.classList.toggle("d-none", !isPhp);
      phpVersionWrapEl.classList.toggle("d-none", !isPhp);
      nodeVersionWrapEl.classList.toggle("d-none", !isNode);
      nodeCommandWrapEl.classList.toggle("d-none", !isNode);
      docRootWrapEl.classList.toggle("d-none", isProxy);
      proxyPrimaryWrapEl.classList.toggle("d-none", !isProxy);
      proxyPortsWrapEl.classList.toggle("d-none", !isProxy);
      proxyAdvancedWrapEl.classList.toggle("d-none", !isProxy);
      redirectWrapEl.classList.toggle("d-none", protocol !== "both");
      mtlsWrapEl.classList.toggle("d-none", protocol === "http");
      parentCookieWrapEl.classList.toggle("d-none", !(isProxy && proxyRewriteEl && proxyRewriteEl.checked));
      syncCustomFieldVisibility();
    }

    function resetForm() {
      formEl.reset();
      if (originalDomainEl) {
        originalDomainEl.value = "";
      }
      document.getElementById("apHostDomain").value = "";
      if (docRootCustomEl) {
        docRootCustomEl.value = "/app";
      }
      if (phpVersionCustomEl) {
        phpVersionCustomEl.value = "";
      }
      if (nodeVersionCustomEl) {
        nodeVersionCustomEl.value = "";
      }
      applyOptionDefaults();
      document.getElementById("apHostBodySize").value = "10";
      document.getElementById("apHostProxyHttpPort").value = "80";
      document.getElementById("apHostProxyHttpsPort").value = "443";
      document.getElementById("apHostRedirectHttps").checked = true;
      document.getElementById("apHostProxyRewrite").checked = true;
      showFormError("");
      syncFieldVisibility();
    }

    function fillFormFromItem(item) {
      if (!item || typeof item !== "object") {
        return;
      }
      document.getElementById("apHostDomain").value = String(item.domain || "");
      document.getElementById("apHostAppType").value = String(item.app_type || "php");
      document.getElementById("apHostServerType").value = String(item.server_type || "nginx");
      document.getElementById("apHostProtocol").value = String(item.protocol || "both");
      var docRoot = String(item.doc_root || "/app");
      var phpVersion = String(item.php_version || "");
      var nodeVersion = String(item.node_version || "");

      if (phpRuntimeIndexEl) {
        var phpIdx = findIndexByValue(optionsCache.php_runtime, phpVersion);
        phpRuntimeIndexEl.value = phpIdx !== "" ? phpIdx : "0";
      }
      if (phpVersionCustomEl) {
        phpVersionCustomEl.value = phpVersion;
      }
      if (nodeRuntimeIndexEl) {
        var nodeIdx = findIndexByValue(optionsCache.node_runtime, nodeVersion);
        nodeRuntimeIndexEl.value = nodeIdx !== "" ? nodeIdx : "0";
      }
      if (nodeVersionCustomEl) {
        nodeVersionCustomEl.value = nodeVersion;
      }
      if (docRootIndexEl) {
        var docIdx = findIndexByValue(optionsCache.doc_root, docRoot);
        docRootIndexEl.value = docIdx !== "" ? docIdx : "0";
      }
      if (docRootCustomEl) {
        docRootCustomEl.value = docRoot;
      }
      document.getElementById("apHostProxyHost").value = String(item.proxy_host || "");
      document.getElementById("apHostProxyIp").value = String(item.proxy_ip || "");
      document.getElementById("apHostProxyHttpPort").value = String(item.proxy_http_port || "80");
      document.getElementById("apHostProxyHttpsPort").value = String(item.proxy_https_port || "443");
      document.getElementById("apHostNodeCommand").value = "";
      document.getElementById("apHostRedirectHttps").checked = true;
      syncFieldVisibility();
    }

    function setBusy(isBusy) {
      if (refreshBtn) {
        refreshBtn.disabled = !!isBusy;
      }
      if (addBtn) {
        addBtn.disabled = !!isBusy;
      }
      if (submitBtn) {
        submitBtn.disabled = !!isBusy;
      }
    }

    function fetchJson(url, options) {
      return fetch(url, options || {
        method: "GET",
        credentials: "same-origin",
        cache: "no-store",
        headers: { "Accept": "application/json" }
      })
        .then(function (res) {
          return res.json().catch(function () { return null; }).then(function (json) {
            return { ok: res.ok, status: res.status, json: json || {} };
          });
        });
    }

    function loadFormOptions() {
      return fetchJson(apiUrl + "?action=options")
        .then(function (res) {
          var payload = res.json || {};
          if (!res.ok || !payload.ok) {
            throw new Error(payload.message || ("host options api failed (" + String(res.status) + ")"));
          }
          var options = payload.options && typeof payload.options === "object" ? payload.options : {};
          optionsCache.php_runtime = Array.isArray(options.php_runtime) ? options.php_runtime : [];
          optionsCache.node_runtime = Array.isArray(options.node_runtime) ? options.node_runtime : [];
          optionsCache.doc_root = Array.isArray(options.doc_root) ? options.doc_root : [];
          if (optionsCache.php_runtime.length === 0) {
            optionsCache.php_runtime = [{ index: 0, kind: "custom", value: "", label: "Custom Version (>= 5.5)" }];
          }
          if (optionsCache.node_runtime.length === 0) {
            optionsCache.node_runtime = [{ index: 0, kind: "custom", value: "", label: "Custom Version" }];
          }
          if (optionsCache.doc_root.length === 0) {
            optionsCache.doc_root = [{ index: 0, kind: "custom", value: "", label: "<Custom Path>" }];
          }

          fillSelect(phpRuntimeIndexEl, optionsCache.php_runtime);
          fillSelect(nodeRuntimeIndexEl, optionsCache.node_runtime);
          fillSelect(docRootIndexEl, optionsCache.doc_root);
          applyOptionDefaults();
          syncCustomFieldVisibility();
        })
        .catch(function (err) {
          showMessage("error", err && err.message ? err.message : "Unable to load runtime/doc-root options.");
        });
    }

    function loadHosts() {
      setBusy(true);
      return fetchJson(apiUrl)
        .then(function (res) {
          var payload = res.json || {};
          if (!res.ok || !payload.ok) {
            throw new Error(payload.message || ("host api failed (" + String(res.status) + ")"));
          }
          var items = Array.isArray(payload.items) ? payload.items : [];
          itemMap = Object.create(null);
          items.forEach(function (it) {
            var d = String(it && it.domain || "").toLowerCase();
            if (d) {
              itemMap[d] = it;
            }
          });
          renderSummary(payload.summary || {});
          renderRows(items);
          if (metaEl) {
            metaEl.textContent = "Updated: " + String(payload.generated_at || "-");
          }
        })
        .catch(function (err) {
          renderSummary({});
          renderRows([]);
          showMessage("error", err && err.message ? err.message : "Unable to load hosts.");
        })
        .finally(function () {
          setBusy(false);
        });
    }

    function collectPayload() {
      var app = String(document.getElementById("apHostAppType").value || "php").toLowerCase();
      var protocol = String(document.getElementById("apHostProtocol").value || "both").toLowerCase();
      return {
        domain: String(document.getElementById("apHostDomain").value || "").trim(),
        app_type: app,
        server_type: String(document.getElementById("apHostServerType").value || "nginx").toLowerCase(),
        protocol: protocol,
        redirect_https: !!document.getElementById("apHostRedirectHttps").checked,
        php_runtime_index: String(phpRuntimeIndexEl && phpRuntimeIndexEl.value || "").trim(),
        php_version_custom: String(phpVersionCustomEl && phpVersionCustomEl.value || "").trim(),
        node_runtime_index: String(nodeRuntimeIndexEl && nodeRuntimeIndexEl.value || "").trim(),
        node_version_custom: String(nodeVersionCustomEl && nodeVersionCustomEl.value || "").trim(),
        doc_root_index: String(docRootIndexEl && docRootIndexEl.value || "").trim(),
        doc_root_custom: String(docRootCustomEl && docRootCustomEl.value || "").trim(),
        node_command: String(document.getElementById("apHostNodeCommand").value || "").trim(),
        body_size_mb: toNumber(document.getElementById("apHostBodySize").value, 10),
        streaming: !!document.getElementById("apHostStreaming").checked,
        mtls: !!document.getElementById("apHostMtls").checked,
        proxy_host: String(document.getElementById("apHostProxyHost").value || "").trim(),
        proxy_ip: String(document.getElementById("apHostProxyIp").value || "").trim(),
        proxy_http_port: toNumber(document.getElementById("apHostProxyHttpPort").value, 80),
        proxy_https_port: toNumber(document.getElementById("apHostProxyHttpsPort").value, 443),
        proxy_websocket: !!document.getElementById("apHostProxyWebsocket").checked,
        proxy_rewrite: !!document.getElementById("apHostProxyRewrite").checked,
        parent_cookie_domain: String(document.getElementById("apHostParentCookieDomain").value || "").trim(),
        proxy_subfilter: !!document.getElementById("apHostProxySubfilter").checked,
        proxy_csp: !!document.getElementById("apHostProxyCsp").checked
      };
    }

    function openForAdd() {
      resetForm();
      if (modalTitleEl) {
        modalTitleEl.textContent = "Add Host";
      }
      var m = getModal();
      if (m) {
        m.show();
      } else {
        showMessage("error", "Modal is not ready yet. Please retry in a moment.");
      }
    }

    function openForEdit(domain) {
      var key = String(domain || "").toLowerCase();
      var item = itemMap[key];
      if (!item) {
        showMessage("error", "Host not found: " + domain);
        return;
      }
      resetForm();
      if (originalDomainEl) {
        originalDomainEl.value = String(item.domain || "");
      }
      fillFormFromItem(item);
      if (modalTitleEl) {
        modalTitleEl.textContent = "Edit Host";
      }
      var m = getModal();
      if (m) {
        m.show();
      } else {
        showMessage("error", "Modal is not ready yet. Please retry in a moment.");
      }
    }

    function submitForm(evt) {
      evt.preventDefault();
      showFormError("");
      showMessage("", "");

      var payload = collectPayload();
      if (!payload.domain) {
        showFormError("Domain is required.");
        return;
      }

      var original = String(originalDomainEl && originalDomainEl.value || "").trim();
      var method = original ? "PUT" : "POST";
      if (original) {
        payload.original_domain = original;
      }

      setBusy(true);
      fetchJson(apiUrl, {
        method: method,
        credentials: "same-origin",
        cache: "no-store",
        headers: {
          "Accept": "application/json",
          "Content-Type": "application/json"
        },
        body: JSON.stringify(payload)
      })
        .then(function (res) {
          var body = res.json || {};
          if (!res.ok || !body.ok) {
            throw new Error(body.message || ("save failed (" + String(res.status) + ")"));
          }
          showMessage("success", body.message || (original ? "Host updated." : "Host added."));
          showRebootAlert(body);
          var m = getModal();
          if (m) {
            m.hide();
          }
          return loadHosts();
        })
        .catch(function (err) {
          showFormError(err && err.message ? err.message : "Save failed.");
        })
        .finally(function () {
          setBusy(false);
        });
    }

    function deleteHost(domain) {
      var d = String(domain || "").trim();
      if (!d) {
        return;
      }
      if (!window.confirm("Delete host '" + d + "'?")) {
        return;
      }
      showMessage("", "");
      setBusy(true);
      fetchJson(apiUrl + "?domain=" + encodeURIComponent(d), {
        method: "DELETE",
        credentials: "same-origin",
        cache: "no-store",
        headers: { "Accept": "application/json" }
      })
        .then(function (res) {
          var body = res.json || {};
          if (!res.ok || !body.ok) {
            throw new Error(body.message || ("delete failed (" + String(res.status) + ")"));
          }
          showMessage("success", body.message || "Host deleted.");
          return loadHosts();
        })
        .catch(function (err) {
          showMessage("error", err && err.message ? err.message : "Delete failed.");
        })
        .finally(function () {
          setBusy(false);
        });
    }

    rowsEl.addEventListener("click", function (evt) {
      var btn = evt.target instanceof Element ? evt.target.closest("[data-host-action]") : null;
      if (!btn) {
        return;
      }
      var action = String(btn.getAttribute("data-host-action") || "");
      var domain = String(btn.getAttribute("data-domain") || "");
      if (action === "edit") {
        openForEdit(domain);
      } else if (action === "delete") {
        deleteHost(domain);
      }
    });

    if (addBtn) {
      addBtn.addEventListener("click", openForAdd);
    }
    if (refreshBtn) {
      refreshBtn.addEventListener("click", function () {
        showMessage("", "");
        loadHosts();
      });
    }
    if (formEl) {
      formEl.addEventListener("submit", submitForm);
    }
    if (appTypeEl) {
      appTypeEl.addEventListener("change", syncFieldVisibility);
    }
    if (protocolEl) {
      protocolEl.addEventListener("change", syncFieldVisibility);
    }
    if (proxyRewriteEl) {
      proxyRewriteEl.addEventListener("change", syncFieldVisibility);
    }
    if (phpRuntimeIndexEl) {
      phpRuntimeIndexEl.addEventListener("change", syncCustomFieldVisibility);
    }
    if (nodeRuntimeIndexEl) {
      nodeRuntimeIndexEl.addEventListener("change", syncCustomFieldVisibility);
    }
    if (docRootIndexEl) {
      docRootIndexEl.addEventListener("change", syncCustomFieldVisibility);
    }

    syncFieldVisibility();
    loadFormOptions().finally(function () {
      loadHosts();
    });
  })();
</script>
