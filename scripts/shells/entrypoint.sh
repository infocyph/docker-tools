#!/bin/bash
set -euo pipefail

HOST_OS="$(printf '%s' "${HOST_OS:-linux}" | tr '[:upper:]' '[:lower:]')" && export HOST_OS
certify >/dev/null 2>&1 || echo "[entrypoint] Certification failed" >&2
init-php-dirs >/dev/null 2>&1 || echo "[entrypoint] init-php-dirs failed" >&2
git-default >/dev/null 2>&1 || echo "[entrypoint] git-default failed" >&2

if [[ "${ADMIN_PANEL_AUTOSTART:-1}" == "1" ]]; then
  : "${ADMIN_PANEL_BIND:=0.0.0.0}"
  : "${ADMIN_PANEL_PORT:=9911}"
  : "${ADMIN_PANEL_DOCROOT:=/etc/share/admin-panel}"
  : "${ADMIN_PANEL_PHP_SERVER_LOG:=/tmp/admin-panel-php-server.log}"
  : "${ADMIN_PANEL_PID_FILE:=/run/admin-panel.pid}"

  [[ "$ADMIN_PANEL_PORT" =~ ^[0-9]{1,5}$ ]] || {
    echo "[entrypoint] Invalid admin panel port: $ADMIN_PANEL_PORT" >&2
    exit 1
  }

  rm -f -- "$ADMIN_PANEL_PID_FILE"

  if [[ ! -d "$ADMIN_PANEL_DOCROOT" ]]; then
    echo "[entrypoint] Admin panel docroot not found: $ADMIN_PANEL_DOCROOT" >&2
  elif [[ ! -f "$ADMIN_PANEL_DOCROOT/index.php" ]]; then
    echo "[entrypoint] Admin panel index not found: $ADMIN_PANEL_DOCROOT/index.php" >&2
  elif [[ ! -f "$ADMIN_PANEL_DOCROOT/router.php" ]]; then
    echo "[entrypoint] Admin panel router not found: $ADMIN_PANEL_DOCROOT/router.php" >&2
  else
    if ! pgrep -f "php -S ${ADMIN_PANEL_BIND}:${ADMIN_PANEL_PORT}" >/dev/null 2>&1; then
      php -S "${ADMIN_PANEL_BIND}:${ADMIN_PANEL_PORT}" -t "$ADMIN_PANEL_DOCROOT" "$ADMIN_PANEL_DOCROOT/router.php" >>"$ADMIN_PANEL_PHP_SERVER_LOG" 2>&1 &
      printf '%s\n' "$!" >"$ADMIN_PANEL_PID_FILE"
    else
      pgrep -f "php -S ${ADMIN_PANEL_BIND}:${ADMIN_PANEL_PORT}" | head -n 1 >"$ADMIN_PANEL_PID_FILE"
    fi
  fi
else
  rm -f -- "${ADMIN_PANEL_PID_FILE:-/run/admin-panel.pid}"
fi

exec "$@"
