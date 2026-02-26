(() => {
  const $ = (id) => document.getElementById(id);

  let files = [];
  let activeFile = '';
  let activeLevel = '';
  let page = 1;
  let lastPages = 1;

  const BOOT = (window.LV_BOOT || { page: 'logs', domain: '' });
  const urlParams = new URLSearchParams(window.location.search || '');
  const Q_INIT = (urlParams.get('q') || '').trim();

  let activeDomain = (BOOT.domain || '').trim();

  // Live tail (SSE)
  let liveOn = false;
  let liveES = null;
  let liveHash = '';

  const THEME_KEY = 'lv_theme_mode'; // "auto" | "light" | "dark"

  function prefersDark() {
    return !!(window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches);
  }

  function applyTheme(mode) {
    let actual = mode;
    if (mode === 'auto') {
      actual = prefersDark() ? 'dark' : 'light';
    }
    document.documentElement.setAttribute('data-bs-theme', actual);
  }

  function getMode() { return localStorage.getItem(THEME_KEY) || 'auto'; }

  function setMode(mode) {
    localStorage.setItem(THEME_KEY, mode);
    syncThemeUI();
  }

  function syncThemeUI() {
    const mode = getMode();
    applyTheme(mode);

    const t = $('themeToggle');
    const l = $('themeLabel');
    if (!t || !l) {
      return;
    }

    if (mode === 'auto') {
      t.checked = prefersDark();
      l.textContent = 'Auto';
    } else if (mode === 'dark') {
      t.checked = true;
      l.textContent = 'Dark';
    } else {
      t.checked = false;
      l.textContent = 'Light';
    }
  }

  syncThemeUI();

  if (Q_INIT) {
    const qi = $('q');
    if (qi) {
      qi.value = Q_INIT;
    }
  }

  if (window.matchMedia) {
    window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', () => {
      if (getMode() === 'auto') {
        syncThemeUI();
      }
    });
  }

  $('themeToggle')?.addEventListener('change', (e) => {
    const checked = !!e.target.checked;
    setMode(checked ? 'dark' : 'light');
  });

  $('themeLabel')?.addEventListener('dblclick', () => setMode('auto'));

  function fmtBytes(n) {
    const u = ['B', 'KB', 'MB', 'GB'];
    let i = 0;
    while (n >= 1024 && i < u.length - 1) {
      n /= 1024;
      i++;
    }
    return (i === 0 ? n.toFixed(0) : n.toFixed(1)) + ' ' + u[i];
  }

  function fmtTime(ts) {
    if (!ts) {
      return '';
    }
    return new Date(ts * 1000).toLocaleString();
  }

  async function api(url, params = {}) {
    const u = new URL(url, location.origin);
    Object.entries(params).forEach(([k, v]) => u.searchParams.set(k, v));
    const r = await fetch(u.toString(), { cache: 'no-store' });
    return r.json();
  }

  function uniqServices(list) {
    const s = new Set(list.map((x) => x.service || 'logs'));
    return Array.from(s).sort();
  }

  function serviceDomainSupported(svc) {
    const v = String(svc || '').toLowerCase();
    return v === 'nginx' || v === 'apache' || v === 'php' || v === 'php-fpm' || v === 'phpfpm';
  }

  function extractDomainFromName(name) {
    let s = String(name || '');
    s = s.replace(/\.gz$/i, '');
    s = s.replace(/(\.access|\.error)\.log$/i, '');
    s = s.replace(/\.log$/i, '');
    s = s.replace(/([.-])\d{8}$/i, '');
    s = s.replace(/([.-])\d+$/i, '');
    const low = s.toLowerCase();
    if (!s || low === 'error' || low === 'access') {
      return '';
    }
    return s;
  }

  function buildDomainListForService(svc) {
    const set = new Set();
    for (const f of files) {
      if (String(f.service) !== String(svc)) {
        continue;
      }
      const d = extractDomainFromName(f.name);
      if (d) {
        set.add(d);
      }
    }
    return Array.from(set).sort((a, b) => a.localeCompare(b));
  }

  function syncDomainFilterUI() {
    const svc = $('serviceFilter')?.value || '';
    const domSel = $('domainFilter');
    if (!domSel) {
      return;
    }

    if (!svc || !serviceDomainSupported(svc)) {
      domSel.classList.add('d-none');
      domSel.value = '';
      return;
    }

    const domains = buildDomainListForService(svc);
    domSel.innerHTML =
      `<option value="">All Domains</option>` +
      domains.map((d) => `<option value="${String(d).replace(/"/g, '&quot;')}">${d}</option>`).join('');

    domSel.classList.remove('d-none');

    if (activeDomain && domains.includes(activeDomain)) {
      domSel.value = activeDomain;
    } else {
      domSel.value = '';
    }
  }

  function renderFiles(serviceFilter = '') {
    const list = $('fileList');
    list.innerHTML = '';

    const shown = files.filter((f) => {
      if (serviceFilter && f.service !== serviceFilter) {
        return false;
      }
      if (activeDomain) {
        const hay = (f.name + ' ' + f.path).toLowerCase();
        if (!hay.includes(activeDomain.toLowerCase())) {
          return false;
        }
      }
      return true;
    });

    for (const f of shown) {
      const div = document.createElement('div');
      div.className = 'lv-file' + (f.path === activeFile ? ' active' : '');
      div.innerHTML = `
        <div class="d-flex align-items-center justify-content-between">
          <div class="name">${f.name}</div>
          <div class="meta">${fmtBytes(f.size)}</div>
        </div>
        <div class="meta text-truncate">${f.path}</div>
        <div class="meta">mtime: ${fmtTime(f.mtime)}</div>
      `;
      div.addEventListener('click', () => {
        activeFile = f.path;
        page = 1;
        $('activeFile').textContent = f.path;
        $('btnRaw').href = '/api/raw?file=' + encodeURIComponent(activeFile);
        stopLive();
        renderFiles($('serviceFilter').value);
        loadEntries();
      });
      list.appendChild(div);
    }
  }

  async function loadFiles() {
    const j = await api('/api/files');
    files = j.files || [];

    const sv = $('serviceFilter');
    const curr = sv.value;

    sv.innerHTML = `<option value="">All Services</option>`;
    for (const s of uniqServices(files)) {
      const o = document.createElement('option');
      o.value = s;
      o.textContent = s;
      sv.appendChild(o);
    }

    if (activeDomain) {
      const services = uniqServices(files);
      let picked = '';
      for (const s of services) {
        const has = files.some((f) =>
          String(f.service) === String(s) &&
          (String(f.name) + ' ' + String(f.path)).toLowerCase().includes(activeDomain.toLowerCase()),
        );
        if (has) {
          picked = s;
          break;
        }
      }
      if (picked) {
        sv.value = picked;
      } else {
        sv.value = curr;
      }
    } else {
      sv.value = curr;
    }

    syncDomainFilterUI();
    renderFiles(sv.value);
  }

  function setCounts(meta) {
    const c = (meta && meta.counts) || { debug: 0, info: 0, warn: 0, error: 0 };
    $('cntDebug').textContent = c.debug ?? 0;
    $('cntInfo').textContent = c.info ?? 0;
    $('cntWarn').textContent = c.warn ?? 0;
    $('cntError').textContent = c.error ?? 0;
  }

  function badge(level) {
    return `<span class="lv-badge ${level}">${String(level).toUpperCase()}</span>`;
  }

  function escapeHtml(s) {
    return (s ?? '').replace(/[&<>"']/g, (c) => ({
      '&': '&amp;',
      '<': '&lt;',
      '>': '&gt;',
      '"': '&quot;',
      '\'': '&#039;',
    }[c]));
  }

  function escapeRegExp(s) { return String(s).replace(/[.*+?^${}()|[\]\\]/g, '\\$&'); }

  function highlight(text, q) {
    if (!q) {
      return escapeHtml(text);
    }
    const re = new RegExp(escapeRegExp(q), 'gi');
    return escapeHtml(text).replace(re, (m) => `<mark>${m}</mark>`);
  }

  function renderEntries(items, q) {
    const box = $('entries');
    box.innerHTML = '';

    let opened = null;

    for (const it of items) {
      const lvl = it.level || 'info';
      const ts = it.ts || '';
      const summary = it.summary || '';
      const body = it.body || '';

      const row = document.createElement('div');
      row.className = 'lv-entry';
      row.innerHTML = `
        <div class="d-flex align-items-center gap-2">
          ${badge(lvl)}
          <div class="lv-muted small">${ts ? escapeHtml(ts) : '—'}</div>
          <div class="flex-grow-1">${highlight(summary, q)}</div>
          <button class="btn btn-sm lv-btn ms-auto" data-act="toggle">Details</button>
        </div>
        <div class="d-none" data-act="panel">
          <pre class="lv-pre">${highlight(body, q)}</pre>
        </div>
      `;

      row.querySelector('[data-act="toggle"]').addEventListener('click', () => {
        const p = row.querySelector('[data-act="panel"]');

        // single accordion open
        if (opened && opened !== p) {
          opened.classList.add('d-none');
        }
        p.classList.toggle('d-none');
        opened = p.classList.contains('d-none') ? null : p;
      });

      box.appendChild(row);
    }
  }

  function updatePagerButtons() {
    const prev = $('prevPage');
    const next = $('nextPage');
    if (prev) {
      prev.disabled = page <= 1;
    }
    if (next) {
      next.disabled = page >= lastPages;
    }
  }

  async function loadEntries() {
    if (!activeFile) {
      return;
    }

    const per = $('perPage').value || '25';
    const q = ($('q').value || '').trim();

    const j = await api('/api/entries', {
      file: activeFile,
      page: String(page),
      per,
      level: activeLevel,
      q,
    });

    if (!j.ok) {
      return;
    }

    setCounts(j.meta);
    renderEntries(j.items || [], q);

    lastPages = Math.max(1, j.pages || 1);
    page = Math.max(1, Math.min(page, lastPages));

    $('pageInfo').textContent = `${j.page} / ${j.pages}`;
    $('stats').textContent = `Total: ${j.total} · Cached: ${new Date((j.meta.generated_at || 0) * 1000).toLocaleTimeString()}`;

    updatePagerButtons();
  }

  function stopLive() {
    liveOn = false;
    liveHash = '';
    if (liveES) {
      try { liveES.close(); } catch {}
      liveES = null;
    }
  }

  function startLive() {
    if (!activeFile) {
      return;
    }
    stopLive();
    liveOn = true;

    const u = new URL('/api/tail', location.origin);
    u.searchParams.set('file', activeFile);
    u.searchParams.set('lines', '400');
    u.searchParams.set('intervalMs', '900');

    liveES = new EventSource(u.toString());
    liveES.addEventListener('tail', (ev) => {
      try {
        const j = JSON.parse(ev.data || '{}');
        if (!j.ok) {
          return;
        }
        if (j.hash && j.hash === liveHash) {
          return;
        }
        liveHash = j.hash || '';
        // Render raw tail as a single "entry" style (simple but useful)
        $('entries').innerHTML = `
          <div class="lv-entry">
            <div class="d-flex align-items-center gap-2">
              <span class="lv-badge info">LIVE</span>
              <div class="lv-muted small">${new Date((j.ts || 0) * 1000).toLocaleTimeString()}</div>
              <div class="flex-grow-1">Live tail snapshot</div>
              <button class="btn btn-sm lv-btn ms-auto" id="btnLiveStop">Stop</button>
            </div>
            <div>
              <pre class="lv-pre">${escapeHtml(j.text || '')}</pre>
            </div>
          </div>
        `;
        $('btnLiveStop')?.addEventListener('click', () => {
          stopLive();
          loadEntries();
        });
      } catch {}
    });

    liveES.addEventListener('error', () => {
      // keep silent (dev-only)
    });
  }

  $('btnRefreshFiles')?.addEventListener('click', loadFiles);

  $('serviceFilter')?.addEventListener('change', () => {
    const svc = $('serviceFilter').value;

    syncDomainFilterUI();

    if (!svc || !serviceDomainSupported(svc)) {
      activeDomain = '';
      $('domainFilter') && ($('domainFilter').value = '');
    } else {
      const domains = buildDomainListForService(svc);
      if (activeDomain && !domains.includes(activeDomain)) {
        activeDomain = '';
        $('domainFilter') && ($('domainFilter').value = '');
      }
    }

    renderFiles(svc);
  });

  $('domainFilter')?.addEventListener('change', () => {
    activeDomain = $('domainFilter').value || '';
    renderFiles($('serviceFilter').value);
  });

  $('perPage')?.addEventListener('change', () => {
    page = 1;
    stopLive();
    loadEntries();
  });

  $('btnSearch')?.addEventListener('click', () => {
    page = 1;
    stopLive();
    loadEntries();
  });
  $('q')?.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') {
      page = 1;
      stopLive();
      loadEntries();
    }
  });

  $('prevPage')?.addEventListener('click', () => {
    if (page > 1) {
      page--;
      stopLive();
      loadEntries();
    }
  });

  $('nextPage')?.addEventListener('click', () => {
    if (page < lastPages) {
      page++;
      stopLive();
      loadEntries();
    }
  });

  document.querySelectorAll('#levelPills [data-level]').forEach((btn) => {
    btn.addEventListener('click', () => {
      const lvl = btn.getAttribute('data-level');
      activeLevel = activeLevel === lvl ? "" : lvl;
      page = 1;
      stopLive();
      loadEntries();
    });
  });

  // Quick dev shortcut: press "L" to toggle live mode
  document.addEventListener("keydown", (e) => {
    if (e.key.toLowerCase() === "l" && activeFile) {
      liveOn ? (stopLive(), loadEntries()) : startLive();
    }
  });

  loadFiles();
})();