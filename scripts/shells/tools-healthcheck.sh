#!/usr/bin/env bash
set -euo pipefail

FIFO="${NOTIFY_FIFO:-/run/notify.fifo}"
ADMIN_ENABLED="${ADMIN_PANEL_AUTOSTART:-1}"
ADMIN_PORT="${ADMIN_PANEL_PORT:-9911}"
ADMIN_PID_FILE="${ADMIN_PANEL_PID_FILE:-/run/admin-panel.pid}"

fail() {
  printf '[health] %s\n' "$*" >&2
  exit 1
}

process_running() {
  local pattern="$1"
  pgrep -f -- "$pattern" >/dev/null 2>&1
}

pidfile_running() {
  local file="$1" pid=""
  [[ -r "$file" ]] || return 1
  read -r pid <"$file" || return 1
  [[ "$pid" =~ ^[0-9]+$ ]] || return 1
  kill -0 "$pid" >/dev/null 2>&1
}

process_running '[/]usr/local/bin/notifierd' || process_running '[n]otifierd' || fail 'notifierd is not running'
[[ -p "$FIFO" ]] || fail "notification FIFO is missing or invalid: $FIFO"

case "$ADMIN_ENABLED" in
  0) ;;
  1)
    pidfile_running "$ADMIN_PID_FILE" || fail 'admin panel process is not running'
    wget -q -T 2 -O /dev/null "http://127.0.0.1:${ADMIN_PORT}/" || fail 'admin panel HTTP probe failed'
    ;;
  *) fail "invalid ADMIN_PANEL_AUTOSTART value: $ADMIN_ENABLED" ;;
esac

exit 0
