<?php
declare(strict_types=1);
$activePage = 'logs';
$pageTitle  = 'Log Viewer';

$assetVer = (int)@filemtime(__DIR__ . '/../../public/js/app.js');
if ($assetVer <= 0) { $assetVer = time(); }

require __DIR__ . '/_layout_top.php';
?>

  <div class="row g-3">

    <!-- Sidebar -->
    <aside class="col-12 col-lg-3">
      <div class="card lv-card">
        <div class="card-header lv-card-header d-flex gap-2 align-items-center">
          <select class="form-select form-select-sm lv-select" id="serviceFilter">
            <option value="">All Services</option>
          </select>

          <select class="form-select form-select-sm lv-select d-none"
                  id="domainFilter">
            <option value="">All Domains</option>
          </select>

          <button class="btn btn-sm lv-btn ms-auto" id="btnRefreshFiles">
            Refresh
          </button>
        </div>

        <div class="card-body p-0">
          <div class="lv-filelist" id="fileList"></div>
        </div>
      </div>
    </aside>

    <!-- Main -->
    <section class="col-12 col-lg-9">
      <div class="card lv-card">

        <div class="card-header lv-card-header d-flex flex-wrap align-items-center gap-2">

          <div class="me-2">
            <div class="lv-muted small">Active</div>
            <div class="small text-truncate" style="max-width:520px" id="activeFile">—</div>
          </div>

          <!-- ✅ Capsules -->
          <div class="d-flex flex-wrap gap-2 align-items-center" id="fileCaps">
            <!-- populated by JS -->
          </div>

          <div class="ms-auto d-flex align-items-center gap-2">

            <span class="lv-muted small me-1">Entries:</span>
            <button class="btn btn-sm lv-btn" id="btnLive">Refresh</button>
            <button class="btn btn-sm lv-btn" id="btnStream">Stream</button>
            <a class="btn btn-sm lv-btn" id="btnExport" href="#" target="_blank" rel="noopener">Export</a>
            <button class="btn btn-sm lv-btn" id="btnNoise">Noise</button>
            <div class="dropdown">
              <button class="btn btn-sm lv-btn dropdown-toggle" data-bs-toggle="dropdown" aria-expanded="false">Actions</button>
              <ul class="dropdown-menu" id="actionMenu"></ul>
            </div>

            <button class="btn btn-sm lv-btn" id="btnSaveView">Save View</button>
            <button class="btn btn-sm lv-btn" id="btnLoadView">Load View</button>

            <a class="btn btn-sm lv-btn" id="btnDownload" href="#" target="_blank" rel="noopener">Download</a>

            <select class="form-select form-select-sm lv-select"
                    id="perPage"
                    style="width:130px">
              <option value="25">25 per page</option>
              <option value="50">50 per page</option>
              <option value="100">100 per page</option>
            </select>

            <a class="btn btn-sm lv-btn"
               id="btnRaw"
               href="#"
               target="_blank"
               rel="noopener">
              Raw
            </a>

          </div>

        </div>

        <div class="card-body p-0">
          <div class="lv-entries" id="entries"></div>
        </div>

        <div class="card-footer lv-card-footer d-flex align-items-center">
          <div class="lv-muted small" id="stats">—</div>
          <div class="ms-auto d-flex gap-2 align-items-center">
            <button class="btn btn-sm lv-btn" id="prevPage">‹</button>
            <div class="small" id="pageInfo">1 / 1</div>
            <button class="btn btn-sm lv-btn" id="nextPage">›</button>
          </div>
        </div>

      </div>
    </section>

  </div>


  <!-- Noise suppression modal -->
  <div class="modal fade" id="noiseModal" tabindex="-1" aria-hidden="true">
    <div class="modal-dialog modal-lg modal-dialog-scrollable">
      <div class="modal-content" style="background: var(--lv-card-bg); border: 1px solid var(--lv-card-border);">
        <div class="modal-header">
          <h5 class="modal-title">Noise Suppression</h5>
          <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
        </div>
        <div class="modal-body">
          <div class="form-check form-switch mb-3">
            <input class="form-check-input" type="checkbox" role="switch" id="noiseEnabled">
            <label class="form-check-label" for="noiseEnabled">Hide lines matching patterns</label>
          </div>

          <label class="form-label small lv-muted">Regex patterns (one per line). Example: <code>favicon\.ico</code></label>
          <textarea class="form-control lv-ig" id="noisePatterns" rows="10" placeholder="healthcheck\nfavicon\.ico\nGET /metrics"></textarea>

          <div class="form-text lv-muted mt-2">
            Patterns are applied to <b>summary</b> and <b>body</b>. Invalid regex will be ignored.
          </div>
        </div>
        <div class="modal-footer">
          <button class="btn btn-sm lv-btn" id="btnNoiseSave" data-bs-dismiss="modal">Save</button>
        </div>
      </div>
    </div>
  </div>

  <!-- Exec output modal -->
  <div class="modal fade" id="execModal" tabindex="-1" aria-hidden="true">
    <div class="modal-dialog modal-xl modal-dialog-scrollable">
      <div class="modal-content" style="background: var(--lv-card-bg); border: 1px solid var(--lv-card-border);">
        <div class="modal-header">
          <h5 class="modal-title" id="execTitle">Action Output</h5>
          <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
        </div>
        <div class="modal-body">
          <pre class="lv-pre" id="execOut" style="min-height: 300px;"></pre>
        </div>
      </div>
    </div>
  </div>

  <script>
    window.LV_BOOT = {
      page: 'logs',
      domain: <?= json_encode((string)($_GET['domain'] ?? ''), JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE) ?>
    };
  </script>

  <script src="/assets/js/app.js?v=<?= $assetVer ?>"></script>

<?php require __DIR__ . '/_layout_bottom.php'; ?>



