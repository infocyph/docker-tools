<?php
declare(strict_types=1);
?>

<section class="ap-page-head">
  <div>
    <p class="ap-breadcrumb mb-1">Home / Automation Manager</p>
    <h2 class="ap-page-title mb-1">Automation Manager</h2>
    <p class="ap-page-sub mb-0">Manage saved cron and supervisor configs.</p>
  </div>
  <div class="d-flex align-items-center gap-2 flex-wrap">
    <button id="amRefresh" class="btn ap-ghost-btn" type="button"><i class="bi bi-arrow-repeat me-1"></i>Refresh</button>
    <a class="btn btn-primary" href="<?= htmlspecialchars(($basePath ?? '') . '/automation-cron', ENT_QUOTES, 'UTF-8') ?>"><i class="bi bi-calendar-plus me-1"></i>Add Cron</a>
    <a class="btn btn-outline-primary" href="<?= htmlspecialchars(($basePath ?? '') . '/automation-supervisor', ENT_QUOTES, 'UTF-8') ?>"><i class="bi bi-cpu me-1"></i>Add Supervisor</a>
  </div>
</section>

<div id="amMsg" class="d-none mb-3"></div>

<section class="row g-3 mt-1">
  <div class="col-12">
    <article class="card ap-card">
      <header class="card-header ap-card-head ap-card-head-wrap">
        <div>
          <h4 class="ap-card-title mb-1"><i class="bi bi-list-ul me-1"></i>Saved Files</h4>
          <p id="amMeta" class="ap-card-sub mb-0">Updated: -</p>
        </div>
        <div class="d-flex align-items-center gap-2">
          <select id="amFilter" class="form-select form-select-sm" style="width: 160px;">
            <option value="all">All</option>
            <option value="cron">Cron</option>
            <option value="supervisor">Supervisor</option>
          </select>
        </div>
      </header>
      <div class="card-body">
        <div id="amSummary" class="ap-monitor-summary mb-3"></div>
        <div class="table-responsive">
          <table class="table ap-table mb-0">
            <thead><tr><th>Type</th><th>Name</th><th>Summary</th><th>Updated</th><th class="text-end">Actions</th></tr></thead>
            <tbody id="amRows"><tr><td colspan="5" class="text-center ap-page-sub py-4">Loading...</td></tr></tbody>
          </table>
        </div>
      </div>
    </article>
  </div>
</section>

<script>
(() => {
  "use strict";
  const base = (document.body?.getAttribute("data-ap-base") || "") === "/" ? "" : (document.body?.getAttribute("data-ap-base") || "");
  const API = base + "/api/automation-manager";
  const qs = (id) => document.getElementById(id);
  const esc = (v) => String(v ?? "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&#039;");
  const key = (k,n) => (String(k||"").toLowerCase()+"::"+String(n||""));
  const req = (u, o) => fetch(u, o || { method: "GET", credentials: "same-origin", cache: "no-store", headers: { Accept: "application/json" } }).then(r => r.json().catch(()=>({})).then(j => ({ ok:r.ok, status:r.status, body:j || {} })));
  const msg = (k, t) => {
    const n = qs("amMsg");
    if (!n) return;
    const s = String(t || "").trim();
    if (!s) {
      n.className = "d-none mb-3";
      n.textContent = "";
      return;
    }
    n.className = (k==="success"?"alert alert-success mb-3":k==="warning"?"alert alert-warning mb-3":"alert alert-danger mb-3");
    n.textContent = s;
  };

  let items = [];
  let map = Object.create(null);

  const render = () => {
    const rows = qs("amRows");
    if (!rows) return;
    const filter = String(qs("amFilter")?.value || "all");
    const data = filter === "all" ? items : items.filter((x) => x.kind === filter);
    if (!data.length) {
      rows.innerHTML = '<tr><td colspan="5" class="text-center ap-page-sub py-4">No files found.</td></tr>';
      return;
    }
    rows.innerHTML = data.map((it) =>
      `<tr><td><span class="badge ${it.kind==="supervisor"?"text-bg-primary":"text-bg-secondary"}">${esc(it.kind)}</span></td><td>${esc(it.name)}</td><td>${esc(it.summary)}</td><td>${esc(it.updated_at)}</td><td class="text-end"><button class="btn btn-sm btn-outline-primary me-1" data-act="edit" data-kind="${esc(it.kind)}" data-name="${esc(it.name)}"><i class="bi bi-pencil-square"></i></button><button class="btn btn-sm btn-outline-danger" data-act="del" data-kind="${esc(it.kind)}" data-name="${esc(it.name)}"><i class="bi bi-trash"></i></button></td></tr>`
    ).join("");
  };

  const list = () => req(API).then((r) => {
    if (!r.ok || !r.body.ok) throw new Error(r.body.message || `Load failed (${r.status})`);
    items = [];
    map = Object.create(null);
    ["cron", "supervisor"].forEach((kind) => {
      (r.body.items?.[kind] || []).forEach((x) => {
        const item = { kind, name: String(x.name || ""), summary: String(x.summary || "-"), updated_at: String(x.updated_at || "-") };
        if (!item.name) return;
        items.push(item);
        map[key(kind, item.name)] = item;
      });
    });
    items.sort((a, b) => key(a.kind, a.name).localeCompare(key(b.kind, b.name)));
    const s = r.body.summary || {};
    const w = r.body.writable || {};
    const summary = qs("amSummary");
    if (summary) {
      summary.innerHTML = `<span class="ap-kv-group ap-live-state-info"><span class="ap-kv-group-key">Cron</span><span class="ap-kv-group-val">${esc(s.cron||0)}</span></span>
<span class="ap-kv-group ap-live-state-info"><span class="ap-kv-group-key">Supervisor</span><span class="ap-kv-group-val">${esc(s.supervisor||0)}</span></span>
<span class="ap-kv-group ap-live-state-info"><span class="ap-kv-group-key">Cron Writable</span><span class="ap-kv-group-val">${esc(w.cron?"Yes":"No")}</span></span>
<span class="ap-kv-group ap-live-state-info"><span class="ap-kv-group-key">Supervisor Writable</span><span class="ap-kv-group-val">${esc(w.supervisor?"Yes":"No")}</span></span>`;
    }
    const meta = qs("amMeta");
    if (meta) meta.textContent = `Updated: ${r.body.generated_at || "-"}`;
    render();
  }).catch((e) => {
    const rows = qs("amRows");
    if (rows) rows.innerHTML = '<tr><td colspan="5" class="text-center text-danger py-4">Failed to load.</td></tr>';
    msg("error", e.message || "Failed to load.");
  });

  const del = (kind, name) => req(`${API}?kind=${encodeURIComponent(kind)}&name=${encodeURIComponent(name)}`, {
    method: "DELETE",
    credentials: "same-origin",
    cache: "no-store",
    headers: { Accept: "application/json" }
  }).then((r) => {
    if (!r.ok || !r.body.ok) throw new Error(r.body.message || `Delete failed (${r.status})`);
    msg("success", String(r.body.message || "Deleted."));
    return list();
  });

  qs("amRows")?.addEventListener("click", (e) => {
    const btn = e.target instanceof Element ? e.target.closest("[data-act]") : null;
    if (!btn) return;
    const action = String(btn.getAttribute("data-act") || "");
    const kind = String(btn.getAttribute("data-kind") || "");
    const name = String(btn.getAttribute("data-name") || "");
    if (!kind || !name) return;
    if (action === "edit") {
      const target = kind === "cron" ? "/automation-cron" : "/automation-supervisor";
      window.location.href = `${base}${target}?name=${encodeURIComponent(name)}`;
      return;
    }
    if (action === "del") {
      if (!window.confirm(`Delete ${kind} config '${name}'?`)) return;
      msg("", "");
      del(kind, name).catch((x) => msg("error", x.message || "Delete failed."));
    }
  });

  qs("amFilter")?.addEventListener("change", render);
  qs("amRefresh")?.addEventListener("click", () => { msg("", ""); list(); });

  list();
})();
</script>
