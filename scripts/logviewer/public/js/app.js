(() => {
  const $ = (id) => document.getElementById(id);

  let files = [];
  let activeFile = "";
  let activeLevel = "";
  let page = 1;
  let lastPages = 1;

  const BOOT = (window.LV_BOOT || { page: "logs", domain: "" });

  // Live mode removed; keep legacy hook as a no-op to avoid runtime errors.
  const ensureNotLive = () => {};
  const urlParams = new URLSearchParams(window.location.search || "");
  const Q_INIT = (urlParams.get("q") || "").trim();

  let activeDomain = (BOOT.domain || "").trim();

  const THEME_KEY = "lv_theme_mode"; // "auto" | "light" | "dark"
  const SEARCH_MODE_KEY = "lv_search_mode"; // "tail" | "file"
  const PIN_KEY = "lv_pins";
  const RECENT_KEY = "lv_recent";

  function prefersDark() {
    return !!(window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)").matches);
  }

  function applyTheme(mode) {
    let actual = mode;
    if (mode === "auto") actual = prefersDark() ? "dark" : "light";
    document.documentElement.setAttribute("data-bs-theme", actual);
  }

  function getMode() { return localStorage.getItem(THEME_KEY) || "auto"; }
  function setMode(mode) { localStorage.setItem(THEME_KEY, mode); syncThemeUI(); }

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

  function getSearchMode() {
    return localStorage.getItem(SEARCH_MODE_KEY) || "tail";
  }
  function setSearchMode(mode) {
    localStorage.setItem(SEARCH_MODE_KEY, mode === "file" ? "file" : "tail");
    const sm = $("searchMode");
    if (sm) sm.value = getSearchMode();
  }

  const smEl = $("searchMode");
  if (smEl) {
    smEl.value = getSearchMode();
    smEl.addEventListener("change", () => setSearchMode(smEl.value));
  }

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

    // normalize gzip + rotations
    s = s.replace(/\.gz$/i, "");
    // common access/error endings
    s = s.replace(/(\.access|\.error)\.log$/i, "");
    s = s.replace(/(\.access|\.error)$/i, "");
    s = s.replace(/\.log$/i, "");
    // strip rotation suffixes: -20260228, .20260228, -123, etc.
    s = s.replace(/([.-])\d{8,14}$/i, "");
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

  function getPins() {
    try { return JSON.parse(localStorage.getItem(PIN_KEY) || "[]") || []; } catch { return []; }
  }
  function setPins(arr) {
    localStorage.setItem(PIN_KEY, JSON.stringify(arr.slice(0, 50)));
  }
  function isPinned(path) {
    return getPins().includes(String(path));
  }
  function togglePin(path) {
    const p = String(path);
    const pins = getPins();
    const i = pins.indexOf(p);
    if (i >= 0) pins.splice(i, 1); else pins.unshift(p);
    setPins(pins);
    renderFiles($("serviceFilter")?.value || "");
  }

  function getRecent() {
    try { return JSON.parse(localStorage.getItem(RECENT_KEY) || "[]") || []; } catch { return []; }
  }
  function bumpRecent(path) {
    const p = String(path);
    let r = getRecent().filter(x => String(x) !== p);
    r.unshift(p);
    r = r.slice(0, 15);
    localStorage.setItem(RECENT_KEY, JSON.stringify(r));
  }

  function openFile(path) {
    ensureNotLive();
    activeFile = String(path);
    page = 1;
    lastPages = 1;
    $("activeFile").textContent = activeFile;
    $("btnRaw").href = "/api/raw?file=" + encodeURIComponent(activeFile);
    bumpRecent(activeFile);
    renderFiles($("serviceFilter")?.value || "");
    loadEntries();
  }

  function renderFiles(serviceFilter = "") {
    const list = $("fileList");
    if (!list) return;
    list.innerHTML = "";

    const shown = files.filter((f) => {
      if (serviceFilter && f.service !== serviceFilter) return false;
      if (activeDomain) {
        const hay = (String(f.name) + " " + String(f.display_path || f.path)).toLowerCase();
        if (!hay.includes(activeDomain.toLowerCase())) return false;
      }
      return true;
    });

    const pins = new Set(getPins());
    const pinned = [];
    const normal = [];
    for (const f of shown) {
      if (pins.has(String(f.path))) pinned.push(f);
      else normal.push(f);
    }

    const recentSet = new Set(getRecent());

    const renderSection = (title) => {
      const sec = document.createElement("div");
      sec.className = "lv-file-section";
      sec.textContent = title;
      list.appendChild(sec);
    };

    const renderFile = (f) => {
      const div = document.createElement("div");
      div.className = "lv-file" + (String(f.path) === String(activeFile) ? " active" : "");

      const pinOn = isPinned(f.path);
      const isRecent = recentSet.has(String(f.path));

      div.innerHTML = `
        <div class="d-flex align-items-center justify-content-between gap-2">
          <div class="name text-truncate" style="max-width: 70%">${escapeHtml(f.name)}</div>
          <div class="d-flex align-items-center gap-2">
            ${isRecent ? `<span class="badge text-bg-secondary">recent</span>` : ``}
            <button class="lv-pin ${pinOn ? "on" : ""}" data-act="pin" title="Pin">★</button>
            <div class="meta">${fmtBytes(f.size)}</div>
          </div>
        </div>
        <div class="meta text-truncate">${escapeHtml(f.display_path || f.path)}</div>
        <div class="meta">mtime: ${escapeHtml(fmtTime(f.mtime))}</div>
      `;

      div.addEventListener("click", () => openFile(f.path));
      div.querySelector('[data-act="pin"]').addEventListener("click", (e) => {
        e.preventDefault(); e.stopPropagation();
        togglePin(f.path);
      });

      list.appendChild(div);
    };

    if (pinned.length) {
      renderSection("Pinned");
      pinned.forEach(renderFile);
      renderSection("All files");
    }
    normal.forEach(renderFile);
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

  function renderGrep(text) {
    const box = $("entries");
    if (!box) return;
    box.innerHTML = "";

    const lines = String(text || "").split("\n").filter(Boolean);
    if (!lines.length) {
      box.innerHTML = `<div class="lv-entry"><div class="lv-muted">No matches.</div></div>`;
      return;
    }

    for (const ln of lines) {
      const m = ln.match(/^(\d+):(.*)$/);
      const num = m ? m[1] : "";
      const body = m ? m[2] : ln;

      const row = document.createElement("div");
      row.className = "lv-entry";
      row.innerHTML = `
        <div class="d-flex align-items-center gap-2">
          ${badge("info")}
          <div class="lv-muted small">line ${escapeHtml(num || "—")}</div>
          <div class="flex-grow-1 text-truncate">${escapeHtml(body)}</div>
          <button class="btn btn-sm lv-btn ms-auto" data-act="toggle">Details</button>
        </div>
        <div class="d-none" data-act="panel">
          <pre class="lv-pre">${escapeHtml(body)}</pre>
        </div>
      `;
      row.querySelector('[data-act="toggle"]').addEventListener("click", (e) => {
        e.preventDefault(); e.stopPropagation();
        row.querySelector('[data-act="panel"]').classList.toggle("d-none");
      });
      box.appendChild(row);
    }
  }

  async function loadEntries() {
    ensureNotLive();
    if (!activeFile) return;

    const per = $("perPage")?.value || "25";
    const q = ($("q")?.value || "").trim();
    const mode = getSearchMode();

    if (q && mode === "file") {
      const j = await api("/api/grep", { file: activeFile, q, limit: "800" });

      if (!j.ok) {
        $("entries").innerHTML = `<div class="lv-entry"><div class="lv-muted">${escapeHtml(j.error || "Search failed")}</div></div>`;
        return;
      }

      $("stats").textContent = `File search: "${q}"`;
      renderFileCaps({ size: 0, mtime: 0, total: 0, counts: {error:0,warn:0,info:0,debug:0} });
      renderGrep(j.text || "");
      lastPages = 1;
      page = 1;
      setPaginationUI();
      return;
    }

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

  async function loadFiles() {
    ensureNotLive();

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


  async function refreshAll() {
    // Refresh file list + counts, then refresh current entries (if a file is selected).
    const prevFile = activeFile;
    const prevPage = page;

    await loadFiles();

    // If the previously selected file still exists, keep it selected and refresh entries.
    if (prevFile && files.some(f => String(f.path) === String(prevFile))) {
      activeFile = prevFile;
      page = prevPage || 1;
      await loadEntries();
      return;
    }

    // If a file is currently active (not cleared by loadFiles), refresh it.
    if (activeFile) {
      await loadEntries();
    }
  }

  $("btnRefreshFiles")?.addEventListener("click", loadFiles);

  $("serviceFilter")?.addEventListener("change", () => {
    ensureNotLive();
    page = 1; lastPages = 1;

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
    ensureNotLive();
    page = 1; lastPages = 1;
    activeDomain = $("domainFilter").value || "";
    renderFiles($("serviceFilter").value);
    setPaginationUI();
  });

  $("perPage")?.addEventListener("change", () => { ensureNotLive(); page = 1; loadEntries(); });
  $("btnSearch")?.addEventListener("click", () => { ensureNotLive(); page = 1; loadEntries(); });

  $("q")?.addEventListener("keydown", (e) => {
    if (e.key === "Enter") { ensureNotLive(); page = 1; loadEntries(); }
  });

  $("prevPage")?.addEventListener("click", () => {
    if (page > 1) { ensureNotLive(); page--; loadEntries(); }
  });

  $("nextPage")?.addEventListener("click", () => {
    if (page < lastPages) { ensureNotLive(); page++; loadEntries(); }
  });


  $("btnLive")?.addEventListener("click", () => {
    // Refresh everything: files + counts + (if selected) entries
    refreshAll();
  });

  loadFiles();
})();
