#!/bin/bash
set -euo pipefail

PORT="${NOTIFY_TCP_PORT:-9901}"
HOST="${NOTIFY_HOST:-127.0.0.1}"   # local-only; docknotify is for cross-service
TOKEN="${NOTIFY_TOKEN:-}"
[[ -n "${TOKEN:-}" ]] || TOKEN='-'

SOURCE="${NOTIFY_SOURCE:-${HOSTNAME:-svc}}"

timeout="2500"
urgency="normal"

usage() {
  echo "Usage: notify [-H host] [-p port] [-t ms] [-u low|normal|critical] [-s source] <title> <body>" >&2
  exit 2
}

while getopts ":H:p:t:u:s:" opt; do
  case "$opt" in
  H) HOST="$OPTARG" ;;
  p) PORT="$OPTARG" ;;
  t) timeout="$OPTARG" ;;
  u) urgency="$OPTARG" ;;
  s) SOURCE="$OPTARG" ;;
  *) usage ;;
  esac
done
shift $((OPTIND - 1))

[[ $# -ge 2 ]] || usage

title="$1"
body="$2"

# Validate + normalize
[[ "$timeout" =~ ^[0-9]{1,6}$ ]] || timeout="2500"
case "$urgency" in low|normal|critical) ;; *) urgency="normal" ;; esac

# Sanitize (one-line protocol)
SOURCE="${SOURCE//$'\n'/ }"; SOURCE="${SOURCE//$'\r'/ }"; SOURCE="${SOURCE//$'\t'/ }"
title="${title//$'\n'/ }";   title="${title//$'\r'/ }";   title="${title//$'\t'/ }"
body="${body//$'\n'/ }";     body="${body//$'\r'/ }";     body="${body//$'\t'/ }"

command -v nc >/dev/null 2>&1 || { echo "notify: nc not found" >&2; exit 127; }

# Send (best-effort; never break callers)
# Protocol: token \t timeout \t urgency \t source \t title \t body \n
if ! printf "%s\t%s\t%s\t%s\t%s\t%s\n" \
  "$TOKEN" "$timeout" "$urgency" "$SOURCE" "$title" "$body" \
  | nc -w 1 "$HOST" "$PORT" >/dev/null 2>&1; then
  exit 0
fi
