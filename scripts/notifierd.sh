#!/bin/bash
set -euo pipefail

FIFO="${NOTIFY_FIFO:-/run/notify.fifo}"
PORT="${NOTIFY_TCP_PORT:-9901}"
PREFIX="${NOTIFY_PREFIX:-__HOST_NOTIFY__}"
TOKEN="${NOTIFY_TOKEN:-}"

TITLE_MAX="${NOTIFY_TITLE_MAX:-100}"
BODY_MAX="${NOTIFY_BODY_MAX:-300}"
[[ "$TITLE_MAX" =~ ^[0-9]{1,4}$ ]] || TITLE_MAX=100
[[ "$BODY_MAX"  =~ ^[0-9]{1,5}$ ]] || BODY_MAX=300

mkdir -p "$(dirname "$FIFO")"

# ensure a clean fifo (only on start)
rm -f "$FIFO"
mkfifo "$FIFO"

_cleanup() {
  # best-effort cleanup
  [[ -n "${SOCAT_PID-}" ]] && kill "$SOCAT_PID" >/dev/null 2>&1 || true
  exec 3>&- 3<&- || true
}
trap _cleanup EXIT INT TERM

echo "[notifier] ready fifo=$FIFO tcp=0.0.0.0:${PORT}" >&2

# Start TCP listener -> FIFO writer
socat -u "TCP-LISTEN:${PORT},fork,reuseaddr" "OPEN:${FIFO},wronly" >/dev/null 2>&1 &
SOCAT_PID=$!

# CRITICAL: keep FIFO open in this process so reads don't behave weirdly
# 3<> opens for read+write, keeping both ends present
exec 3<>"$FIFO"

while IFS= read -r line <&3; do
  [[ -z "${line:-}" ]] && continue

  # Protocol (6 fields): token \t timeout \t urgency \t source \t title \t body
  IFS=$'\t' read -r in_token timeout urgency source title body <<<"$line"
  [[ "${in_token:-}" == "-" ]] && in_token=""

  if [[ -n "$TOKEN" && "${in_token:-}" != "$TOKEN" ]]; then
    echo "[notifier] rejected (bad token)" >&2
    continue
  fi

  timeout="${timeout:-2500}"
  urgency="${urgency:-normal}"
  source="${source:-svc}"

  [[ "$timeout" =~ ^[0-9]{1,6}$ ]] || timeout="2500"
  case "$urgency" in low|normal|critical) ;; *) urgency="normal" ;; esac

  source="${source//$'\n'/ }"; source="${source//$'\r'/ }"; source="${source//$'\t'/ }"
  title="${title//$'\n'/ }";   title="${title//$'\r'/ }";   title="${title//$'\t'/ }"
  body="${body//$'\n'/ }";     body="${body//$'\r'/ }";     body="${body//$'\t'/ }"

  title="[$source] $title"
  title="${title:0:${TITLE_MAX}}"
  body="${body:0:${BODY_MAX}}"

  # Emit for host watcher: PREFIX \t timeout \t urgency \t title \t body
  printf '%s\t%s\t%s\t%s\t%s\n' "$PREFIX" "$timeout" "$urgency" "$title" "$body"
done
