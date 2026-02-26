#!/bin/bash
set -euo pipefail

if ! certify >/dev/null 2>&1; then
  echo "[entrypoint] Certification failed" >&2
fi

# Optional: start Log Viewer in background (keep main CMD running)
# Enable by setting: LOGVIEW_AUTOSTART=1
if [[ "${LOGVIEW_AUTOSTART:-0}" == "1" ]]; then
  : "${LOGVIEW_BIND:=0.0.0.0}"
  : "${LOGVIEW_PORT:=9911}"

  # Avoid spawning twice (in case of restart scripts)
  if ! pgrep -f "php -S ${LOGVIEW_BIND}:${LOGVIEW_PORT} .*etc/share/logviewer/app/index.php" >/dev/null 2>&1; then
    echo "[entrypoint] Starting Log Viewer on ${LOGVIEW_BIND}:${LOGVIEW_PORT}" >&2
    php -S "${LOGVIEW_BIND}:${LOGVIEW_PORT}" /etc/share/logviewer/app/index.php >/dev/null 2>&1 &
  fi
fi

exec "$@"