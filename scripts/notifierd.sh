#!/bin/bash
set -euo pipefail

PORT="${NOTIFY_TCP_PORT:-9901}"
PREFIX="${NOTIFY_PREFIX:-__HOST_NOTIFY__}"
TOKEN="${NOTIFY_TOKEN:-}"

TITLE_MAX="${NOTIFY_TITLE_MAX:-100}"
BODY_MAX="${NOTIFY_BODY_MAX:-300}"
[[ "$TITLE_MAX" =~ ^[0-9]{1,4}$ ]] || TITLE_MAX=100
[[ "$BODY_MAX"  =~ ^[0-9]{1,5}$ ]] || BODY_MAX=300

echo "[notifier] ready tcp=0.0.0.0:${PORT}" >&2

# socat emits received bytes to stdout; we parse line-by-line.
# Use stdbuf when available to reduce buffering.
socat_cmd=(socat -u -T 2 "TCP-LISTEN:${PORT},fork,reuseaddr" STDOUT)
command -v stdbuf >/dev/null 2>&1 && socat_cmd=(stdbuf -oL -eL "${socat_cmd[@]}")

# IMPORTANT: no pipeline -> no subshell loop
while IFS= read -r line; do
  [[ -z "${line:-}" ]] && continue

  # Protocol (6 fields): token \t timeout \t urgency \t source \t title \t body
  IFS=$'\t' read -r in_token timeout urgency source title body <<<"$line"
  [[ "${in_token:-}" == "-" ]] && in_token=""

  # Auth only if TOKEN is configured
  if [[ -n "${TOKEN:-}" && "${in_token:-}" != "$TOKEN" ]]; then
    echo "[notifier] rejected (bad token)" >&2
    continue
  fi

  timeout="${timeout:-2500}"
  urgency="${urgency:-normal}"
  source="${source:-svc}"

  [[ "$timeout" =~ ^[0-9]{1,6}$ ]] || timeout="2500"
  case "$urgency" in low|normal|critical) ;; *) urgency="normal" ;; esac

  # Sanitize to keep one-line protocol stable
  source="${source//$'\n'/ }"; source="${source//$'\r'/ }"; source="${source//$'\t'/ }"
  title="${title//$'\n'/ }";   title="${title//$'\r'/ }";   title="${title//$'\t'/ }"
  body="${body//$'\n'/ }";     body="${body//$'\r'/ }";     body="${body//$'\t'/ }"

  title="[$source] $title"
  title="${title:0:${TITLE_MAX}}"
  body="${body:0:${BODY_MAX}}"

  # Emit to stdout for host watcher (5 fields):
  # PREFIX \t timeout \t urgency \t title \t body
  printf '%s\t%s\t%s\t%s\t%s\n' "$PREFIX" "$timeout" "$urgency" "$title" "$body"
done < <("${socat_cmd[@]}")
