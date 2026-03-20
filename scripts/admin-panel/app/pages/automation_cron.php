<?php
declare(strict_types=1);
?>

<section class="ap-page-head">
  <div>
    <p class="ap-breadcrumb mb-1">Home / Automation Manager / Cron Builder</p>
    <h2 id="acTitle" class="ap-page-title mb-1">Add Cron Config</h2>
    <p class="ap-page-sub mb-0">Build and save cron entries for docker-runner scheduler.</p>
  </div>
  <div class="d-flex align-items-center gap-2 flex-wrap">
    <a class="btn ap-ghost-btn" href="<?= htmlspecialchars(($basePath ?? '') . '/automation-manager', ENT_QUOTES, 'UTF-8') ?>"><i class="bi bi-arrow-left me-1"></i>Back</a>
  </div>
</section>

<style>
  .ac-group {
    border: 1px solid var(--ap-border);
    background: color-mix(in srgb, var(--ap-surface-2) 80%, transparent);
  }

  .ac-group .card-header {
    background: color-mix(in srgb, var(--ap-surface-2) 92%, transparent);
    border-bottom: 1px solid var(--ap-border);
  }

  .ac-preview {
    overflow-y: hidden;
    resize: none;
  }
</style>

<div id="acMsg" class="d-none mb-3"></div>

<section class="row g-3 mt-1">
  <div class="col-12">
    <article class="card ap-card">
      <div class="card-body">
        <form id="acForm" novalidate>
          <input type="hidden" id="acOriginal">
          <div id="acErr" class="alert alert-danger d-none" role="alert"></div>

          <div class="row g-3">
            <div class="col-12">
              <article class="card ac-group">
                <header class="card-header">
                  <h6 class="mb-0">Identity And Schedule</h6>
                </header>
                <div class="card-body">
                  <div class="row g-3">
                    <div class="col-md-4"><label class="form-label" for="acName">File Name</label><input id="acName" class="form-control" placeholder="app-scheduler"></div>
                    <div class="col-md-8">
                      <label class="form-label" for="acMode">Schedule Preset</label>
                      <select id="acMode" class="form-select">
                        <option value="every_minute">Every minute</option>
                        <option value="every_2_hours">Every 2 hours</option>
                        <option value="every_n_hours">Every N hours</option>
                        <option value="daily">Daily</option>
                        <option value="weekly">Weekly</option>
                        <option value="monthly">Monthly</option>
                        <option value="custom">Custom expression</option>
                      </select>
                    </div>
                    <div id="acWrapNHours" class="col-md-3"><label class="form-label" for="acNHours">Every N Hours</label><input id="acNHours" class="form-control" type="number" min="1" max="23" value="2"></div>
                    <div id="acWrapHour" class="col-md-3"><label class="form-label" for="acHour">Hour (0-23)</label><input id="acHour" class="form-control" type="number" min="0" max="23" value="2"></div>
                    <div id="acWrapMin" class="col-md-3"><label class="form-label" for="acMin">Minute (0-59)</label><input id="acMin" class="form-control" type="number" min="0" max="59" value="0"></div>
                    <div id="acWrapDow" class="col-md-3">
                      <label class="form-label" for="acDow">Weekday (0=Sun ... 6=Sat)</label>
                      <input id="acDow" class="form-control" type="number" min="0" max="6" value="1">
                      <div class="form-text">0=Sunday, 1=Monday, ..., 6=Saturday</div>
                    </div>
                    <div id="acWrapDom" class="col-md-3"><label class="form-label" for="acDom">Day Of Month</label><input id="acDom" class="form-control" type="number" min="1" max="31" value="1"></div>
                    <div id="acWrapCustomExpr" class="col-12"><label class="form-label" for="acCustomExpr">Custom Expression (5 fields)</label><input id="acCustomExpr" class="form-control" value="* * * * *"></div>
                  </div>
                </div>
              </article>
            </div>

            <div class="col-12">
              <article class="card ac-group">
                <header class="card-header">
                  <h6 class="mb-0">Command</h6>
                </header>
                <div class="card-body">
                  <div class="row g-3">
                    <div class="col-md-3">
                      <label class="form-label" for="acExec">Executor</label>
                      <select id="acExec" class="form-select">
                        <option value="pexe">pexe</option>
                        <option value="dexe">dexe</option>
                        <option value="custom">custom</option>
                      </select>
                    </div>
                    <div id="acWrapPhpContainer" class="col-md-4"><label class="form-label" for="acPhpContainer">PHP Container</label><select id="acPhpContainer" class="form-select"></select></div>
                    <div id="acWrapPhpArgs" class="col-md-5"><label class="form-label" for="acPhpArgs">PHP Args / Executable</label><input id="acPhpArgs" class="form-control" placeholder="artisan schedule:run"></div>
                    <div id="acWrapAnyContainer" class="col-md-4"><label class="form-label" for="acAnyContainer">Container (dexe)</label><select id="acAnyContainer" class="form-select"></select></div>
                    <div id="acWrapDexeCmd" class="col-md-8"><label class="form-label" for="acDexeCmd">dexe Command</label><input id="acDexeCmd" class="form-control" placeholder="php artisan schedule:run"></div>
                    <div id="acWrapCustomCmd" class="col-12"><label class="form-label" for="acCustomCmd">Custom Command</label><input id="acCustomCmd" class="form-control" placeholder="/usr/local/bin/pexe PHP_84 artisan schedule:run"></div>
                    <div class="col-12">
                      <label class="form-label" for="acLogFile">Log File Path</label>
                      <input id="acLogFile" class="form-control" placeholder="/global/log/cron/app-scheduler.log">
                      <div class="form-text">Command output appends to this file using <code>2&gt;&amp;1</code>.</div>
                    </div>
                  </div>
                </div>
              </article>
            </div>

            <div class="col-12"><label class="form-label" for="acPreview">Generated Cron Line</label><textarea id="acPreview" rows="1" class="form-control ac-preview" readonly></textarea></div>
            <div class="col-12">
              <div class="form-check"><input id="acRawMode" type="checkbox" class="form-check-input"><label class="form-check-label" for="acRawMode">Raw mode</label></div>
              <textarea id="acRaw" rows="6" class="form-control mt-2 d-none" spellcheck="false"></textarea>
            </div>
          </div>

          <div class="d-flex justify-content-end gap-2 mt-3">
            <button id="acReset" type="button" class="btn btn-outline-secondary">Reset</button>
            <button id="acSave" type="submit" class="btn btn-primary">Save Cron</button>
          </div>
        </form>
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
  const val = (id, fallback = "") => {
    const node = qs(id);
    return node ? String(node.value ?? fallback) : String(fallback);
  };
  const req = (u, o) => fetch(u, o || { method: "GET", credentials: "same-origin", cache: "no-store", headers: { Accept: "application/json" } }).then(r => r.json().catch(()=>({})).then(j => ({ ok:r.ok, status:r.status, body:j || {} })));
  const msg = (k, t) => {
    const n = qs("acMsg");
    if (!n) return;
    const s = String(t || "").trim();
    if (!s) { n.className = "d-none mb-3"; n.textContent = ""; return; }
    n.className = (k==="success"?"alert alert-success mb-3":k==="warning"?"alert alert-warning mb-3":"alert alert-danger mb-3");
    n.textContent = s;
  };
  const err = (t) => {
    const n = qs("acErr");
    if (!n) return;
    const s = String(t || "").trim();
    n.classList.toggle("d-none", !s);
    n.textContent = s;
  };
  const setWrap = (id, on) => {
    const n = qs(id);
    if (!n) return;
    n.classList.toggle("d-none", !on);
  };
  const i = (v,min,max,def) => { let n = Number(v); if (!isFinite(n)) n=def; n=Math.round(n); if (n<min) n=min; if (n>max) n=max; return n; };
  const q1 = (s) => "'" + String(s||"").replace(/'/g, "'\\''") + "'";
  const slug = (s) => { const x = String(s||"").trim().toLowerCase().replace(/\.[a-z0-9]+$/i,"").replace(/[^a-z0-9]+/g,"-").replace(/^-+|-+$/g,""); return x || "cron-task"; };
  const state = { logDirty: false };
  const defaultLogFile = () => `/global/log/cron/${slug(val("acName"))}.log`;

  const cronExpr = () => {
    const m = val("acMode", "every_minute");
    const h = i(val("acHour", "2"),0,23,2), mn = i(val("acMin", "0"),0,59,0);
    if (m==="every_minute") return "* * * * *";
    if (m==="every_2_hours") return `${mn} */2 * * *`;
    if (m==="every_n_hours") return `${mn} */${i(val("acNHours", "2"),1,23,2)} * * *`;
    if (m==="daily") return `${mn} ${h} * * *`;
    if (m==="weekly") return `${mn} ${h} * * ${i(val("acDow", "1"),0,6,1)}`;
    if (m==="monthly") return `${mn} ${h} ${i(val("acDom", "1"),1,31,1)} * *`;
    return String(val("acCustomExpr", "* * * * *")).trim();
  };

  const cronCmd = () => {
    const e = val("acExec", "pexe");
    if (e==="pexe") return `/usr/local/bin/pexe ${String(val("acPhpContainer")).trim()} ${String(val("acPhpArgs")).trim()}`;
    if (e==="dexe") return `/usr/local/bin/dexe ${String(val("acAnyContainer")).trim()} /bin/sh -lc ${q1(String(val("acDexeCmd")).trim())}`;
    return String(val("acCustomCmd")).trim();
  };

  const cronLine = () => {
    const logFile = String(val("acLogFile")).trim() || defaultLogFile();
    return `${cronExpr()} root ${cronCmd()} >> ${logFile} 2>&1`;
  };

  const sync = () => {
    const m = val("acMode", "every_minute"), e = val("acExec", "pexe");
    const scheduleWraps = ["acWrapNHours", "acWrapHour", "acWrapMin", "acWrapDow", "acWrapDom", "acWrapCustomExpr"];
    scheduleWraps.forEach((id) => setWrap(id, false));
    if (m === "every_n_hours") {
      setWrap("acWrapNHours", true);
      setWrap("acWrapMin", true);
    } else if (m === "every_2_hours") {
      setWrap("acWrapMin", true);
    } else if (m === "daily") {
      setWrap("acWrapHour", true);
      setWrap("acWrapMin", true);
    } else if (m === "weekly") {
      setWrap("acWrapHour", true);
      setWrap("acWrapMin", true);
      setWrap("acWrapDow", true);
    } else if (m === "monthly") {
      setWrap("acWrapHour", true);
      setWrap("acWrapMin", true);
      setWrap("acWrapDom", true);
    } else if (m === "custom") {
      setWrap("acWrapCustomExpr", true);
    }
    if (m === "every_2_hours" && qs("acNHours")) qs("acNHours").value = "2";
    setWrap("acWrapPhpContainer", e === "pexe");
    setWrap("acWrapPhpArgs", e === "pexe");
    setWrap("acWrapAnyContainer", e === "dexe");
    setWrap("acWrapDexeCmd", e === "dexe");
    setWrap("acWrapCustomCmd", e === "custom");
    if (!state.logDirty && qs("acLogFile")) qs("acLogFile").value = defaultLogFile();
    const p = qs("acPreview");
    if (p) {
      p.value = cronLine();
    }
    qs("acRaw")?.classList.toggle("d-none", !qs("acRawMode")?.checked);
  };

  const fill = (id, arr) => {
    const n = qs(id);
    if (!n) return;
    n.innerHTML = "";
    (arr || []).forEach((v) => {
      const o = document.createElement("option");
      if (v && typeof v === "object" && v.value != null) {
        o.value = String(v.value);
        o.textContent = String(v.label || v.value);
      } else {
        o.value = String(v || "");
        o.textContent = String(v || "");
      }
      n.appendChild(o);
    });
  };

  const reset = () => {
    if (qs("acOriginal")) qs("acOriginal").value = "";
    if (qs("acTitle")) qs("acTitle").textContent = "Add Cron Config";
    if (qs("acName")) qs("acName").value = "";
    if (qs("acMode")) qs("acMode").value = "every_minute";
    if (qs("acNHours")) qs("acNHours").value = "2";
    if (qs("acHour")) qs("acHour").value = "2";
    if (qs("acMin")) qs("acMin").value = "0";
    if (qs("acDow")) qs("acDow").value = "1";
    if (qs("acDom")) qs("acDom").value = "1";
    if (qs("acCustomExpr")) qs("acCustomExpr").value = "* * * * *";
    if (qs("acExec")) qs("acExec").value = "pexe";
    if (qs("acDexeCmd")) qs("acDexeCmd").value = "";
    if (qs("acCustomCmd")) qs("acCustomCmd").value = "";
    if (qs("acLogFile")) qs("acLogFile").value = "";
    state.logDirty = false;
    if (qs("acRawMode")) qs("acRawMode").checked = false;
    if (qs("acRaw")) qs("acRaw").value = "";
    err("");
    sync();
  };

  const loadOptions = () => req(`${API}?action=options`).then((r) => {
    if(!r.ok||!r.body.ok) throw new Error(r.body.message||`Options failed (${r.status})`);
    const opts = r.body.options || {};
    fill("acPhpContainer", opts.containers?.php || []);
    fill("acAnyContainer", opts.containers?.all || []);
    const sug = opts.cron?.php_arg_suggestions || [];
    if (!val("acPhpArgs") && sug.length && qs("acPhpArgs")) qs("acPhpArgs").value = String(sug[0]);
    sync();
  });

  const loadEdit = (name) => req(API).then((r) => {
    if (!r.ok || !r.body.ok) throw new Error(r.body.message || `Load failed (${r.status})`);
    const row = (r.body.items?.cron || []).find((x) => String(x.name || "") === name);
    if (!row) throw new Error(`Cron config '${name}' not found.`);
    if (qs("acTitle")) qs("acTitle").textContent = `Edit Cron Config: ${name}`;
    if (qs("acOriginal")) qs("acOriginal").value = name;
    if (qs("acName")) qs("acName").value = name;
    if (qs("acLogFile")) qs("acLogFile").value = defaultLogFile();
    state.logDirty = false;
    if (qs("acRawMode")) qs("acRawMode").checked = true;
    if (qs("acRaw")) qs("acRaw").value = String(row.content || "");
    sync();
  });

  qs("acForm")?.addEventListener("submit", (e) => {
    e.preventDefault();
    msg("", "");
    err("");
    const name = String(val("acName")).trim();
    if (!name) { err("File name is required."); return; }
    const raw = !!qs("acRawMode")?.checked;
    const content = raw ? String(val("acRaw")) : (cronLine() + "\n");
    if (!String(content).trim()) { err("Content cannot be empty."); return; }
    req(API, {
      method: "POST",
      credentials: "same-origin",
      cache: "no-store",
      headers: { Accept: "application/json", "Content-Type": "application/json" },
      body: JSON.stringify({ kind: "cron", name, original_name: String(val("acOriginal")).trim(), content })
    }).then((r) => {
      if (!r.ok || !r.body.ok) throw new Error(r.body.message || `Save failed (${r.status})`);
      const rel = r.body.reload;
      const m = String(r.body.message || "Saved.");
      if (rel && rel.ok === false && rel.message) msg("warning", `${m} ${rel.message}`); else msg("success", m);
      if (qs("acOriginal")) qs("acOriginal").value = name;
      if (qs("acTitle")) qs("acTitle").textContent = `Edit Cron Config: ${name}`;
    }).catch((x) => err(x.message || "Save failed."));
  });

  ["acName","acMode","acNHours","acHour","acMin","acDow","acDom","acCustomExpr","acExec","acPhpContainer","acAnyContainer","acPhpArgs","acDexeCmd","acCustomCmd","acRawMode"].forEach((id) => {
    const n = qs(id);
    if (!n) return;
    n.addEventListener("input", sync);
    n.addEventListener("change", sync);
  });
  qs("acLogFile")?.addEventListener("input", () => {
    state.logDirty = true;
    sync();
  });
  qs("acLogFile")?.addEventListener("change", () => {
    state.logDirty = true;
    sync();
  });

  qs("acReset")?.addEventListener("click", reset);

  const editName = new URLSearchParams(window.location.search).get("name");
  loadOptions().then(() => {
    reset();
    if (editName) return loadEdit(editName);
    return null;
  }).catch((e) => msg("error", e.message || "Failed to load page data."));
})();
</script>
