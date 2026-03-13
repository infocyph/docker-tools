    </main>
  </div>
</div>

<script src="<?= htmlspecialchars(($assetPrefix ?? '') . '/public/vendor/bootstrap/js/bootstrap.bundle.min.js?v=' . ($bootstrapJsVer ?? time()), ENT_QUOTES, 'UTF-8') ?>"></script>
<script src="<?= htmlspecialchars(($assetPrefix ?? '') . '/public/vendor/chart.js/chart.umd.min.js?v=' . ($chartJsVer ?? time()), ENT_QUOTES, 'UTF-8') ?>"></script>
<script src="<?= htmlspecialchars(($assetPrefix ?? '') . '/public/js/core.js?v=' . ($coreJsVer ?? time()), ENT_QUOTES, 'UTF-8') ?>"></script>
<script src="<?= htmlspecialchars(($assetPrefix ?? '') . '/public/js/panel.js?v=' . ($panelJsVer ?? time()), ENT_QUOTES, 'UTF-8') ?>"></script>
</body>
</html>
