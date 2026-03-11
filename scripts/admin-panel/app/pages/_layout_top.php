<?php
declare(strict_types=1);
/** @var string $activePage */
/** @var string $pageTitle */

$assetVer = (int)@filemtime(__DIR__ . '/../../public/css/panel.css');
if ($assetVer <= 0) {
    $assetVer = time();
}

$copyrightYear = (string)date('Y');
?>
<!doctype html>
<html lang="en" data-bs-theme="light">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width,initial-scale=1"/>
  <title><?= htmlspecialchars($pageTitle, ENT_QUOTES, 'UTF-8') ?></title>

  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;500;600;700;800&family=Sora:wght@600;700;800&display=swap" rel="stylesheet">
  <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css" rel="stylesheet">
  <link href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.11.3/font/bootstrap-icons.min.css" rel="stylesheet">
  <link href="./public/css/panel.css?v=<?= $assetVer ?>" rel="stylesheet">
</head>
<body>
<div class="ap-app">
  <aside id="apSidebar" class="ap-sidebar">
    <div class="ap-brand-wrap">
      <div class="ap-brand-icon">
        <i class="bi bi-grid-1x2-fill"></i>
      </div>
      <div>
        <p class="ap-brand-eyebrow mb-0">Local Dev Stack</p>
        <h1 class="ap-brand-title mb-0">Admin Panel</h1>
      </div>
    </div>

    <nav class="ap-nav">
      <p class="ap-nav-label">Core</p>
      <a class="ap-nav-link <?= $activePage === 'dashboard' ? 'active' : '' ?>" href="?p=dashboard">
        <i class="bi bi-speedometer2"></i>
        <span>Dashboard</span>
      </a>

      <p class="ap-nav-label">Coming Soon</p>
      <button class="ap-nav-link" type="button" disabled>
        <i class="bi bi-hdd-network"></i>
        <span>Containers</span>
        <span class="ap-chip">Soon</span>
      </button>
      <button class="ap-nav-link" type="button" disabled>
        <i class="bi bi-globe2"></i>
        <span>Domains</span>
        <span class="ap-chip">Soon</span>
      </button>
      <button class="ap-nav-link" type="button" disabled>
        <i class="bi bi-bell"></i>
        <span>Alerts</span>
        <span class="ap-chip">Soon</span>
      </button>
      <button class="ap-nav-link" type="button" disabled>
        <i class="bi bi-gear"></i>
        <span>Settings</span>
        <span class="ap-chip">Soon</span>
      </button>
    </nav>

    <div class="ap-sidebar-foot">
      <div class="ap-foot-card">
        <p class="ap-foot-title mb-0">&copy; <?= htmlspecialchars($copyrightYear, ENT_QUOTES, 'UTF-8') ?> Infocyph</p>
      </div>
    </div>
  </aside>

  <div class="ap-overlay" id="apOverlay" aria-hidden="true"></div>

  <div class="ap-main-wrap">
    <header class="ap-topbar">
      <div class="container-fluid ap-topbar-inner">
        <div class="d-flex align-items-center gap-2">
          <button id="apSidebarToggle" class="btn ap-icon-btn d-lg-none" type="button" aria-label="Toggle sidebar">
            <i class="bi bi-list"></i>
          </button>
          <div class="ap-search d-none d-md-flex">
            <i class="bi bi-search"></i>
            <input type="text" class="form-control" placeholder="Search modules, commands, services..." aria-label="Search"/>
          </div>
        </div>

        <div class="d-flex align-items-center gap-2">
          <button id="apThemeBtn" class="btn ap-icon-btn" type="button" aria-label="Toggle theme">
            <i class="bi bi-moon-stars"></i>
          </button>
          <button class="btn ap-icon-btn position-relative" type="button" aria-label="Notifications" disabled>
            <i class="bi bi-bell"></i>
            <span class="ap-dot"></span>
          </button>
          <div class="ap-user-pill">
            <span class="ap-user-avatar">AD</span>
            <span class="d-none d-md-inline">Admin</span>
          </div>
        </div>
      </div>
    </header>

    <main class="ap-main container-fluid py-4">
