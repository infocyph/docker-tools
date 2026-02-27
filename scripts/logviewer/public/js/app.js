(() => {
  const $ = (id) => document.getElementById(id);

  let files = [];
  let activeFile = "";
  let activeLevel = "";
  let page = 1;
  let lastPages = 1;

  let liveOn = false;
  let liveES = null;
  let liveHash = "";

  const BOOT = (window.LV_BOOT || { page: "logs", domain: "" });
  const urlParams = new URLSearchParams(window.location.search || "");
  const Q_INIT = (urlParams.get("q") || "").trim();

  let activeDomain = (BOOT.domain || "").trim();

  const THEME_KEY = "lv_theme_mode"; // "auto" | "light" | "dark"

  function prefersDark() {
    return !!(window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)").matches);
  }

  function applyTheme(mode) {
    let actual = mode;
    if (mode === "auto") actual = prefersDark() ? "dark" : "light";
    document.documentElement.setAttribute("data-bs-theme", actual);
  }

  function getMode() {
    return localStorage.getItem(THEME_KEY) || "auto";
  }

  function setMode(mode) {
    localStorage.setItem(THEME_KEY, mode);
    syncThemeUI();
  }

  function syncThemeUI() {
    const mode = getMode();
    applyTheme(mode);

    const t = $("themeToggle");
    const l = $("themeLabel");
    if (!t || !l) return;

    if (mode === "auto") {
      t.checked = prefersDark();
      l.textContent = "Auto";
    } else if (mode === "dark") {
      t.checked = true;
      l.textContent = "Dark";
    } else {
      t.checked = false;
      l.textContent = "Light";
    }
  }

  syncThemeUI();

  if (window.matchMedia) {
    window.matchMedia("(prefers-color-scheme: dark)").addEventListener("change", () => {
      if (getMode() === "auto") syncThemeUI();
    });
  }

  $("themeToggle")?.addEventListener("change", (e) => {
    const checked = !!e.target.checked;
    setMode(checked ? "dark" : "light");
  });

  $("themeLabel")?.addEventListener("dblclick", () => setMode("auto"));

  if (Q_INIT) {
    const qi = $("q");
    if (qi) qi.value = Q_INIT;
  }

  function escapeHtml(s) {
    return (s ?? "").replace(/[&<>"']/g, (c) => ({
      "&": "&amp;",
      "<": "&lt;",
      ">": "&gt;",
      '"': "&quot;",
      "'": "&#039;",
    }[c]));
  }

  function fmtBytes(n) {
    n = Number(n || 0);
    const u = ["B", "KB", "MB", "GB"];
    let i = 0;
    while (n >= 1024 && i < u.length - 1) { n /= 1024; i++; }
    return (i === 0 ? n.toFixed(0) : n.toFixed(1)) + " " + u[i];
  }

  function fmtTime(ts) {
    if (!ts) return "—";
    return new Date(ts * 1000).toLocaleString();
  }

  async function api(url, params = {}) {
    const u = new URL(url, location.origin);
    Object.entries(params).forEach(([k, v]) => u.searchParams.set(k, v));
    const r = await fetch(u.toString(), { cache: "no-store" });
    return r.json();
  }

  function uniqServices(list) {
    const s = new Set();
    for (const x of (list || [])) {
      const v = (x && x.service) ? String(x.service) : "logs";
      if (v) s.add(v);
    }
    return Array.from(s).sort((a, b) => a.localeCompare(b));
  }

  function serviceDomainSupported(svc) {
    const v = String(svc || "").toLowerCase();
    return v === "nginx" || v === "apache" || v === "php" || v === "php-fpm" || v === "phpfpm";
  }

  function looksLikeTemplateToken(s) {
    s = String(s || "");
    if (!s) return true;
    if (s.includes("{{") || s.includes("}}")) return true;
    if (s.includes("$")) return true;
    return false;
  }

  function extractDomainFromName(name) {
    let s = String(name || "");

    s = s.replace(/\.gz$/i, "");
    s = s.replace(/(\.access|\.error)\.log$/i, "");
    s = s.replace(/\.log$/i, "");
    s = s.replace(/([.-])\d{8}$/i, "");
    s = s.replace(/([.-])\d+$/i, "");
    s = s.trim();

    const low = s.toLowerCase();
    if (!s || low === "error" || low === "access") return "";
    if (looksLikeTemplateToken(s)) return "";
    return s;
  }

  function buildDomainListForService(svc) {
    const set = new Set();
    for (const f of files) {
      if (String(f.service) !== String(svc)) continue;
      const d = extractDomainFromName(f.name);
      if (d) set.add(d);
    }
    return Array.from(set).sort((a, b) => a.localeCompare(b));
  }

  function syncDomainFilterUI() {
    const svc = $("serviceFilter")?.value || "";
    const domSel = $("domainFilter");
    if (!domSel) return;

    if (!svc || !serviceDomainSupported(svc)) {
      domSel.classList.add("d-none");
      domSel.value = "";
      return;
    }

    const domains = buildDomainListForService(svc);
    domSel.innerHTML =
      `<option value="">All Domains</option>` +
      domains.map((d) => `<option value="${escapeHtml(d)}">${escapeHtml(d)}</option>`).join("");

    domSel.classList.remove("d-none");

    if (activeDomain && domains.includes(activeDomain)) domSel.value = activeDomain;
    else domSel.value = "";
  }

  function setLiveState(on) {
    liveOn = !!on;
    const btn = $("btnLive");
    if (!btn) return;
    btn.textContent = liveOn ? "Stop Live" : "Live";
    btn.classList.toggle("btn-danger", liveOn);
  }

  function stopLive() {
    if (liveES) {
      try { liveES.close(); } catch (e) {}
      liveES = null;
    }
    liveHash = "";
    setLiveState(false);
  }

  function startLive() {
    if (!activeFile) return;

    stopLive();
    setLiveState(true);

    const u = new URL("/api/tail", location.origin);
    u.searchParams.set("file", activeFile);
    u.searchParams.set("lines", "400");
    u.searchParams.set("intervalMs", "900");

    liveES = new EventSource(u.toString());

    liveES.addEventListener("tail", (ev) => {
      const j = JSON.parse(ev.data || "{}");
      if (!j.ok) return;
      if (j.hash && j.hash === liveHash) return;
      liveHash = j.hash || "";

      const box = $("entries");
      if (!box) return;
      box.innerHTML =
        `<div class="lv-entry">
          <div class="d-flex align-items-center gap-2">
            <span class="lv-badge info">LIVE</span>
            <div class="lv-muted small">${new Date((j.ts || 0) * 1000).toLocaleTimeString()}</div>
            <div class="ms-auto lv-muted small">auto-updating</div>
          </div>
          <pre class="lv-pre">${escapeHtml(j.text || "")}</pre>
        </div>`;
    });

    liveES.addEventListener("error", () => {
      stopLive();
    });
  }

  $("btnLive")?.addEventListener("click", () => {
    liveOn ? stopLive() : startLive();
  });

  window.addEventListener("beforeunload", stopLive);

  function renderFileCaps(meta) {
    const caps = $("fileCaps");
    if (!caps) return;

    const size = meta?.size ?? 0;
    const mtime = meta?.mtime ?? 0;
    const total = meta?.total ?? 0;
    const c = meta?.counts || { debug: 0, info: 0, warn: 0, error: 0 };

    caps.innerHTML = `
      <span class="lv-cap"><span class="k">Size</span><span class="v">${fmtBytes(size)}</span></span>
      <span class="lv-cap"><span class="k">Logs</span><span class="v">${Number(total || 0)}</span></span>
      <span class="lv-cap"><span class="k">Updated</span><span class="v">${escapeHtml(fmtTime(mtime))}</span></span>
      <span class="lv-cap"><span class="k">Err</span><span class="v">${Number(c.error || 0)}</span></span>
      <span class="lv-cap"><span class="k">Warn</span><span class="v">${Number(c.warn || 0)}</span></span>
    `;
  }

  function setPaginationUI() {
    const prev = $("prevPage");
    const next = $("nextPage");
    if (prev) prev.disabled = page <= 1;
    if (next) next.disabled = page >= lastPages;
    const pi = $("pageInfo");
    if (pi) pi.textContent = `${page} / ${lastPages}`;
  }

  function renderFiles(serviceFilter = "") {
    const list = $("fileList");
    if (!list) return;
    list.innerHTML = "";

    const shown = files.filter((f) => {
      if (serviceFilter && f.service !== serviceFilter) return false;

      if (activeDomain) {
        const hay = (String(f.name) + " " + String(f.path)).toLowerCase();
        if (!hay.includes(activeDomain.toLowerCase())) return false;
      }
      return true;
    });

    for (const f of shown) {
      const div = document.createElement("div");
      div.className = "lv-file" + (f.path === activeFile ? " active" : "");
      div.innerHTML = `
        <div class="d-flex align-items-center justify-content-between">
          <div class="name">${escapeHtml(f.name)}</div>
          <div class="meta">${fmtBytes(f.size)}</div>
        </div>
        <div class="meta text-truncate">${escapeHtml(f.path)}</div>
        <div class="meta">mtime: ${escapeHtml(fmtTime(f.mtime))}</div>
      `;
      div.addEventListener("click", () => {
        stopLive();
        activeFile = f.path;
        page = 1;
        lastPages = 1;
        $("activeFile").textContent = f.path;
        $("btnRaw").href = "/api/raw?file=" + encodeURIComponent(activeFile);
        renderFiles($("serviceFilter").value);
        loadEntries();
      });
      list.appendChild(div);
    }
  }

  async function loadFiles() {
    stopLive();

    const j = await api("/api/files");
    files = j.files || [];

    const sv = $("serviceFilter");
    if (!sv) return;
    const curr = sv.value || "";

    sv.innerHTML = `<option value="">All Services</option>`;
    for (const s of uniqServices(files)) {
      const o = document.createElement("option");
      o.value = s;
      o.textContent = s;
      sv.appendChild(o);
    }

    if (activeDomain) {
      const services = uniqServices(files);
      let picked = "";
      for (const s of services) {
        const has = files.some((f) =>
          String(f.service) === String(s) &&
          (String(f.name) + " " + String(f.path)).toLowerCase().includes(activeDomain.toLowerCase())
        );
        if (has) { picked = s; break; }
      }
      sv.value = picked || curr;
    } else {
      sv.value = curr;
    }

    syncDomainFilterUI();
    renderFiles(sv.value);

    if (activeFile && !files.some(f => String(f.path) === String(activeFile))) {
      activeFile = "";
      $("activeFile").textContent = "—";
      $("entries").innerHTML = "";
      $("stats").textContent = "—";
      $("fileCaps").innerHTML = "";
      page = 1;
      lastPages = 1;
      setPaginationUI();
    }
  }

  function badge(level) {
    const lvl = String(level || "info");
    return `<span class="lv-badge ${lvl}">${escapeHtml(lvl.toUpperCase())}</span>`;
  }

  function renderEntries(items) {
    const box = $("entries");
    if (!box) return;
    box.innerHTML = "";

    for (const it of (items || [])) {
      const lvl = it.level || "info";
      const ts = it.ts || "";
      const summary = it.summary || "";
      const body = it.body || "";

      const row = document.createElement("div");
      row.className = "lv-entry";
      row.innerHTML = `
        <div class="d-flex align-items-center gap-2">
          ${badge(lvl)}
          <div class="lv-muted small">${escapeHtml(ts || "—")}</div>
          <div class="flex-grow-1">${escapeHtml(summary)}</div>
          <button class="btn btn-sm lv-btn ms-auto" data-act="toggle">Details</button>
        </div>
        <div class="d-none" data-act="panel">
          <pre class="lv-pre">${escapeHtml(body)}</pre>
        </div>
      `;

      row.querySelector('[data-act="toggle"]').addEventListener("click", (e) => {
        e.preventDefault();
        e.stopPropagation();
        const p = row.querySelector('[data-act="panel"]');
        p.classList.toggle("d-none");
      });

      box.appendChild(row);
    }
  }

  async function loadEntries() {
    stopLive();
    if (!activeFile) return;

    const per = $("perPage")?.value || "25";
    const q = ($("q")?.value || "").trim();

    const j = await api("/api/entries", {
      file: activeFile,
      page: String(page),
      per,
      level: activeLevel,
      q,
    });

    if (!j.ok) return;

    lastPages = Number(j.pages || 1);
    page = Number(j.page || 1);

    renderFileCaps(j.meta);
    renderEntries(j.items || []);

    $("stats").textContent =
      `Total: ${j.total} · Cached: ${new Date((j.meta?.generated_at || 0) * 1000).toLocaleTimeString()}`;

    setPaginationUI();
  }

  $("btnRefreshFiles")?.addEventListener("click", loadFiles);

  $("serviceFilter")?.addEventListener("change", () => {
    stopLive();
    page = 1;
    lastPages = 1;

    const svc = $("serviceFilter").value;

    syncDomainFilterUI();

    if (!svc || !serviceDomainSupported(svc)) {
      activeDomain = "";
      $("domainFilter") && ($("domainFilter").value = "");
    } else {
      const domains = buildDomainListForService(svc);
      if (activeDomain && !domains.includes(activeDomain)) {
        activeDomain = "";
        $("domainFilter") && ($("domainFilter").value = "");
      }
    }

    renderFiles(svc);
    setPaginationUI();
  });

  $("domainFilter")?.addEventListener("change", () => {
    stopLive();
    page = 1;
    lastPages = 1;
    activeDomain = $("domainFilter").value || "";
    renderFiles($("serviceFilter").value);
    setPaginationUI();
  });

  $("perPage")?.addEventListener("change", () => { page = 1; loadEntries(); });
  $("btnSearch")?.addEventListener("click", () => { page = 1; loadEntries(); });

  $("q")?.addEventListener("keydown", (e) => {
    if (e.key === "Enter") { page = 1; loadEntries(); }
  });

  $("prevPage")?.addEventListener("click", () => {
    if (page > 1) { page--; loadEntries(); }
  });

  $("nextPage")?.addEventListener("click", () => {
    if (page < lastPages) { page++; loadEntries(); }
  });

  loadFiles();
})();