(() => {
  const $ = (id) => document.getElementById(id);

  let files = [];
  let activeFile = '';
  let activeLevel = '';
  let page = 1;
  let lastPages = 1;

  let liveOn = false;
  let liveES = null;
  let liveHash = '';

  function escapeHtml(s) {
    return (s ?? '').replace(/[&<>"']/g, (c) => ({
      '&': '&amp;',
      '<': '&lt;',
      '>': '&gt;',
      '"': '&quot;',
      '\'': '&#039;',
    }[c]));
  }

  function api(url, params = {}) {
    const u = new URL(url, location.origin);
    Object.entries(params).forEach(([k, v]) => u.searchParams.set(k, v));
    return fetch(u.toString(), { cache: 'no-store' }).then(r => r.json());
  }

  function setLiveState(on) {
    liveOn = on;
    const btn = $('btnLive');
    if (!btn) return;
    btn.textContent = on ? 'Stop Live' : 'Live';
    btn.classList.toggle('btn-danger', on);
  }

  function stopLive() {
    if (liveES) {
      liveES.close();
      liveES = null;
    }
    setLiveState(false);
  }

  function startLive() {
    if (!activeFile) return;

    stopLive();
    setLiveState(true);

    const u = new URL('/api/tail', location.origin);
    u.searchParams.set('file', activeFile);
    u.searchParams.set('lines', '400');

    liveES = new EventSource(u.toString());
    liveES.addEventListener('tail', ev => {
      const j = JSON.parse(ev.data || '{}');
      if (!j.ok) return;
      if (j.hash === liveHash) return;
      liveHash = j.hash;
      $('entries').innerHTML =
        `<div class="lv-entry">
          <span class="lv-badge info">LIVE</span>
          <pre class="lv-pre">${escapeHtml(j.text)}</pre>
        </div>`;
    });
  }

  $('btnLive')?.addEventListener('click', () => {
    liveOn ? stopLive() : startLive();
  });

  // Load Files
  async function loadFiles() {
    const j = await api('/api/files');
    files = j.files || [];
    renderFiles();
  }

  function renderFiles() {
    const box = $('fileList');
    if (!box) return;
    box.innerHTML = '';

    files.forEach(f => {
      const div = document.createElement('div');
      div.className = 'lv-file';
      div.textContent = f.name;
      div.onclick = () => {
        activeFile = f.path;
        stopLive();
        loadEntries();
      };
      box.appendChild(div);
    });
  }

  async function loadEntries() {
    if (!activeFile) return;

    const j = await api('/api/entries', {
      file: activeFile,
      page,
      per: $('perPage')?.value || 25,
      level: activeLevel,
      q: $('q')?.value || ''
    });

    if (!j.ok) return;

    const box = $('entries');
    box.innerHTML = '';

    j.items.forEach(it => {
      const row = document.createElement('div');
      row.className = 'lv-entry';
      row.innerHTML =
        `<div>
          <span class="lv-badge ${it.level}">${it.level.toUpperCase()}</span>
          ${escapeHtml(it.summary)}
        </div>
        <pre class="lv-pre d-none">${escapeHtml(it.body)}</pre>`;
      row.onclick = () => {
        row.querySelector('pre').classList.toggle('d-none');
      };
      box.appendChild(row);
    });

    lastPages = j.pages;
    $('pageInfo').textContent = `${j.page} / ${j.pages}`;
  }

  loadFiles();
})();