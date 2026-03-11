#!/bin/bash
set -euo pipefail

certify >/dev/null 2>&1 || echo "[entrypoint] Certification failed" >&2
init-fpm-pool-dirs >/dev/null 2>&1 || echo "[entrypoint] init-fpm-pool-dirs failed" >&2

if [[ "${ADMIN_PANEL_AUTOSTART:-1}" == "1" ]]; then
  : "${ADMIN_PANEL_BIND:=0.0.0.0}"
  : "${ADMIN_PANEL_PORT:=9911}"
  : "${ADMIN_PANEL_DOCROOT:=/etc/share/admin-panel}"
  : "${ADMIN_PANEL_PHP_SERVER_LOG:=/tmp/admin-panel-php-server.log}"

  if [[ ! -d "$ADMIN_PANEL_DOCROOT" ]]; then
    echo "[entrypoint] Admin panel docroot not found: $ADMIN_PANEL_DOCROOT" >&2
  elif [[ ! -f "$ADMIN_PANEL_DOCROOT/index.php" ]]; then
    echo "[entrypoint] Admin panel index not found: $ADMIN_PANEL_DOCROOT/index.php" >&2
  elif [[ ! -f "$ADMIN_PANEL_DOCROOT/router.php" ]]; then
    echo "[entrypoint] Admin panel router not found: $ADMIN_PANEL_DOCROOT/router.php" >&2
  else
    if ! pgrep -f "php -S ${ADMIN_PANEL_BIND}:${ADMIN_PANEL_PORT}" >/dev/null 2>&1; then
      php -S "${ADMIN_PANEL_BIND}:${ADMIN_PANEL_PORT}" -t "$ADMIN_PANEL_DOCROOT" "$ADMIN_PANEL_DOCROOT/router.php" >>"$ADMIN_PANEL_PHP_SERVER_LOG" 2>&1 &
    fi
  fi
fi

exec "$@"
