#!/usr/bin/env bash
set -euo pipefail

FIFO="${NOTIFY_FIFO:-/run/notify.fifo}"
ADMIN_ENABLED="${ADMIN_PANEL_AUTOSTART:-1}"
ADMIN_BIND="${ADMIN_PANEL_BIND:-0.0.0.0}"
ADMIN_PORT="${ADMIN_PANEL_PORT:-9911}"

fail() {
  printf '[health] %s\n' "$*" >&2
  exit 1
}

process_running() {
  local pattern="$1"
  pgrep -f -- "$pattern" >/dev/null 2>&1
}

process_running '[/]usr/local/bin/notifierd' || process_running '[n]otifierd' || fail 'notifierd is not running'
[[ -p "$FIFO" ]] || fail "notification FIFO is missing or invalid: $FIFO"

case "$ADMIN_ENABLED" in
  0) ;;
  1)
    process_running "php -S ${ADMIN_BIND}:${ADMIN_PORT}" || fail 'admin panel process is not running'
    wget -q -T 2 -O /dev/null "http://127.0.0.1:${ADMIN_PORT}/" || fail 'admin panel HTTP probe failed'
    ;;
  *) fail "invalid ADMIN_PANEL_AUTOSTART value: $ADMIN_ENABLED" ;;
esac

exit 0
