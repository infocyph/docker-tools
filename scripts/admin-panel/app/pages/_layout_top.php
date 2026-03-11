<?php
declare(strict_types=1);
/** @var string $activePage */
/** @var string $pageTitle */

$assetVer = (int)@filemtime(__DIR__ . '/../../public/css/panel.css');
if ($assetVer <= 0) {
    $assetVer = time();
}

$copyrightYear = (string)date('Y');
$scriptName = (string)($_SERVER['SCRIPT_NAME'] ?? '/index.php');
$basePath = str_replace('\\', '/', dirname($scriptName));
if ($basePath === '.' || $basePath === '/') {
    $basePath = '';
}
$assetPrefix = $basePath === '' ? '' : $basePath;
$routeHref = static function (string $slug = '') use ($basePath): string {
    $clean = trim($slug, '/');
    if ($clean === '' || $clean === 'dashboard') {
        return $basePath === '' ? '/' : $basePath . '/';
    }
    return ($basePath === '' ? '' : $basePath) . '/' . $clean;
};
?>
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width,initial-scale=1"/>
  <title><?= htmlspecialchars($pageTitle, ENT_QUOTES, 'UTF-8') ?></title>

  <script>
    (function () {
      try {
        var mode = localStorage.getItem("ap_theme_mode") || "auto";
        var prefersDark = window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)").matches;
        var actual = mode === "auto" ? (prefersDark ? "dark" : "light") : mode;
        document.documentElement.setAttribute("data-bs-theme", actual === "dark" ? "dark" : "light");
      } catch (e) {
        document.documentElement.setAttribute("data-bs-theme", "light");
      }
    })();
  </script>

  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Outfit:wght@500;600;700;800&family=Public+Sans:wght@400;500;600;700&display=swap" rel="stylesheet">
  <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css" rel="stylesheet">
  <link href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.11.3/font/bootstrap-icons.min.css" rel="stylesheet">
  <link href="<?= htmlspecialchars($assetPrefix . '/public/css/panel.css?v=' . $assetVer, ENT_QUOTES, 'UTF-8') ?>" rel="stylesheet">
</head>
<body class="ap-page" data-ap-base="<?= htmlspecialchars($basePath, ENT_QUOTES, 'UTF-8') ?>">
<div class="ap-shell">
  <aside id="apSidebar" class="ap-sidebar">
    <div class="ap-sidebar-head">
      <a class="ap-brand" href="<?= htmlspecialchars($routeHref('dashboard'), ENT_QUOTES, 'UTF-8') ?>" aria-label="Admin panel home">
        <span class="ap-brand-mark">
          <i class="bi bi-grid-1x2-fill"></i>
        </span>
        <span class="ap-brand-copy">
          <span class="ap-brand-eyebrow">Local Dev Stack</span>
          <strong class="ap-brand-title">Admin Panel</strong>
        </span>
      </a>
      <button id="apSidebarDesktopToggle" class="btn ap-icon-btn d-none d-lg-inline-flex" type="button" aria-label="Collapse sidebar">
        <i class="bi bi-layout-sidebar-inset-reverse"></i>
      </button>
    </div>

    <nav class="ap-nav" aria-label="Sidebar navigation">
      <div class="ap-nav-group">
        <p class="ap-nav-group-title">Main</p>
        <a class="ap-nav-link <?= $activePage === 'dashboard' ? 'active' : '' ?>" href="<?= htmlspecialchars($routeHref('dashboard'), ENT_QUOTES, 'UTF-8') ?>">
          <i class="bi bi-speedometer2"></i>
          <span>Dashboard</span>
        </a>
        <button class="ap-nav-link ap-nav-link-muted" type="button" disabled>
          <i class="bi bi-hdd-stack"></i>
          <span>Containers</span>
          <span class="ap-nav-chip">Soon</span>
        </button>
        <button class="ap-nav-link ap-nav-link-muted" type="button" disabled>
          <i class="bi bi-globe2"></i>
          <span>Domains</span>
          <span class="ap-nav-chip">Soon</span>
        </button>
      </div>

      <div class="ap-nav-group">
        <p class="ap-nav-group-title">Tools</p>
        <a class="ap-nav-link <?= $activePage === 'logs' ? 'active' : '' ?>" href="<?= htmlspecialchars($routeHref('logs'), ENT_QUOTES, 'UTF-8') ?>">
          <i class="bi bi-file-earmark-text"></i>
          <span>Logs</span>
        </a>
        <a class="ap-nav-link <?= $activePage === 'live-stats' ? 'active' : '' ?>" href="<?= htmlspecialchars($routeHref('live-stats'), ENT_QUOTES, 'UTF-8') ?>">
          <i class="bi bi-activity"></i>
          <span>Live Stats</span>
        </a>
        <button class="ap-nav-link ap-nav-link-muted" type="button" disabled>
          <i class="bi bi-gear"></i>
          <span>Settings</span>
          <span class="ap-nav-chip">Soon</span>
        </button>
      </div>
    </nav>

    <div class="ap-sidebar-foot">
      <div class="ap-help-card">
        <p class="ap-help-title mb-1">LDS Status</p>
        <p class="ap-help-text mb-0">Dashboard shell is active. Data adapters will attach next.</p>
      </div>
      <p class="ap-copy mb-0">&copy; <?= htmlspecialchars($copyrightYear, ENT_QUOTES, 'UTF-8') ?> Infocyph</p>
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
          <button id="apSidebarDesktopToggleTop" class="btn ap-icon-btn d-none d-lg-inline-flex" type="button" aria-label="Collapse sidebar">
            <i class="bi bi-layout-sidebar-inset"></i>
          </button>
          <div class="ap-search d-none d-md-flex">
            <i class="bi bi-search"></i>
            <input type="text" class="form-control" placeholder="Search modules, containers, domains..." aria-label="Search"/>
          </div>
        </div>

        <div class="d-flex align-items-center gap-2">
          <button class="btn ap-icon-btn position-relative" type="button" aria-label="Notifications" disabled>
            <i class="bi bi-bell"></i>
            <span class="ap-dot"></span>
          </button>

          <div class="dropdown">
            <button id="apThemeBtn" class="btn ap-icon-btn" type="button" data-bs-toggle="dropdown" aria-expanded="false" aria-label="Theme mode">
              <i id="apThemeIcon" class="bi bi-circle-half"></i>
            </button>
            <ul class="dropdown-menu dropdown-menu-end ap-menu">
              <li><button class="dropdown-item ap-theme-item" type="button" data-theme-mode="auto">Auto</button></li>
              <li><button class="dropdown-item ap-theme-item" type="button" data-theme-mode="light">Light</button></li>
              <li><button class="dropdown-item ap-theme-item" type="button" data-theme-mode="dark">Dark</button></li>
            </ul>
          </div>

          <div class="dropdown">
            <button class="btn ap-user-pill" type="button" data-bs-toggle="dropdown" aria-expanded="false">
              <span class="ap-user-avatar">AD</span>
              <span class="d-none d-md-inline">Admin</span>
            </button>
            <ul class="dropdown-menu dropdown-menu-end ap-menu">
              <li><button class="dropdown-item" type="button" disabled>Profile</button></li>
              <li><button class="dropdown-item" type="button" disabled>Preferences</button></li>
              <li><hr class="dropdown-divider"></li>
              <li><button class="dropdown-item" type="button" disabled>Sign out</button></li>
            </ul>
          </div>
        </div>
      </div>
    </header>

    <main class="ap-main container-fluid py-4">
