#!/bin/bash
set -euo pipefail

if ! certify >/dev/null 2>&1; then
  echo "[entrypoint] Certification failed" >&2
fi

# Ensure per-version FPM pool dirs exist on the mounted host path
init-fpm-pool-dirs || echo "[entrypoint] init-fpm-pool-dirs failed" >&2

if [[ "${LOGVIEW_AUTOSTART:-0}" == "1" ]]; then
  : "${LOGVIEW_BIND:=0.0.0.0}"
  : "${LOGVIEW_PORT:=9911}"
  : "${LOGVIEW_DOCROOT:=/etc/share/logviewer/app/index.php}"
  : "${LOGVIEW_PHP_SERVER_LOG:=/tmp/logviewer-php-server.log}"

  if [[ ! -f "$LOGVIEW_DOCROOT" ]]; then
    echo "[entrypoint] LogViewer index not found: $LOGVIEW_DOCROOT" >&2
  else
    if ! pgrep -f "php -S ${LOGVIEW_BIND}:${LOGVIEW_PORT}" >/dev/null 2>&1; then
      echo "[entrypoint] Starting Log Viewer on ${LOGVIEW_BIND}:${LOGVIEW_PORT}" >&2
      php -S "${LOGVIEW_BIND}:${LOGVIEW_PORT}" "$LOGVIEW_DOCROOT" >>"$LOGVIEW_PHP_SERVER_LOG" 2>&1 &
    fi
  fi
fi

exec "$@"
