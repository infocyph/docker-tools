#!/bin/bash
set -euo pipefail

FIFO="${NOTIFY_FIFO:-/run/notify.fifo}"
PORT="${NOTIFY_TCP_PORT:-9901}"
PREFIX="${NOTIFY_PREFIX:-__HOST_NOTIFY__}"
TOKEN="${NOTIFY_TOKEN:-}"

# Caps (configurable)
TITLE_MAX="${NOTIFY_TITLE_MAX:-100}"
BODY_MAX="${NOTIFY_BODY_MAX:-300}"

# Validate caps (fallback to defaults if bad)
[[ "$TITLE_MAX" =~ ^[0-9]{1,4}$ ]] || TITLE_MAX=100
[[ "$BODY_MAX"  =~ ^[0-9]{1,5}$ ]] || BODY_MAX=300

mkdir -p "$(dirname "$FIFO")"
rm -f "$FIFO"
mkfifo "$FIFO"

echo "[notifier] ready fifo=$FIFO tcp=0.0.0.0:$PORT" >&2

socat -u "TCP-LISTEN:${PORT},fork,reuseaddr" "FILE:${FIFO}" >/dev/null 2>&1 &

while IFS=$'\n' read -r line < "$FIFO"; do
  [[ -z "${line:-}" ]] && continue

  # New protocol (6 fields):
  # token \t timeout \t urgency \t source \t title \t body
  IFS=$'\t' read -r in_token timeout urgency source title body <<< "$line"

  # Token placeholder → treat as empty
  [[ "${in_token:-}" == "-" ]] && in_token=""

  # Auth only if TOKEN is configured
  if [[ -n "$TOKEN" && "$in_token" != "$TOKEN" ]]; then
    echo "[notifier] rejected (bad token)" >&2
    continue
  fi

  timeout="${timeout:-2500}"
  urgency="${urgency:-normal}"
  source="${source:-svc}"

  [[ "$timeout" =~ ^[0-9]{1,6}$ ]] || timeout="2500"
  case "$urgency" in low|normal|critical) ;; *) urgency="normal" ;; esac

  # Sanitize (keep protocol stable)
  source="${source//$'\n'/ }"; source="${source//$'\r'/ }"; source="${source//$'\t'/ }"
  title="${title//$'\n'/ }";   title="${title//$'\r'/ }";   title="${title//$'\t'/ }"
  body="${body//$'\n'/ }";     body="${body//$'\r'/ }";     body="${body//$'\t'/ }"

  # Prefix title with source
  title="[$source] $title"

  # Apply caps
  title="${title:0:${TITLE_MAX}}"
  body="${body:0:${BODY_MAX}}"

  echo -e "${PREFIX}\t${timeout}\t${urgency}\t${title}\t${body}"
done
