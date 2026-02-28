<?php
declare(strict_types=1);
/** @var string $activePage */
/** @var string $pageTitle */
?>
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width,initial-scale=1"/>
  <title><?= htmlspecialchars($pageTitle, ENT_QUOTES, 'UTF-8') ?></title>

  <script>
    // Apply theme as early as possible (no flash)
    (function(){
      try{
        var mode = localStorage.getItem("lv_theme_mode") || "auto";
        var prefersDark = window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)").matches;
        var actual = (mode === "auto") ? (prefersDark ? "dark" : "light") : mode;
        document.documentElement.setAttribute("data-bs-theme", actual);
      }catch(e){}
    })();
  </script>

  <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css" rel="stylesheet">
  <link href="/assets/css/style.css" rel="stylesheet">
</head>

<body class="lv-page-<?= htmlspecialchars($activePage, ENT_QUOTES, 'UTF-8') ?>">

<div class="lv-shell">

  <header class="lv-topbar border-bottom">
    <div class="container-fluid py-3">

      <div class="d-flex align-items-center gap-3">

        <div class="dropdown">
          <button class="btn btn-sm lv-btn dropdown-toggle"
                  data-bs-toggle="dropdown"
                  aria-expanded="false">
            <?= $activePage === 'logs' ? 'Log Viewer' : 'Dashboard' ?>
          </button>

          <ul class="dropdown-menu">
            <li><a class="dropdown-item" href="/?p=dashboard">Dashboard</a></li>
            <li><a class="dropdown-item" href="/?p=logs">Log Viewer</a></li>
          </ul>
        </div>

        <div class="lv-dot"></div>

        <div class="ms-auto d-flex align-items-center gap-3">

          <?php if ($activePage === 'logs'): ?>
            <div class="lv-search input-group input-group-sm">
              <span class="input-group-text lv-ig-icon">⌕</span>
              <input id="q" class="form-control lv-ig" placeholder="Search logs...">

              <!-- ✅ Search mode: tail vs file -->
              <select id="searchMode" class="form-select form-select-sm lv-select" style="max-width: 135px;">
                <option value="tail">Tail</option>
                <option value="file">File</option>
              </select>

              <button class="btn btn-sm lv-btn" id="btnSearch">Search</button>
            </div>
          <?php endif; ?>

          <div class="d-flex align-items-center gap-2">
            <span class="lv-muted small d-none d-md-inline">Theme</span>
            <div class="form-check form-switch m-0">
              <input class="form-check-input lv-switch"
                     type="checkbox"
                     role="switch"
                     id="themeToggle">
              <label class="form-check-label small"
                     for="themeToggle"
                     id="themeLabel">Auto</label>
            </div>
          </div>

        </div>

      </div>

    </div>
  </header>

  <main class="lv-main">
    <div class="container-fluid py-3">
