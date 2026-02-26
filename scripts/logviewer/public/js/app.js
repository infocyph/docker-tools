(() => {
  const $ = (id) => document.getElementById(id);

  let files = [];
  let activeFile = "";
  let activeLevel = "";
  let page = 1;

  const BOOT = (window.LV_BOOT || { page: "logs", domain: "" });
  const DOMAIN_FILTER = (BOOT.domain || "").trim();
  const urlParams = new URLSearchParams(window.location.search || "");
  const Q_INIT = (urlParams.get("q") || "").trim();

  // ───────────────────────────────────────────────────────────────────────────
  // Theme (Toggle): default Auto(System), user can force Light/Dark
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

  if (Q_INIT) {
    const qi = $("q");
    if (qi) qi.value = Q_INIT;
  }

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

  // ───────────────────────────────────────────────────────────────────────────

  function fmtBytes(n) {
    const u = ["B", "KB", "MB", "GB"];
    let i = 0;
    while (n >= 1024 && i < u.length - 1) {
      n /= 1024;
      i++;
    }
    return (i === 0 ? n.toFixed(0) : n.toFixed(1)) + " " + u[i];
  }

  function fmtTime(ts) {
    if (!ts) return "";
    return new Date(ts * 1000).toLocaleString();
  }

  async function api(url, params = {}) {
    const u = new URL(url, location.origin);
    Object.entries(params).forEach(([k, v]) => u.searchParams.set(k, v));
    const r = await fetch(u.toString(), { cache: "no-store" });
    return r.json();
  }

  function uniqServices(list) {
    const s = new Set(list.map((x) => x.service || "logs"));
    return Array.from(s).sort();
  }

  function renderFiles(serviceFilter = "") {
    const list = $("fileList");
    list.innerHTML = "";

    const shown = files.filter((f) => {
      if (serviceFilter && f.service !== serviceFilter) return false;
      if (DOMAIN_FILTER) {
        const hay = (f.name + " " + f.path).toLowerCase();
        if (!hay.includes(DOMAIN_FILTER.toLowerCase())) return false;
      }
      return true;
    });

    for (const f of shown) {
      const div = document.createElement("div");
      div.className = "lv-file" + (f.path === activeFile ? " active" : "");
      div.innerHTML = `
        <div class="d-flex align-items-center justify-content-between">
          <div class="name">${f.name}</div>
          <div class="meta">${fmtBytes(f.size)}</div>
        </div>
        <div class="meta text-truncate">${f.path}</div>
        <div class="meta">mtime: ${fmtTime(f.mtime)}</div>
      `;
      div.addEventListener("click", () => {
        activeFile = f.path;
        page = 1;
        $("activeFile").textContent = f.path;
        $("btnRaw").href = "/api/raw?file=" + encodeURIComponent(activeFile);
        renderFiles($("serviceFilter").value);
        loadEntries();
      });
      list.appendChild(div);
    }
  }

  async function loadFiles() {
    const j = await api("/api/files");
    files = j.files || [];

    const sv = $("serviceFilter");
    const curr = sv.value;
    sv.innerHTML = `<option value="">All Services</option>`;
    for (const s of uniqServices(files)) {
      const o = document.createElement("option");
      o.value = s;
      o.textContent = s;
      sv.appendChild(o);
    }
    sv.value = curr;

    renderFiles(curr);
  }

  function setCounts(meta) {
    const c = (meta && meta.counts) || { debug: 0, info: 0, warn: 0, error: 0 };
    $("cntDebug").textContent = c.debug ?? 0;
    $("cntInfo").textContent = c.info ?? 0;
    $("cntWarn").textContent = c.warn ?? 0;
    $("cntError").textContent = c.error ?? 0;
  }

  function badge(level) {
    return `<span class="lv-badge ${level}">${String(level).toUpperCase()}</span>`;
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

  function renderEntries(items) {
    const box = $("entries");
    box.innerHTML = "";

    for (const it of items) {
      const lvl = it.level || "info";
      const ts = it.ts || "";
      const summary = it.summary || "";
      const body = it.body || "";

      const row = document.createElement("div");
      row.className = "lv-entry";
      row.innerHTML = `
        <div class="d-flex align-items-center gap-2">
          ${badge(lvl)}
          <div class="lv-muted small">${ts ? ts : "—"}</div>
          <div class="flex-grow-1">${escapeHtml(summary)}</div>
          <button class="btn btn-sm lv-btn ms-auto" data-act="toggle">Details</button>
        </div>
        <div class="d-none" data-act="panel">
          <pre class="lv-pre">${escapeHtml(body)}</pre>
        </div>
      `;

      row.querySelector('[data-act="toggle"]').addEventListener("click", () => {
        const p = row.querySelector('[data-act="panel"]');
        p.classList.toggle("d-none");
      });

      box.appendChild(row);
    }
  }

  async function loadEntries() {
    if (!activeFile) return;

    const per = $("perPage").value || "25";
    const q = ($("q").value || "").trim();

    const j = await api("/api/entries", {
      file: activeFile,
      page: String(page),
      per,
      level: activeLevel,
      q,
    });

    if (!j.ok) return;

    setCounts(j.meta);
    renderEntries(j.items || []);

    $("pageInfo").textContent = `${j.page} / ${j.pages}`;
    $("stats").textContent =
      `Total: ${j.total} · Cached: ${new Date((j.meta.generated_at || 0) * 1000).toLocaleTimeString()}`;
  }

  $("btnRefreshFiles").addEventListener("click", loadFiles);
  $("serviceFilter").addEventListener("change", () => renderFiles($("serviceFilter").value));
  $("perPage").addEventListener("change", () => { page = 1; loadEntries(); });

  $("btnSearch").addEventListener("click", () => { page = 1; loadEntries(); });
  $("q").addEventListener("keydown", (e) => {
    if (e.key === "Enter") { page = 1; loadEntries(); }
  });

  $("prevPage").addEventListener("click", () => { if (page > 1) { page--; loadEntries(); } });
  $("nextPage").addEventListener("click", () => { page++; loadEntries(); });

  document.querySelectorAll("#levelPills [data-level]").forEach((btn) => {
    btn.addEventListener("click", () => {
      const lvl = btn.getAttribute("data-level");
      activeLevel = activeLevel === lvl ? "" : lvl;
      page = 1;
      loadEntries();
    });
  });

  loadFiles();
})();