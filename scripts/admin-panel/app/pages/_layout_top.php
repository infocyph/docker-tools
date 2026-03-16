<?php
declare(strict_types=1);
/** @var string $activePage */
/** @var string $pageTitle */

$panelCssVer = (int)@filemtime(__DIR__ . '/../../public/css/panel.css');
if ($panelCssVer <= 0) {
    $panelCssVer = time();
}
$bootstrapCssVer = (int)@filemtime(__DIR__ . '/../../public/vendor/bootstrap/css/bootstrap.min.css');
if ($bootstrapCssVer <= 0) {
    $bootstrapCssVer = $panelCssVer;
}
$bootstrapIconsCssVer = (int)@filemtime(__DIR__ . '/../../public/vendor/bootstrap-icons/bootstrap-icons.min.css');
if ($bootstrapIconsCssVer <= 0) {
    $bootstrapIconsCssVer = $panelCssVer;
}
$fontAwesomeCssVer = (int)@filemtime(__DIR__ . '/../../public/vendor/fontawesome/css/all.min.css');
if ($fontAwesomeCssVer <= 0) {
    $fontAwesomeCssVer = $panelCssVer;
}
$coreCssVer = (int)@filemtime(__DIR__ . '/../../public/css/core.css');
if ($coreCssVer <= 0) {
    $coreCssVer = $panelCssVer;
}
$panelJsVer = (int)@filemtime(__DIR__ . '/../../public/js/panel.js');
if ($panelJsVer <= 0) {
    $panelJsVer = $panelCssVer;
}
$bootstrapJsVer = (int)@filemtime(__DIR__ . '/../../public/vendor/bootstrap/js/bootstrap.bundle.min.js');
if ($bootstrapJsVer <= 0) {
    $bootstrapJsVer = $panelJsVer;
}
$chartJsVer = (int)@filemtime(__DIR__ . '/../../public/vendor/chart.js/chart.umd.min.js');
if ($chartJsVer <= 0) {
    $chartJsVer = $panelJsVer;
}
$coreJsVer = (int)@filemtime(__DIR__ . '/../../public/js/core.js');
if ($coreJsVer <= 0) {
    $coreJsVer = $panelJsVer;
}

$copyrightYear = (string)date('Y');
$scriptName = (string)($_SERVER['SCRIPT_NAME'] ?? '/index.php');
$basePath = str_replace('\\', '/', dirname($scriptName));
if ($basePath === '.' || $basePath === '/') {
    $basePath = '';
}
$assetPrefix = $basePath;
$routeHref = static function (string $slug = '') use ($basePath): string {
    $clean = trim($slug, '/');
    if ($clean === '' || $clean === 'dashboard') {
        return $basePath === '' ? '/' : $basePath . '/';
    }
    return $basePath . '/' . $clean;
};
$monitoringActive = in_array($activePage, ['logs', 'docker-logs', 'db-health', 'queue-health', 'slo-view', 'log-heatmap', 'drift-monitor', 'alerts', 'synthetic-flows', 'tls-monitor', 'volume-monitor', 'live-stats'], true);
$topbarPageTitle = trim((string)preg_replace('/\s*\|\s*Admin Panel\s*$/i', '', $pageTitle));
if ($topbarPageTitle === '') {
    $topbarPageTitle = $pageTitle;
}
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
  <link href="<?= htmlspecialchars($assetPrefix . '/public/vendor/bootstrap/css/bootstrap.min.css?v=' . $bootstrapCssVer, ENT_QUOTES, 'UTF-8') ?>" rel="stylesheet">
  <link href="<?= htmlspecialchars($assetPrefix . '/public/vendor/bootstrap-icons/bootstrap-icons.min.css?v=' . $bootstrapIconsCssVer, ENT_QUOTES, 'UTF-8') ?>" rel="stylesheet">
  <link href="<?= htmlspecialchars($assetPrefix . '/public/vendor/fontawesome/css/all.min.css?v=' . $fontAwesomeCssVer, ENT_QUOTES, 'UTF-8') ?>" rel="stylesheet">
  <link href="<?= htmlspecialchars($assetPrefix . '/public/css/core.css?v=' . $coreCssVer, ENT_QUOTES, 'UTF-8') ?>" rel="stylesheet">
  <link href="<?= htmlspecialchars($assetPrefix . '/public/css/panel.css?v=' . $panelCssVer, ENT_QUOTES, 'UTF-8') ?>" rel="stylesheet">
</head>
<body class="ap-page" data-ap-base="<?= htmlspecialchars($basePath, ENT_QUOTES, 'UTF-8') ?>">
<div class="ap-shell">
  <aside id="apSidebar" class="ap-sidebar">
    <div class="ap-sidebar-head">
      <a class="ap-brand" href="<?= htmlspecialchars($routeHref('dashboard'), ENT_QUOTES, 'UTF-8') ?>" aria-label="Admin panel home">
        <span class="ap-brand-mark">
          <i class="bi bi-boxes"></i>
        </span>
        <span class="ap-brand-copy">
          <span class="ap-brand-eyebrow">LocalDevStack</span>
          <strong class="ap-brand-title">Admin Panel</strong>
        </span>
      </a>
      <button id="apSidebarDesktopToggle" class="btn ap-icon-btn d-none d-lg-inline-flex" type="button" aria-label="Collapse sidebar">
        <i class="bi bi-layout-sidebar-inset-reverse"></i>
      </button>
    </div>

    <nav class="ap-nav" aria-label="Sidebar navigation">
      <div class="ap-nav-group">
        <p class="ap-nav-group-title">System</p>
        <a class="ap-nav-link <?= $activePage === 'dashboard' ? 'active' : '' ?>" href="<?= htmlspecialchars($routeHref('dashboard'), ENT_QUOTES, 'UTF-8') ?>">
          <i class="bi bi-speedometer2"></i>
          <span>Dashboard</span>
        </a>
        <div class="ap-nav-tree <?= $monitoringActive ? 'is-open' : '' ?>">
          <button
            class="ap-nav-link ap-nav-link-toggle <?= $monitoringActive ? 'active' : '' ?>"
            type="button"
            data-nav-toggle="monitoring"
            aria-expanded="<?= $monitoringActive ? 'true' : 'false' ?>"
            aria-controls="apNavMonitoringSubmenu"
          >
            <i class="bi bi-binoculars"></i>
            <span>Monitoring</span>
            <i class="bi bi-chevron-down ap-nav-caret" aria-hidden="true"></i>
          </button>
          <div id="apNavMonitoringSubmenu" class="ap-nav-submenu <?= $monitoringActive ? 'is-open' : '' ?>" aria-label="Monitoring submenu">
            <a class="ap-nav-link ap-nav-link-sub <?= $activePage === 'docker-logs' ? 'active' : '' ?>" href="<?= htmlspecialchars($routeHref('docker-logs'), ENT_QUOTES, 'UTF-8') ?>">
              <i class="bi bi-terminal-split"></i>
              <span>Docker Logs</span>
            </a>
            <a class="ap-nav-link ap-nav-link-sub <?= $activePage === 'db-health' ? 'active' : '' ?>" href="<?= htmlspecialchars($routeHref('db-health'), ENT_QUOTES, 'UTF-8') ?>">
              <i class="bi bi-database-check"></i>
              <span>DB / Redis Health</span>
            </a>
            <a class="ap-nav-link ap-nav-link-sub <?= $activePage === 'queue-health' ? 'active' : '' ?>" href="<?= htmlspecialchars($routeHref('queue-health'), ENT_QUOTES, 'UTF-8') ?>">
              <i class="bi bi-list-task"></i>
              <span>Queue / Cron</span>
            </a>
            <a class="ap-nav-link ap-nav-link-sub <?= $activePage === 'slo-view' ? 'active' : '' ?>" href="<?= htmlspecialchars($routeHref('slo-view'), ENT_QUOTES, 'UTF-8') ?>">
              <i class="bi bi-speedometer"></i>
              <span>Error Budget / SLO</span>
            </a>
            <a class="ap-nav-link ap-nav-link-sub <?= $activePage === 'log-heatmap' ? 'active' : '' ?>" href="<?= htmlspecialchars($routeHref('log-heatmap'), ENT_QUOTES, 'UTF-8') ?>">
              <i class="bi bi-grid-3x3-gap"></i>
              <span>Log Error Heatmap</span>
            </a>
            <a class="ap-nav-link ap-nav-link-sub <?= $activePage === 'drift-monitor' ? 'active' : '' ?>" href="<?= htmlspecialchars($routeHref('drift-monitor'), ENT_QUOTES, 'UTF-8') ?>">
              <i class="bi bi-sliders"></i>
              <span>Config Drift</span>
            </a>
            <a class="ap-nav-link ap-nav-link-sub <?= $activePage === 'logs' ? 'active' : '' ?>" href="<?= htmlspecialchars($routeHref('logs'), ENT_QUOTES, 'UTF-8') ?>">
              <i class="bi bi-file-earmark-text"></i>
              <span>File Logs</span>
            </a>
            <a class="ap-nav-link ap-nav-link-sub <?= $activePage === 'synthetic-flows' ? 'active' : '' ?>" href="<?= htmlspecialchars($routeHref('synthetic-flows'), ENT_QUOTES, 'UTF-8') ?>">
              <i class="bi bi-diagram-3"></i>
              <span>Synthetic Flows</span>
            </a>
            <a class="ap-nav-link ap-nav-link-sub <?= $activePage === 'tls-monitor' ? 'active' : '' ?>" href="<?= htmlspecialchars($routeHref('tls-monitor'), ENT_QUOTES, 'UTF-8') ?>">
              <i class="bi bi-shield-lock"></i>
              <span>TLS / mTLS</span>
            </a>
            <a class="ap-nav-link ap-nav-link-sub <?= $activePage === 'volume-monitor' ? 'active' : '' ?>" href="<?= htmlspecialchars($routeHref('volume-monitor'), ENT_QUOTES, 'UTF-8') ?>">
              <i class="bi bi-hdd-stack"></i>
              <span>Volume Growth</span>
            </a>
            <a class="ap-nav-link ap-nav-link-sub <?= $activePage === 'alerts' ? 'active' : '' ?>" href="<?= htmlspecialchars($routeHref('alerts'), ENT_QUOTES, 'UTF-8') ?>">
              <i class="bi bi-bell"></i>
              <span>Alert Rules</span>
            </a>
            <a class="ap-nav-link ap-nav-link-sub <?= $activePage === 'live-stats' ? 'active' : '' ?>" href="<?= htmlspecialchars($routeHref('live-stats'), ENT_QUOTES, 'UTF-8') ?>">
              <i class="bi bi-activity"></i>
              <span>Live Stats</span>
            </a>
          </div>
        </div>
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
        <button class="ap-nav-link ap-nav-link-muted" type="button" disabled>
          <i class="bi bi-book-half"></i>
          <span>Documentation</span>
        </button>
        <button class="ap-nav-link ap-nav-link-muted" type="button" disabled>
          <i class="bi bi-shield-check"></i>
          <span>Release Notes</span>
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
          <div class="ap-topbar-page d-none d-xl-block">
            <p class="ap-topbar-label mb-0">Workspace</p>
            <strong class="ap-topbar-value"><?= htmlspecialchars($topbarPageTitle, ENT_QUOTES, 'UTF-8') ?></strong>
          </div>
          <div class="ap-search d-none d-md-flex">
            <i class="bi bi-search"></i>
            <input type="text" class="form-control" placeholder="Search modules, containers, domains..." aria-label="Search"/>
            <kbd class="ap-search-kbd">Ctrl K</kbd>
          </div>
        </div>

        <div class="d-flex align-items-center gap-2 ap-topbar-actions">
          <button class="btn ap-icon-btn position-relative" type="button" aria-label="Notifications" disabled>
            <i class="bi bi-bell"></i>
            <span class="ap-dot"></span>
          </button>
          <button class="btn ap-icon-btn position-relative d-none d-md-inline-grid" type="button" aria-label="Messages" disabled>
            <i class="bi bi-chat-left-text"></i>
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
              <span class="d-none d-md-grid ap-user-meta">
                <span class="ap-user-name">Admin</span>
                <span class="ap-user-role">Super Admin</span>
              </span>
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
