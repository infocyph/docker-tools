<?php
declare(strict_types=1);

require_once __DIR__ . '/../bootstrap.php';

$activePage = 'logs';
$pageTitle  = 'Log Viewer';

require_once __DIR__ . '/_layout_top.php';
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

          <div>
            <div class="lv-muted small">Active</div>
            <div class="small" id="activeFile">—</div>
          </div>

          <div class="ms-auto d-flex align-items-center gap-2">

            <button class="btn btn-sm lv-btn" id="btnLive">
              Live
            </button>

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
          <div class="ms-auto d-flex gap-2">
            <button class="btn btn-sm lv-btn" id="prevPage">‹</button>
            <div class="small" id="pageInfo">1 / 1</div>
            <button class="btn btn-sm lv-btn" id="nextPage">›</button>
          </div>
        </div>

      </div>
    </section>

  </div>

  <script>
    window.LV_BOOT = {
      page: 'logs',
      domain: <?= json_encode((string)($_GET['domain'] ?? '')) ?>
    };
  </script>

  <script src="/assets/js/app.js"></script>

<?php require_once __DIR__ . '/_layout_bottom.php'; ?>

