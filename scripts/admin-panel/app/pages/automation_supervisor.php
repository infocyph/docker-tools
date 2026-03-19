<?php
declare(strict_types=1);
?>

<section class="ap-page-head">
  <div>
    <p class="ap-breadcrumb mb-1">Home / Automation / Supervisor</p>
    <h2 id="asTitle" class="ap-page-title mb-1">Add Supervisor Config</h2>
    <p class="ap-page-sub mb-0">Section-first builder: add one form card per section, then save as one config file.</p>
  </div>
  <div class="d-flex align-items-center gap-2 flex-wrap">
    <a class="btn ap-ghost-btn" href="<?= htmlspecialchars(($basePath ?? '') . '/automation-manager', ENT_QUOTES, 'UTF-8') ?>"><i class="bi bi-arrow-left me-1"></i>Back</a>
  </div>
</section>

<style>
  .as-group {
    border: 1px solid var(--ap-border);
    background: color-mix(in srgb, var(--ap-surface-2) 82%, transparent);
  }

  .as-group .card-header {
    background: color-mix(in srgb, var(--ap-surface-2) 92%, transparent);
    border-bottom: 1px solid var(--ap-border);
  }

  .as-section-tabs {
    display: flex;
    align-items: center;
    gap: 0.35rem;
    overflow-x: auto;
    overflow-y: hidden;
    flex-wrap: nowrap;
    white-space: nowrap;
    padding-bottom: 0;
  }

  .as-section-tabs .nav-item {
    flex: 0 0 auto;
  }

  .as-section-tabs .nav-link {
    white-space: nowrap;
  }

  .as-section-tab-item {
    display: flex;
    align-items: center;
    gap: 0.35rem;
    position: relative;
  }

  .as-section-tab-link {
    display: inline-flex;
    align-items: center;
    gap: 0.45rem;
    padding-right: 1.65rem;
  }

  .as-tab-index {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    min-width: 1.25rem;
    height: 1.25rem;
    padding: 0 0.35rem;
    border-radius: 999px;
    font-size: 0.7rem;
    font-weight: 700;
    background: color-mix(in srgb, var(--bs-primary, #0d6efd) 22%, transparent);
    color: var(--bs-primary, #0d6efd);
  }

  .as-tab-remove-btn {
    border: 0;
    background: transparent;
    color: var(--bs-secondary-color, #6c757d);
    width: 1.25rem;
    height: 1.25rem;
    border-radius: 999px;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    padding: 0;
    position: absolute;
    right: 0.35rem;
    top: 50%;
    transform: translateY(-50%);
    z-index: 3;
  }

  .as-tab-remove-btn:hover {
    color: var(--bs-danger, #dc3545);
    background: color-mix(in srgb, var(--bs-danger, #dc3545) 15%, transparent);
  }

  .as-tab-remove-btn i {
    font-size: 0.7rem;
    line-height: 1;
  }

  .as-add-tab-btn {
    border: 1px dashed var(--ap-border);
    border-radius: 0.5rem;
    background: color-mix(in srgb, var(--ap-surface-2) 88%, transparent);
    color: var(--bs-primary, #0d6efd);
  }

  .as-add-tab-btn:hover {
    background: color-mix(in srgb, var(--ap-surface-2) 72%, var(--bs-primary, #0d6efd) 8%);
    color: var(--bs-primary, #0d6efd);
  }

  .as-preview-pane .card-body {
    display: flex;
  }

  .as-section-preview {
    width: 100%;
    height: 100%;
    resize: none;
    font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", monospace;
    white-space: pre;
  }
</style>

<div id="asMsg" class="d-none mb-3"></div>

<section class="row g-3 mt-1">
  <div class="col-12">
    <article class="card ap-card">
      <div class="card-body">
        <form id="asForm" novalidate>
          <input type="hidden" id="asOriginal">
          <div id="asErr" class="alert alert-danger d-none" role="alert"></div>

          <div class="card border-0 shadow-sm mb-3">
            <div class="card-header">File Settings</div>
            <div class="card-body">
              <div class="row g-3">
                <div class="col-md-8">
                  <label class="form-label" for="asName">Config File Name</label>
                  <input id="asName" class="form-control" value="program-worker-default.conf" data-bs-toggle="tooltip" title="Destination supervisor file name.">
                </div>
                <div class="col-md-4 d-flex align-items-end">
                  <div class="form-check">
                    <input id="asRawMode" type="checkbox" class="form-check-input" data-bs-toggle="tooltip" title="Enable manual full-file editing mode.">
                    <label class="form-check-label" for="asRawMode">Raw mode</label>
                  </div>
                </div>
              </div>
            </div>
          </div>

          <div class="card border-0 shadow-sm mb-3">
            <div class="card-header d-flex justify-content-between align-items-center">
              <span>Sections</span>
              <button type="button" class="btn btn-sm btn-outline-secondary" data-bs-toggle="modal" data-bs-target="#asGuideModal">Guide</button>
            </div>
            <div class="card-body">
              <div id="asTabsWrap">
                <ul id="asSectionTabs" class="nav nav-tabs as-section-tabs mb-3" role="tablist">
                  <li id="asAddSectionItem" class="nav-item" role="presentation">
                    <button id="asAddSectionTab" type="button" class="nav-link as-add-tab-btn" data-bs-toggle="tooltip" title="Add new section tab">
                      + Add
                    </button>
                  </li>
                </ul>
                <div id="asSectionPanes" class="tab-content"></div>
              </div>
              <textarea id="asRaw" rows="16" class="form-control d-none font-monospace" spellcheck="false" style="resize:none;"></textarea>
            </div>
          </div>

          <div class="card border-0 shadow-sm mb-3">
            <div class="card-header">Generated Final config</div>
            <div class="card-body">
              <textarea id="asPreview" rows="12" class="form-control font-monospace" readonly style="resize:none;"></textarea>
            </div>
          </div>

          <div class="d-flex justify-content-end gap-2">
            <button id="asReset" type="button" class="btn btn-outline-secondary">Reset</button>
            <button id="asSave" type="submit" class="btn btn-primary">Save Supervisor</button>
          </div>
        </form>
      </div>
    </article>
  </div>
</section>

<div class="modal fade" id="asGuideModal" tabindex="-1" aria-labelledby="asGuideModalLabel" aria-hidden="true">
  <div class="modal-dialog modal-lg modal-dialog-scrollable">
    <div class="modal-content">
      <div class="modal-header">
        <h5 class="modal-title" id="asGuideModalLabel">Supervisor Builder Guide</h5>
        <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
      </div>
      <div class="modal-body">
        <p class="mb-2"><strong>program</strong>: daemon/worker processes.</p>
        <p class="mb-2"><strong>eventlistener</strong>: listener process for Supervisor events (configure <code>events</code>).</p>
        <p class="mb-2"><strong>fcgi-program</strong>: FastCGI process with managed socket.</p>
        <p class="mb-2">Use the <strong>+</strong> button in tab header to add more sections in the same file (odd/even/mod variants).</p>
        <p class="mb-0">All card values are merged into one final file preview and saved together.</p>
      </div>
    </div>
  </div>
</div>

<script>
(() => {
  "use strict";
  const base = (document.body?.getAttribute("data-ap-base") || "") === "/" ? "" : (document.body?.getAttribute("data-ap-base") || "");
  const API = base + "/api/automation-manager";

  const qs = (id) => document.getElementById(id);
  const esc = (s) => String(s ?? "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&#039;");
  const norm = (s, f = "item") => {
    const x = String(s || "").trim().toLowerCase().replace(/\.[a-z0-9]+$/i, "").replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "");
    return x || f;
  };
  const q1 = (s) => "'" + String(s || "").replace(/'/g, "'\\''") + "'";
  const asBool = (s, d = false) => {
    const x = String(s || "").trim().toLowerCase();
    if (!x) return d;
    if (["1", "true", "yes", "on"].includes(x)) return true;
    if (["0", "false", "no", "off"].includes(x)) return false;
    return d;
  };
  const asInt = (s, d, min = null) => {
    let n = Number.parseInt(String(s ?? d), 10);
    if (!Number.isFinite(n)) n = d;
    if (min !== null && n < min) n = min;
    return String(n);
  };
  const fileOk = (name) => /^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(name);
  const req = (u, o) => fetch(u, o || { method: "GET", credentials: "same-origin", cache: "no-store", headers: { Accept: "application/json" } }).then(async (r) => {
    const txt = await r.text().catch(() => "");
    let body = {};
    try {
      body = JSON.parse(txt || "{}");
    } catch (_) {
      const t = String(txt || "").trim();
      body = t ? { message: t.slice(0, 500) } : {};
    }
    return { ok: r.ok, status: r.status, body: body || {} };
  });

  const msg = (k, t) => {
    const n = qs("asMsg");
    if (!n) return;
    const s = String(t || "").trim();
    if (!s) {
      n.className = "d-none mb-3";
      n.textContent = "";
      return;
    }
    n.className = (k === "success" ? "alert alert-success mb-3" : k === "warning" ? "alert alert-warning mb-3" : "alert alert-danger mb-3");
    n.textContent = s;
  };
  const err = (t) => {
    const n = qs("asErr");
    if (!n) return;
    const s = String(t || "").trim();
    n.classList.toggle("d-none", !s);
    n.textContent = s;
  };

  const state = {
    containers: {
      all: [],
      php: [],
    },
    nameDirty: false,
    tabSeq: 0,
    rawMode: false,
  };

  const tooltip = (root = document) => {
    if (!(window.bootstrap && window.bootstrap.Tooltip)) return;
    root.querySelectorAll('[data-bs-toggle="tooltip"]').forEach((el) => {
      try { new window.bootstrap.Tooltip(el); } catch (_) {}
    });
  };

  const sectionDefaults = (type = "program", idx = 1) => {
    const suffix = `${idx}`;
    const n = type === "eventlistener" ? `listener_${suffix}` : (type === "fcgi-program" ? `fcgi_${suffix}` : `worker_${suffix}`);
    return {
      section_type: type,
      section_name: n,
      socket: "tcp://127.0.0.1:9000",
      socket_owner: "",
      socket_mode: "",
      socket_backlog: "1024",
      events: "PROCESS_STATE",
      buffer_size: "10",
      result_handler: "supervisor.dispatchers:default_handler",
      exec_mode: "pexe",
      php_container: "",
      php_args: "",
      any_container: "",
      dexe_cmd: "",
      custom_cmd: "",
      process_name: "%(program_name)s",
      numprocs: "1",
      numprocs_start: "0",
      directory: "",
      umask: "022",
      priority: "999",
      autostart: true,
      autorestart: "unexpected",
      startsecs: "1",
      startretries: "3",
      exitcodes: "0",
      stopsignal: "TERM",
      stopwaitsecs: "10",
      stopasgroup: false,
      killasgroup: false,
      user: "root",
      redirect_stderr: false,
      stdout_logfile: "",
      stdout_logfile_maxbytes: "20MB",
      stdout_logfile_backups: "10",
      stdout_capture_maxbytes: "0",
      stdout_events_enabled: false,
      stdout_syslog: false,
      stderr_logfile: "",
      stderr_logfile_maxbytes: "20MB",
      stderr_logfile_backups: "10",
      stderr_capture_maxbytes: "0",
      stderr_events_enabled: false,
      stderr_syslog: false,
      environment: "",
      serverurl: "AUTO",
    };
  };

  const suggestFileName = (type, sectionName) => `${type}-${norm(sectionName || type, type)}.conf`;

  const cardHtml = () => `
    <div class="as-section-card">
      <div class="row g-3">
        <div class="col-xl-8">
          <article class="card as-group mb-3">
            <header class="card-header"><h6 class="mb-0">Section Identity</h6></header>
            <div class="card-body">
              <div class="row g-3 align-items-end">
                <div class="col-md-4">
                  <label class="form-label">Section Type</label>
                  <select class="form-select" data-field="section_type">
                    <option value="program">program</option>
                    <option value="eventlistener">eventlistener</option>
                    <option value="fcgi-program">fcgi-program</option>
                  </select>
                </div>
                <div class="col-md-6">
                  <label class="form-label">Section Name</label>
                  <input class="form-control" data-field="section_name" placeholder="worker_default">
                </div>
                <div class="col-md-2 d-none d-md-block"></div>
              </div>
            </div>
          </article>

          <article class="card as-group mb-3">
            <header class="card-header"><h6 class="mb-0">Execution Command</h6></header>
            <div class="card-body">
              <div class="row g-3">
                <div class="col-md-3">
                  <label class="form-label">Command Source</label>
                  <select class="form-select" data-field="exec_mode">
                    <option value="pexe">pexe</option>
                    <option value="dexe">dexe</option>
                    <option value="custom">custom</option>
                  </select>
                </div>
                <div class="col-md-4" data-wrap="php"><label class="form-label">PHP Container</label><select class="form-select" data-field="php_container"></select></div>
                <div class="col-md-5" data-wrap="php"><label class="form-label">PHP Executable and Args</label><input class="form-control" data-field="php_args" placeholder="artisan queue:work --sleep=1 --tries=3"></div>
                <div class="col-md-4" data-wrap="dexe"><label class="form-label">Target Container</label><select class="form-select" data-field="any_container"></select></div>
                <div class="col-md-8" data-wrap="dexe"><label class="form-label">Container Shell Command</label><input class="form-control" data-field="dexe_cmd"></div>
                <div class="col-12" data-wrap="custom"><label class="form-label">Full Command</label><input class="form-control" data-field="custom_cmd"></div>
              </div>
            </div>
          </article>

          <article class="card as-group mb-3 d-none" data-wrap="socket">
            <header class="card-header"><h6 class="mb-0">FastCGI Socket Settings</h6></header>
            <div class="card-body">
              <div class="row g-3">
                <div class="col-md-6" data-wrap="socket"><label class="form-label">Socket Address</label><input class="form-control" data-field="socket"></div>
                <div class="col-md-3" data-wrap="socket"><label class="form-label">Socket Owner</label><input class="form-control" data-field="socket_owner"></div>
                <div class="col-md-3" data-wrap="socket"><label class="form-label">Socket Mode</label><input class="form-control" data-field="socket_mode"></div>
                <div class="col-md-3" data-wrap="socket"><label class="form-label">Socket Backlog</label><input class="form-control" data-field="socket_backlog" type="number" min="1"></div>
              </div>
            </div>
          </article>

          <article class="card as-group mb-3 d-none" data-wrap="events">
            <header class="card-header"><h6 class="mb-0">Event Subscription</h6></header>
            <div class="card-body">
              <div class="row g-3">
                <div class="col-md-5" data-wrap="events"><label class="form-label">Subscribed Events</label><input class="form-control" data-field="events"></div>
                <div class="col-md-3" data-wrap="events"><label class="form-label">Buffer Size</label><input class="form-control" data-field="buffer_size" type="number" min="1"></div>
                <div class="col-md-4" data-wrap="events"><label class="form-label">Result Handler</label><input class="form-control" data-field="result_handler"></div>
              </div>
            </div>
          </article>

          <article class="card as-group mb-3">
            <header class="card-header"><h6 class="mb-0">Process Lifecycle</h6></header>
            <div class="card-body">
              <div class="row g-3">
                <div class="col-md-4"><label class="form-label">Process Name Template</label><input class="form-control" data-field="process_name"></div>
                <div class="col-md-2"><label class="form-label">Run As User</label><input class="form-control" data-field="user"></div>
                <div class="col-md-2"><label class="form-label">Priority</label><input class="form-control" data-field="priority" type="number"></div>
                <div class="col-md-4"><label class="form-label">Working Directory</label><input class="form-control" data-field="directory" placeholder="/app"></div>
                <div class="col-md-2"><label class="form-label">Process Count</label><input class="form-control" data-field="numprocs" type="number" min="1"></div>
                <div class="col-md-2"><label class="form-label">Process Index Start</label><input class="form-control" data-field="numprocs_start" type="number" min="0"></div>
                <div class="col-md-2"><label class="form-label">Auto Restart</label><select class="form-select" data-field="autorestart"><option value="unexpected">unexpected</option><option value="true">true</option><option value="false">false</option></select></div>
                <div class="col-md-2"><label class="form-label">File Mode Mask</label><input class="form-control" data-field="umask"></div>
                <div class="col-md-2"><label class="form-label">Start Secs</label><input class="form-control" data-field="startsecs" type="number" min="0"></div>
                <div class="col-md-2"><label class="form-label">Start Retries</label><input class="form-control" data-field="startretries" type="number" min="0"></div>
                <div class="col-md-4"><label class="form-label">Expected Exit Codes</label><input class="form-control" data-field="exitcodes"></div>
                <div class="col-md-4"><label class="form-label">Stop Signal</label><input class="form-control" data-field="stopsignal"></div>
                <div class="col-md-4"><label class="form-label">Stop Wait Secs</label><input class="form-control" data-field="stopwaitsecs" type="number" min="0"></div>
              </div>
              <div class="row g-3 pt-2 border-top mt-3">
                <div class="col-md-3"><div class="form-check"><input class="form-check-input" type="checkbox" data-field="autostart"><label class="form-check-label">Autostart</label></div></div>
                <div class="col-md-3"><div class="form-check"><input class="form-check-input" type="checkbox" data-field="stopasgroup"><label class="form-check-label">Stop As Group</label></div></div>
                <div class="col-md-3"><div class="form-check"><input class="form-check-input" type="checkbox" data-field="killasgroup"><label class="form-check-label">Kill As Group</label></div></div>
                <div class="col-md-3"><div class="form-check"><input class="form-check-input" type="checkbox" data-field="redirect_stderr"><label class="form-check-label">Redirect stderr to stdout</label></div></div>
              </div>
            </div>
          </article>

          <article class="card as-group mb-3">
            <header class="card-header"><h6 class="mb-0">Log Output and Rotation</h6></header>
            <div class="card-body">
              <div class="row g-3">
                <div class="col-md-6"><label class="form-label">stdout Log File</label><input class="form-control" data-field="stdout_logfile" readonly></div>
                <div class="col-md-6" data-wrap="stderr-path"><label class="form-label">stderr Log File</label><input class="form-control" data-field="stderr_logfile" readonly></div>
                <div class="col-md-4"><label class="form-label">stdout Max Bytes</label><input class="form-control" data-field="stdout_logfile_maxbytes"></div>
                <div class="col-md-4"><label class="form-label">stdout Backups</label><input class="form-control" data-field="stdout_logfile_backups" type="number" min="0"></div>
                <div class="col-md-4"><label class="form-label">stdout Capture Max Bytes</label><input class="form-control" data-field="stdout_capture_maxbytes"></div>
                <div class="col-md-4" data-wrap="stderr-meta"><label class="form-label">stderr Max Bytes</label><input class="form-control" data-field="stderr_logfile_maxbytes"></div>
                <div class="col-md-4" data-wrap="stderr-meta"><label class="form-label">stderr Backups</label><input class="form-control" data-field="stderr_logfile_backups" type="number" min="0"></div>
                <div class="col-md-4" data-wrap="stderr-meta"><label class="form-label">stderr Capture Max Bytes</label><input class="form-control" data-field="stderr_capture_maxbytes"></div>
              </div>
              <div class="row g-3 pt-2 border-top mt-3">
                <div class="col-md-3"><div class="form-check"><input class="form-check-input" type="checkbox" data-field="stdout_events_enabled"><label class="form-check-label">stdout Events Enabled</label></div></div>
                <div class="col-md-3"><div class="form-check"><input class="form-check-input" type="checkbox" data-field="stdout_syslog"><label class="form-check-label">stdout Syslog</label></div></div>
                <div class="col-md-3" data-wrap="stderr-meta"><div class="form-check"><input class="form-check-input" type="checkbox" data-field="stderr_events_enabled"><label class="form-check-label">stderr Events Enabled</label></div></div>
                <div class="col-md-3" data-wrap="stderr-meta"><div class="form-check"><input class="form-check-input" type="checkbox" data-field="stderr_syslog"><label class="form-check-label">stderr Syslog</label></div></div>
              </div>
            </div>
          </article>

          <article class="card as-group">
            <header class="card-header"><h6 class="mb-0">Environment and Supervisor Connection</h6></header>
            <div class="card-body">
              <div class="row g-3">
                <div class="col-md-8"><label class="form-label">Environment Variables</label><input class="form-control" data-field="environment" placeholder="APP_ENV=prod,QUEUE=high"></div>
                <div class="col-md-4"><label class="form-label">Supervisor Server URL</label><input class="form-control" data-field="serverurl"></div>
              </div>
            </div>
          </article>
        </div>
        <div class="col-xl-4">
          <article class="card as-group as-preview-pane h-100">
            <header class="card-header"><h6 class="mb-0">Generated Section Preview</h6></header>
            <div class="card-body">
              <textarea class="form-control as-section-preview font-monospace" data-field="section_preview" rows="30" readonly></textarea>
            </div>
          </article>
        </div>
      </div>
    </div>
  `;

  const fieldHints = {
    section_type: "Supervisor section namespace. This controls type-specific options shown below.",
    section_name: "Identifier used in [section_type:section_name]. Keep it unique in this file.",
    exec_mode: "How command is built: pexe for PHP container commands, dexe for generic container shell command, custom for full manual command.",
    php_container: "Target PHP container for pexe command.",
    php_args: "Executable and arguments passed to pexe in the selected PHP container.",
    any_container: "Target container name for dexe command.",
    dexe_cmd: "Shell command executed inside selected container via dexe.",
    custom_cmd: "Full supervisor command value. Use only when you need fully manual control.",
    socket: "Socket address for fcgi-program, for example tcp://127.0.0.1:9000.",
    socket_owner: "Optional owner of created socket.",
    socket_mode: "Optional mode of created socket, for example 0700.",
    socket_backlog: "Backlog for queued socket connections.",
    events: "Comma-separated event names listened by eventlistener section.",
    buffer_size: "Event listener result buffer size in bytes.",
    result_handler: "Python dotted path used for custom event result handling.",
    process_name: "Process name template. %(program_name)s and %(process_num)s are common tokens.",
    numprocs: "Number of processes to start for this section.",
    numprocs_start: "Initial index for process_num.",
    directory: "Working directory before executing command.",
    umask: "Process umask, typically octal like 022.",
    priority: "Lower values start first and stop last.",
    autostart: "Start process automatically with supervisord.",
    autorestart: "Restart policy when process exits.",
    startsecs: "Seconds process must stay up to be considered running.",
    startretries: "Retry attempts before moving to fatal state.",
    exitcodes: "Expected exit codes when autorestart is unexpected.",
    stopsignal: "Signal used to stop process, for example TERM.",
    stopwaitsecs: "Wait time before forcible kill.",
    stopasgroup: "Send stop signal to full process group.",
    killasgroup: "Send kill signal to full process group.",
    user: "User to run process as.",
    redirect_stderr: "When enabled, stderr is redirected to stdout.",
    stdout_logfile: "Auto-generated stdout logfile path.",
    stdout_logfile_maxbytes: "Max size before stdout log rotation.",
    stdout_logfile_backups: "Number of rotated stdout log backups to keep.",
    stdout_capture_maxbytes: "Capture size for stdout event mode.",
    stdout_events_enabled: "Emit PROCESS_LOG_STDOUT events.",
    stdout_syslog: "Forward stdout to syslog.",
    stderr_logfile: "Auto-generated stderr logfile path.",
    stderr_logfile_maxbytes: "Max size before stderr log rotation.",
    stderr_logfile_backups: "Number of rotated stderr log backups to keep.",
    stderr_capture_maxbytes: "Capture size for stderr event mode.",
    stderr_events_enabled: "Emit PROCESS_LOG_STDERR events.",
    stderr_syslog: "Forward stderr to syslog.",
    environment: "Environment variables, comma-separated key=value pairs.",
    serverurl: "Supervisor server URL. Keep AUTO unless overriding.",
  };

  const applyFieldHints = (card) => {
    card.querySelectorAll("[data-field]").forEach((el) => {
      const key = String(el.getAttribute("data-field") || "").trim();
      const hint = fieldHints[key];
      if (!hint) return;
      el.setAttribute("data-bs-toggle", "tooltip");
      el.setAttribute("title", hint);
      const label = el.parentElement ? el.parentElement.querySelector("label.form-label") : null;
      if (label) {
        label.setAttribute("data-bs-toggle", "tooltip");
        label.setAttribute("title", hint);
      }
    });
  };

  const field = (card, name) => card.querySelector(`[data-field="${name}"]`);
  const getValue = (card, name, d = "") => {
    const n = field(card, name);
    return n ? String(n.value ?? d) : String(d);
  };
  const getChecked = (card, name) => !!field(card, name)?.checked;
  const setValue = (card, name, v) => { const n = field(card, name); if (n) n.value = String(v ?? ""); };
  const setChecked = (card, name, v) => { const n = field(card, name); if (n) n.checked = !!v; };
  const showWrap = (card, key, on) => card.querySelectorAll(`[data-wrap="${key}"]`).forEach((el) => el.classList.toggle("d-none", !on));

  const modelFromCard = (card) => {
    const t = getValue(card, "section_type", "program");
    const redirect = t === "eventlistener" ? false : getChecked(card, "redirect_stderr");
    return {
      section_type: t,
      section_name: getValue(card, "section_name", "worker").trim() || "worker",
      socket: getValue(card, "socket").trim(),
      socket_owner: getValue(card, "socket_owner").trim(),
      socket_mode: getValue(card, "socket_mode").trim(),
      socket_backlog: asInt(getValue(card, "socket_backlog"), 1024, 1),
      events: getValue(card, "events", "PROCESS_STATE").trim(),
      buffer_size: asInt(getValue(card, "buffer_size"), 10, 1),
      result_handler: getValue(card, "result_handler", "supervisor.dispatchers:default_handler").trim(),
      exec_mode: getValue(card, "exec_mode", "pexe"),
      php_container: getValue(card, "php_container").trim(),
      php_args: getValue(card, "php_args").trim(),
      any_container: getValue(card, "any_container").trim(),
      dexe_cmd: getValue(card, "dexe_cmd").trim(),
      custom_cmd: getValue(card, "custom_cmd").trim(),
      process_name: getValue(card, "process_name", "%(program_name)s").trim() || "%(program_name)s",
      numprocs: asInt(getValue(card, "numprocs"), 1, 1),
      numprocs_start: asInt(getValue(card, "numprocs_start"), 0, 0),
      directory: getValue(card, "directory").trim(),
      umask: getValue(card, "umask", "022").trim() || "022",
      priority: asInt(getValue(card, "priority"), 999),
      autostart: getChecked(card, "autostart"),
      autorestart: getValue(card, "autorestart", "unexpected").trim() || "unexpected",
      startsecs: asInt(getValue(card, "startsecs"), 1, 0),
      startretries: asInt(getValue(card, "startretries"), 3, 0),
      exitcodes: getValue(card, "exitcodes", "0").trim() || "0",
      stopsignal: getValue(card, "stopsignal", "TERM").trim().toUpperCase() || "TERM",
      stopwaitsecs: asInt(getValue(card, "stopwaitsecs"), 10, 0),
      stopasgroup: getChecked(card, "stopasgroup"),
      killasgroup: getChecked(card, "killasgroup"),
      user: getValue(card, "user", "root").trim() || "root",
      redirect_stderr: redirect,
      stdout_logfile: getValue(card, "stdout_logfile").trim(),
      stdout_logfile_maxbytes: getValue(card, "stdout_logfile_maxbytes", "20MB").trim() || "20MB",
      stdout_logfile_backups: asInt(getValue(card, "stdout_logfile_backups"), 10, 0),
      stdout_capture_maxbytes: getValue(card, "stdout_capture_maxbytes", "0").trim() || "0",
      stdout_events_enabled: getChecked(card, "stdout_events_enabled"),
      stdout_syslog: getChecked(card, "stdout_syslog"),
      stderr_logfile: getValue(card, "stderr_logfile").trim(),
      stderr_logfile_maxbytes: getValue(card, "stderr_logfile_maxbytes", "20MB").trim() || "20MB",
      stderr_logfile_backups: asInt(getValue(card, "stderr_logfile_backups"), 10, 0),
      stderr_capture_maxbytes: getValue(card, "stderr_capture_maxbytes", "0").trim() || "0",
      stderr_events_enabled: getChecked(card, "stderr_events_enabled"),
      stderr_syslog: getChecked(card, "stderr_syslog"),
      environment: getValue(card, "environment").trim(),
      serverurl: getValue(card, "serverurl", "AUTO").trim() || "AUTO",
    };
  };

  const commandForModel = (m) => {
    if (m.exec_mode === "pexe") {
      const parts = ["/usr/local/bin/pexe", m.php_container, m.php_args].filter((x) => x !== "");
      return parts.join(" ").trim();
    }
    if (m.exec_mode === "dexe") {
      if (!m.any_container || !m.dexe_cmd) return "";
      return `/usr/local/bin/dexe ${m.any_container} /bin/sh -lc ${q1(m.dexe_cmd)}`;
    }
    return m.custom_cmd;
  };

  const renderSectionConfig = (m) => {
    const lines = [`[${m.section_type}:${m.section_name}]`];
    const add = (k, v) => { const s = String(v ?? "").trim(); if (s !== "") lines.push(`${k}=${s}`); };
    if (m.section_type === "fcgi-program") {
      add("socket", m.socket);
      add("socket_owner", m.socket_owner);
      add("socket_mode", m.socket_mode);
      add("socket_backlog", m.socket_backlog);
    }
    add("command", commandForModel(m));
    if (m.section_type === "eventlistener") {
      add("events", m.events);
      add("buffer_size", m.buffer_size);
      add("result_handler", m.result_handler);
    }
    add("process_name", m.process_name);
    add("numprocs", m.numprocs);
    add("numprocs_start", m.numprocs_start);
    add("directory", m.directory);
    add("umask", m.umask);
    add("priority", m.priority);
    add("autostart", m.autostart ? "true" : "false");
    add("autorestart", m.autorestart);
    add("startsecs", m.startsecs);
    add("startretries", m.startretries);
    add("exitcodes", m.exitcodes);
    add("stopsignal", m.stopsignal);
    add("stopwaitsecs", m.stopwaitsecs);
    add("stopasgroup", m.stopasgroup ? "true" : "false");
    add("killasgroup", m.killasgroup ? "true" : "false");
    add("user", m.user);
    add("redirect_stderr", m.redirect_stderr ? "true" : "false");
    add("stdout_logfile", m.stdout_logfile);
    add("stdout_logfile_maxbytes", m.stdout_logfile_maxbytes);
    add("stdout_logfile_backups", m.stdout_logfile_backups);
    add("stdout_capture_maxbytes", m.stdout_capture_maxbytes);
    add("stdout_events_enabled", m.stdout_events_enabled ? "true" : "false");
    if (m.stdout_syslog) add("stdout_syslog", "true");
    if (!m.redirect_stderr) {
      add("stderr_logfile", m.stderr_logfile);
      add("stderr_logfile_maxbytes", m.stderr_logfile_maxbytes);
      add("stderr_logfile_backups", m.stderr_logfile_backups);
      add("stderr_capture_maxbytes", m.stderr_capture_maxbytes);
      add("stderr_events_enabled", m.stderr_events_enabled ? "true" : "false");
      if (m.stderr_syslog) add("stderr_syslog", "true");
    }
    add("environment", m.environment);
    if (m.serverurl && m.serverurl.toUpperCase() !== "AUTO") add("serverurl", m.serverurl);
    lines.push("");
    return lines.join("\n");
  };

  const syncCard = (card) => {
    const m = modelFromCard(card);
    const t = m.section_type;
    const isListener = t === "eventlistener";
    const isFcgi = t === "fcgi-program";
    const exec = m.exec_mode;

    showWrap(card, "socket", isFcgi);
    showWrap(card, "events", isListener);
    showWrap(card, "php", exec === "pexe");
    showWrap(card, "dexe", exec === "dexe");
    showWrap(card, "custom", exec === "custom");
    showWrap(card, "stderr-path", !m.redirect_stderr || isListener);
    showWrap(card, "stderr-meta", !m.redirect_stderr || isListener);

    const redirectField = field(card, "redirect_stderr");
    if (redirectField) {
      redirectField.disabled = isListener;
      if (isListener) redirectField.checked = false;
    }

    const stem = norm(m.section_name || "worker", "worker");
    setValue(card, "stdout_logfile", `/var/log/supervisor/${stem}.out.log`);
    setValue(card, "stderr_logfile", `/var/log/supervisor/${stem}.err.log`);

    const preview = field(card, "section_preview");
    if (preview) {
      preview.value = renderSectionConfig(modelFromCard(card));
    }
  };

  const cardFromModel = (model) => {
    const host = document.createElement("div");
    host.innerHTML = cardHtml();
    const card = host.firstElementChild;
    if (!card) return null;

    const phpSel = field(card, "php_container");
    const allSel = field(card, "any_container");
    if (phpSel) {
      phpSel.innerHTML = "";
      const src = state.containers.php.length ? state.containers.php : state.containers.all;
      (src.length ? src : [""]).forEach((name) => {
        const o = document.createElement("option");
        o.value = String(name || "");
        o.textContent = String(name || "No containers detected");
        phpSel.appendChild(o);
      });
    }
    if (allSel) {
      allSel.innerHTML = "";
      (state.containers.all.length ? state.containers.all : [""]).forEach((name) => {
        const o = document.createElement("option");
        o.value = String(name || "");
        o.textContent = String(name || "No containers detected");
        allSel.appendChild(o);
      });
    }

    Object.entries(model).forEach(([k, v]) => {
      const el = field(card, k);
      if (!el) return;
      if (el.type === "checkbox") el.checked = !!v;
      else el.value = String(v ?? "");
    });

    applyFieldHints(card);
    syncCard(card);
    return card;
  };

  const cards = () => Array.from(qs("asSectionPanes")?.querySelectorAll(".as-section-card") || []);
  const tabButtons = () => Array.from(qs("asSectionTabs")?.querySelectorAll('[data-bs-toggle="tab"]') || []);
  const sectionTabItems = () => Array.from(qs("asSectionTabs")?.querySelectorAll(".as-section-tab-item") || []);
  const paneForCard = (card) => card.closest(".tab-pane");
  const tabForPane = (paneId) => qs("asSectionTabs")?.querySelector(`[data-bs-target="#${paneId}"]`) || null;
  const ensureAddSectionTab = () => {
    const tabs = qs("asSectionTabs");
    if (!tabs) return;
    if (qs("asAddSectionItem")) return;
    const li = document.createElement("li");
    li.id = "asAddSectionItem";
    li.className = "nav-item";
    li.role = "presentation";
    li.innerHTML = `<button id="asAddSectionTab" type="button" class="nav-link as-add-tab-btn" data-bs-toggle="tooltip" title="Add new section tab">+ Add</button>`;
    tabs.appendChild(li);
    tooltip(li);
  };
  const clearSectionsUi = () => {
    qs("asSectionPanes").innerHTML = "";
    const tabs = qs("asSectionTabs");
    if (tabs) {
      tabs.querySelectorAll("li").forEach((li) => {
        if (li.id !== "asAddSectionItem") li.remove();
      });
    }
    ensureAddSectionTab();
  };
  const activatePane = (paneId) => {
    const btn = tabForPane(paneId);
    if (!btn) return;
    if (window.bootstrap && window.bootstrap.Tab) {
      window.bootstrap.Tab.getOrCreateInstance(btn).show();
      return;
    }
    tabButtons().forEach((b) => b.classList.remove("active"));
    btn.classList.add("active");
    Array.from(qs("asSectionPanes")?.querySelectorAll(".tab-pane") || []).forEach((p) => {
      const on = p.id === paneId;
      p.classList.toggle("show", on);
      p.classList.toggle("active", on);
    });
  };

  const modelFromKv = (type, name, kv) => {
    const m = sectionDefaults(type, 1);
    m.section_type = type;
    m.section_name = name || m.section_name;
    m.socket = kv.get("socket") || m.socket;
    m.socket_owner = kv.get("socket_owner") || m.socket_owner;
    m.socket_mode = kv.get("socket_mode") || m.socket_mode;
    m.socket_backlog = kv.get("socket_backlog") || m.socket_backlog;
    m.events = kv.get("events") || m.events;
    m.buffer_size = kv.get("buffer_size") || m.buffer_size;
    m.result_handler = kv.get("result_handler") || m.result_handler;
    m.process_name = kv.get("process_name") || m.process_name;
    m.numprocs = kv.get("numprocs") || m.numprocs;
    m.numprocs_start = kv.get("numprocs_start") || m.numprocs_start;
    m.directory = kv.get("directory") || m.directory;
    m.umask = kv.get("umask") || m.umask;
    m.priority = kv.get("priority") || m.priority;
    m.autostart = asBool(kv.get("autostart"), true);
    m.autorestart = kv.get("autorestart") || m.autorestart;
    m.startsecs = kv.get("startsecs") || m.startsecs;
    m.startretries = kv.get("startretries") || m.startretries;
    m.exitcodes = kv.get("exitcodes") || m.exitcodes;
    m.stopsignal = kv.get("stopsignal") || m.stopsignal;
    m.stopwaitsecs = kv.get("stopwaitsecs") || m.stopwaitsecs;
    m.stopasgroup = asBool(kv.get("stopasgroup"), false);
    m.killasgroup = asBool(kv.get("killasgroup"), false);
    m.user = kv.get("user") || m.user;
    m.redirect_stderr = asBool(kv.get("redirect_stderr"), false);
    m.stdout_logfile_maxbytes = kv.get("stdout_logfile_maxbytes") || m.stdout_logfile_maxbytes;
    m.stdout_logfile_backups = kv.get("stdout_logfile_backups") || m.stdout_logfile_backups;
    m.stdout_capture_maxbytes = kv.get("stdout_capture_maxbytes") || m.stdout_capture_maxbytes;
    m.stdout_events_enabled = asBool(kv.get("stdout_events_enabled"), false);
    m.stdout_syslog = asBool(kv.get("stdout_syslog"), false);
    m.stderr_logfile_maxbytes = kv.get("stderr_logfile_maxbytes") || m.stderr_logfile_maxbytes;
    m.stderr_logfile_backups = kv.get("stderr_logfile_backups") || m.stderr_logfile_backups;
    m.stderr_capture_maxbytes = kv.get("stderr_capture_maxbytes") || m.stderr_capture_maxbytes;
    m.stderr_events_enabled = asBool(kv.get("stderr_events_enabled"), false);
    m.stderr_syslog = asBool(kv.get("stderr_syslog"), false);
    m.environment = kv.get("environment") || m.environment;
    m.serverurl = kv.get("serverurl") || m.serverurl;

    const cmd = String(kv.get("command") || "").trim();
    if (cmd.startsWith("/usr/local/bin/pexe ")) {
      const rest = cmd.slice("/usr/local/bin/pexe ".length).trim();
      const parts = rest.split(/\s+/);
      m.exec_mode = "pexe";
      m.php_container = parts.shift() || "";
      m.php_args = rest.slice(m.php_container.length).trim();
    } else if (cmd.startsWith("/usr/local/bin/dexe ")) {
      const rest = cmd.slice("/usr/local/bin/dexe ".length).trim();
      const mm = rest.match(/^(\S+)\s+\/bin\/sh\s+-lc\s+(.+)$/);
      m.exec_mode = "dexe";
      if (mm) {
        m.any_container = String(mm[1] || "");
        let body = String(mm[2] || "").trim();
        if (body.startsWith("'") && body.endsWith("'")) body = body.slice(1, -1).replace(/'\\''/g, "'");
        if (body.startsWith("\"") && body.endsWith("\"")) body = body.slice(1, -1).replace(/\\"/g, "\"");
        m.dexe_cmd = body;
      }
    } else {
      m.exec_mode = "custom";
      m.custom_cmd = cmd;
    }
    return m;
  };

  const parseSections = (content) => {
    const lines = String(content || "").replace(/\r\n?/g, "\n").split("\n");
    const out = [];
    let current = null;
    let unsupported = false;
    for (const raw of lines) {
      const line = String(raw).trim();
      if (!line || line.startsWith(";") || line.startsWith("#")) continue;
      const h = line.match(/^\[([a-z-]+):([^\]]+)\]$/i);
      if (h) {
        const t = String(h[1] || "").toLowerCase();
        const n = String(h[2] || "").trim();
        if (!["program", "eventlistener", "fcgi-program"].includes(t)) {
          unsupported = true;
          current = null;
          continue;
        }
        current = { type: t, name: n, kv: new Map() };
        out.push(current);
        continue;
      }
      if (!current) continue;
      const at = line.indexOf("=");
      if (at <= 0) continue;
      current.kv.set(line.slice(0, at).trim().toLowerCase(), line.slice(at + 1).trim());
    }
    if (!out.length || unsupported) return [];
    return out.map((x) => modelFromKv(x.type, x.name, x.kv));
  };

  const renumberCards = () => {
    cards().forEach((card, idx) => {
      const t = getValue(card, "section_type", "program");
      const n = getValue(card, "section_name", "section");
      const pane = paneForCard(card);
      if (pane) {
        pane.dataset.index = String(idx);
        const tab = tabForPane(pane.id);
        const tabLabel = tab?.querySelector('[data-role="tab-title"]');
        const tabIndex = tab?.querySelector('[data-role="tab-index"]');
        if (tabIndex) tabIndex.textContent = String(idx + 1);
        if (tabLabel) tabLabel.textContent = `[${t}:${n}]`;
      }
    });
    const oneLeft = sectionTabItems().length <= 1;
    sectionTabItems().forEach((item) => {
      const removeBtn = item.querySelector('[data-act="remove-tab"]');
      if (removeBtn) removeBtn.classList.toggle("d-none", oneLeft);
    });
  };

  const syncAll = () => {
    const raw = !!qs("asRawMode")?.checked;
    const generated = cards().map((card) => {
      syncCard(card);
      return renderSectionConfig(modelFromCard(card)).trimEnd();
    }).join("\n\n").trim();
    renumberCards();

    const rawNode = qs("asRaw");
    if (raw && !state.rawMode && rawNode) {
      if (generated !== "" || String(rawNode.value || "").trim() === "") {
        rawNode.value = generated ? `${generated}\n` : "";
      }
    }
    qs("asTabsWrap")?.classList.toggle("d-none", raw);
    rawNode?.classList.toggle("d-none", !raw);

    if (!state.nameDirty && !raw) {
      const first = cards()[0];
      if (first) qs("asName").value = suggestFileName(getValue(first, "section_type", "program"), getValue(first, "section_name", "worker"));
    }

    const preview = qs("asPreview");
    if (preview) {
      preview.value = raw ? String(rawNode?.value || "") : (generated ? `${generated}\n` : "");
    }
    state.rawMode = raw;
  };

  const addSectionCard = (type = "program", model = null) => {
    const idx = cards().length + 1;
    const card = cardFromModel(model || sectionDefaults(type, idx));
    if (!card) return;
    state.tabSeq += 1;
    const paneId = `asSectPane${state.tabSeq}`;

    const li = document.createElement("li");
    li.className = "nav-item as-section-tab-item";
    li.role = "presentation";
    li.dataset.paneId = paneId;
    li.innerHTML = `<button class="nav-link as-section-tab-link" type="button" role="tab" data-bs-toggle="tab" data-bs-target="#${paneId}" aria-controls="${paneId}" aria-selected="false"><span class="as-tab-index" data-role="tab-index">1</span><span data-role="tab-title">[program:worker]</span></button><button type="button" class="as-tab-remove-btn" data-act="remove-tab" data-pane-id="${paneId}" data-bs-toggle="tooltip" title="Remove section"><i class="bi bi-x-lg"></i></button>`;
    const tabs = qs("asSectionTabs");
    const addItem = qs("asAddSectionItem");
    if (tabs && addItem && addItem.parentElement === tabs) tabs.insertBefore(li, addItem);
    else tabs?.appendChild(li);

    const pane = document.createElement("div");
    pane.className = "tab-pane fade";
    pane.id = paneId;
    pane.role = "tabpanel";
    pane.appendChild(card);
    qs("asSectionPanes")?.appendChild(pane);

    tooltip(card);
    tooltip(li);
    syncAll();
    activatePane(paneId);
  };

  const removeSectionByPaneId = (paneId) => {
    const pane = qs(paneId);
    const tabBtn = tabForPane(paneId);
    const li = tabBtn?.closest(".as-section-tab-item");
    const wasActive = !!tabBtn?.classList.contains("active");
    let nextPaneId = "";

    if (li) {
      const next = li.nextElementSibling;
      const prev = li.previousElementSibling;
      const nextBtn = (next instanceof Element ? next.querySelector('[data-bs-toggle="tab"]') : null);
      const prevBtn = (prev instanceof Element ? prev.querySelector('[data-bs-toggle="tab"]') : null);
      const pick = nextBtn || prevBtn;
      if (pick instanceof Element) {
        const target = String(pick.getAttribute("data-bs-target") || "").trim();
        nextPaneId = target.startsWith("#") ? target.slice(1) : "";
      }
      li.remove();
    }
    if (pane) pane.remove();

    if (!cards().length) {
      addSectionCard("program");
      return;
    }

    if (wasActive && nextPaneId) activatePane(nextPaneId);
    else {
      const firstPane = qs("asSectionPanes")?.querySelector(".tab-pane");
      if (firstPane && firstPane.id) activatePane(firstPane.id);
    }
    syncAll();
  };

  const validateCard = (card) => {
    const m = modelFromCard(card);
    if (!String(m.section_name || "").trim()) return "Section name is required.";
    const cmd = commandForModel(m);
    if (!cmd) return `Command cannot be empty for section '${m.section_name}'.`;
    if (m.exec_mode === "pexe" && (!m.php_container || !m.php_args)) return `Section '${m.section_name}': pexe needs container and args.`;
    if (m.exec_mode === "dexe" && (!m.any_container || !m.dexe_cmd)) return `Section '${m.section_name}': dexe needs container and command.`;
    if (m.exec_mode === "custom" && !m.custom_cmd) return `Section '${m.section_name}': custom command is required.`;
    if (m.section_type === "eventlistener" && !m.events) return `Section '${m.section_name}': events is required.`;
    if (m.section_type === "fcgi-program" && !m.socket) return `Section '${m.section_name}': socket is required.`;
    return "";
  };

  const loadEdit = (name) => req(API).then((r) => {
    if (!r.ok || !r.body.ok) throw new Error(r.body.message || `Load failed (${r.status})`);
    const row = (r.body.items?.supervisor || []).find((x) => String(x.name || "") === name);
    if (!row) throw new Error(`Supervisor config '${name}' not found.`);
    qs("asTitle").textContent = `Edit Supervisor Config: ${name}`;
    qs("asOriginal").value = name;
    qs("asName").value = name;
    state.nameDirty = true;

    const parsed = parseSections(String(row.content || ""));
    const rawMode = !parsed.length;
    qs("asRawMode").checked = rawMode;
    qs("asRaw").value = rawMode ? String(row.content || "") : "";
    clearSectionsUi();
    state.tabSeq = 0;
    state.rawMode = false;
    if (!rawMode) parsed.forEach((m) => addSectionCard(m.section_type, m));
    syncAll();
  });

  const reset = () => {
    qs("asOriginal").value = "";
    qs("asTitle").textContent = "Add Supervisor Config";
    qs("asRawMode").checked = false;
    qs("asRaw").value = "";
    clearSectionsUi();
    state.tabSeq = 0;
    state.rawMode = false;
    state.nameDirty = false;
    addSectionCard("program");
    qs("asName").value = suggestFileName("program", "worker_1");
    err("");
    syncAll();
  };

  qs("asSectionTabs")?.addEventListener("click", (e) => {
    const removeBtn = e.target instanceof Element ? e.target.closest('[data-act="remove-tab"]') : null;
    if (removeBtn) {
      e.preventDefault();
      const paneId = String(removeBtn.getAttribute("data-pane-id") || "").trim();
      if (!paneId) return;
      removeSectionByPaneId(paneId);
      return;
    }
    const btn = e.target instanceof Element ? e.target.closest("#asAddSectionTab") : null;
    if (!btn) return;
    e.preventDefault();
    addSectionCard("program");
  });
  qs("asName")?.addEventListener("input", () => { state.nameDirty = true; });
  qs("asRawMode")?.addEventListener("change", () => syncAll());
  qs("asRaw")?.addEventListener("input", () => syncAll());
  qs("asReset")?.addEventListener("click", () => reset());

  qs("asSectionPanes")?.addEventListener("input", (e) => {
    const card = e.target instanceof Element ? e.target.closest(".as-section-card") : null;
    if (!card) return;
    syncCard(card);
    syncAll();
  });
  qs("asSectionPanes")?.addEventListener("change", (e) => {
    const card = e.target instanceof Element ? e.target.closest(".as-section-card") : null;
    if (!card) return;
    syncCard(card);
    syncAll();
  });

  qs("asForm")?.addEventListener("submit", (e) => {
    e.preventDefault();
    msg("", "");
    err("");
    const name = String(qs("asName")?.value || "").trim();
    if (!name) { err("File name is required."); return; }
    if (!fileOk(name)) { err("Invalid file name. Use letters, numbers, dot, underscore, and hyphen only."); return; }
    const raw = !!qs("asRawMode")?.checked;
    let content = "";
    if (raw) {
      content = String(qs("asRaw")?.value || "");
      if (!content.trim()) { err("Raw config cannot be empty."); return; }
    } else {
      const all = cards();
      if (!all.length) { err("Add at least one section."); return; }
      for (const card of all) {
        const issue = validateCard(card);
        if (issue) { err(issue); return; }
      }
      content = all.map((card) => renderSectionConfig(modelFromCard(card)).trimEnd()).join("\n\n").trim();
      if (!content) { err("Config content cannot be empty."); return; }
      content += "\n";
    }

    req(API, { method: "POST", credentials: "same-origin", cache: "no-store", headers: { Accept: "application/json", "Content-Type": "application/json" }, body: JSON.stringify({ kind: "supervisor", name, original_name: String(qs("asOriginal")?.value || "").trim(), content }) })
      .then((r) => {
        if (!r.ok || !r.body.ok) throw new Error(r.body.message || `Save failed (${r.status})`);
        if (r.body.reload && r.body.reload.ok === false) msg("warning", `${String(r.body.message || "Saved with warning.")} ${String(r.body.reload.message || "")}`.trim());
        else msg("success", String(r.body.message || "Saved."));
        qs("asOriginal").value = name;
        qs("asTitle").textContent = `Edit Supervisor Config: ${name}`;
      })
      .catch((x) => err(x.message || "Save failed."));
  });

  const edit = new URLSearchParams(window.location.search).get("name");
  req(`${API}?action=options`).then((r) => {
    if (!r.ok || !r.body.ok) throw new Error(r.body.message || `Options failed (${r.status})`);
    const o = r.body.options || {};
    state.containers.all = Array.isArray(o.containers?.all) ? o.containers.all.map((x) => String(x || "")).filter((x) => x) : [];
    state.containers.php = Array.isArray(o.containers?.php) ? o.containers.php.map((x) => String(x || "")).filter((x) => x) : [];
    tooltip(document);
    reset();
  }).then(() => {
    if (edit) return loadEdit(edit);
    return null;
  }).catch((e) => msg("error", e.message || "Failed to load page data."));
})();
</script>
