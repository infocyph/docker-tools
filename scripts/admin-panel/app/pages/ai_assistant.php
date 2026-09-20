<?php
declare(strict_types=1);
?>
<section class="ap-page-head">
  <div>
    <p class="ap-breadcrumb mb-1">System / AI Assistant</p>
    <h2 class="ap-page-title mb-1">AI Operations Assistant</h2>
    <p class="ap-page-sub mb-0">Optional local analysis over bounded, deterministic LocalDevStack diagnostics.</p>
  </div>
  <div>
    <span id="aiProviderBadge" class="badge text-bg-secondary">Checking provider…</span>
  </div>
</section>

<section class="row g-3 mt-1">
  <div class="col-12 col-xl-5">
    <article class="card ap-card h-100">
      <header class="card-header ap-card-head">
        <div>
          <h4 class="ap-card-title mb-1">Analysis Request</h4>
          <p class="ap-card-sub mb-0">Generation happens only when you press Run Analysis.</p>
        </div>
      </header>
      <div class="card-body">
        <div class="mb-3">
          <label class="form-label fw-semibold" for="aiSource">Diagnostic source</label>
          <select id="aiSource" class="form-select">
            <option value="status">Stack status</option>
            <option value="alerts">Alerts</option>
            <option value="slo">SLO</option>
            <option value="db">Database health</option>
            <option value="queue">Queue / scheduler</option>
            <option value="tls">TLS / mTLS</option>
            <option value="volume">Volumes / inodes</option>
            <option value="drift">Configuration drift</option>
            <option value="logs">Log heatmap</option>
            <option value="troubleshoot">Troubleshooting summary</option>
          </select>
        </div>

        <div class="mb-3">
          <label class="form-label fw-semibold" for="aiRequest">Optional instruction</label>
          <textarea
            id="aiRequest"
            class="form-control"
            rows="5"
            maxlength="2000"
            placeholder="Example: Focus on the most likely cause and the safest next checks."
          ></textarea>
          <div class="form-text">The fixed safety prompt remains authoritative. Model output is advisory and never auto-executed.</div>
        </div>

        <div class="mb-3">
          <label class="form-label fw-semibold" for="aiThink">Thinking mode</label>
          <select id="aiThink" class="form-select">
            <option value="inherit">Stack default</option>
            <option value="on">Force thinking on</option>
            <option value="off">Force thinking off</option>
            <option value="auto">Provider / model default</option>
          </select>
          <div class="form-text">This applies only to the current analysis request.</div>
        </div>

        <div class="d-flex gap-2 flex-wrap">
          <button id="aiRun" class="btn ap-primary-btn" type="button">
            <i class="bi bi-stars me-1"></i> Run Analysis
          </button>
          <button id="aiCancel" class="btn ap-ghost-btn" type="button" disabled>
            <i class="bi bi-x-circle me-1"></i> Cancel
          </button>
        </div>

        <div id="aiMessage" class="small mt-3 text-body-secondary">
          No hidden background generation is performed.
        </div>
      </div>
    </article>
  </div>

  <div class="col-12 col-xl-7">
    <article class="card ap-card mb-3">
      <header class="card-header ap-card-head">
        <div>
          <h4 class="ap-card-title mb-1">Context Sent</h4>
          <p class="ap-card-sub mb-0">This is the bounded, redacted context supplied to the local provider.</p>
        </div>
      </header>
      <div class="card-body">
        <pre id="aiContext" class="mb-0 p-3 rounded border bg-body-tertiary" style="max-height: 340px; overflow:auto; white-space:pre-wrap;">Run an analysis to inspect the context.</pre>
      </div>
    </article>

    <article class="card ap-card">
      <header class="card-header ap-card-head">
        <div>
          <h4 class="ap-card-title mb-1">Advisory Answer</h4>
          <p class="ap-card-sub mb-0">Review suggestions before taking any action.</p>
        </div>
      </header>
      <div class="card-body">
        <pre id="aiAnswer" class="mb-0 p-3 rounded border bg-body-tertiary" style="max-height: 460px; overflow:auto; white-space:pre-wrap;">No answer yet.</pre>
      </div>
    </article>
  </div>
</section>

<script>
(() => {
  const base = document.body.dataset.apBase || '';
  const api = base + '/api/ai-assistant';
  const badge = document.getElementById('aiProviderBadge');
  const source = document.getElementById('aiSource');
  const request = document.getElementById('aiRequest');
  const think = document.getElementById('aiThink');
  const run = document.getElementById('aiRun');
  const cancel = document.getElementById('aiCancel');
  const message = document.getElementById('aiMessage');
  const context = document.getElementById('aiContext');
  const answer = document.getElementById('aiAnswer');
  let controller = null;

  const setBusy = (busy) => {
    run.disabled = busy;
    cancel.disabled = !busy;
    source.disabled = busy;
    request.disabled = busy;
    think.disabled = busy;
  };

  fetch(api, {headers: {'Accept': 'application/json'}})
    .then((res) => res.json())
    .then((data) => {
      if (data.available) {
        badge.className = 'badge text-bg-success';
        badge.textContent = 'Local AI available' + (data.model ? ' · ' + data.model : '') + (data.think ? ' · think ' + data.think : '');
      } else {
        badge.className = 'badge text-bg-secondary';
        badge.textContent = 'Local AI unavailable';
      }
    })
    .catch(() => {
      badge.className = 'badge text-bg-secondary';
      badge.textContent = 'Provider status unavailable';
    });

  cancel.addEventListener('click', () => {
    if (controller) {
      controller.abort();
    }
  });

  run.addEventListener('click', async () => {
    setBusy(true);
    message.textContent = 'Collecting deterministic diagnostics and requesting local analysis…';
    context.textContent = 'Collecting…';
    answer.textContent = 'Generating…';

    controller = new AbortController();

    try {
      const res = await fetch(api, {
        method: 'POST',
        headers: {'Accept': 'application/json', 'Content-Type': 'application/json'},
        body: JSON.stringify({
          source: source.value,
          request: request.value.trim(),
          think: think.value
        }),
        signal: controller.signal
      });
      const data = await res.json();
      if (!res.ok || !data.ok) {
        throw new Error(data.message || data.error || 'AI analysis failed.');
      }
      context.textContent = data.context || '(empty context)';
      answer.textContent = data.answer || '(empty answer)';
      message.textContent = 'Analysis completed. Context shown above is the redacted data supplied to the provider.';
    } catch (err) {
      const aborted = err && err.name === 'AbortError';
      context.textContent = aborted ? 'Request cancelled before completion.' : context.textContent;
      answer.textContent = aborted ? 'Cancelled.' : 'Analysis failed.';
      message.textContent = aborted ? 'Analysis cancelled.' : String(err.message || err);
    } finally {
      controller = null;
      setBusy(false);
    }
  });
})();
</script>
