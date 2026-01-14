#!/bin/bash
set -euo pipefail

PORT="${NOTIFY_TCP_PORT:-9901}"
PREFIX="${NOTIFY_PREFIX:-__HOST_NOTIFY__}"
TOKEN="${NOTIFY_TOKEN:-}"

TITLE_MAX="${NOTIFY_TITLE_MAX:-100}"
BODY_MAX="${NOTIFY_BODY_MAX:-300}"
[[ "$TITLE_MAX" =~ ^[0-9]{1,4}$ ]] || TITLE_MAX=100
[[ "$BODY_MAX"  =~ ^[0-9]{1,5}$ ]] || BODY_MAX=300

echo "[notifier] ready tcp=0.0.0.0:$PORT" >&2

# socat writes every received line to stdout; we parse it directly.
# Use stdbuf if available to reduce buffering.
socat_cmd=(socat -u "TCP-LISTEN:${PORT},fork,reuseaddr" STDOUT)
command -v stdbuf &>/dev/null && socat_cmd=(stdbuf -oL "${socat_cmd[@]}")

"${socat_cmd[@]}" 2>/dev/null | while IFS= read -r line; do
  [[ -z "${line:-}" ]] && continue

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
  title="${title:0:TITLE_MAX}"
  body="${body:0:BODY_MAX}"

  printf '%s\t%s\t%s\t%s\t%s\n' "$PREFIX" "$timeout" "$urgency" "$title" "$body"
done
