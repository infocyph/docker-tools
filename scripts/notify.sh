#!/bin/bash
set -euo pipefail

PORT="${NOTIFY_TCP_PORT:-9901}"
HOST="${NOTIFY_HOST:-127.0.0.1}"   # keep notify local; docknotify is for cross-service
TOKEN="${NOTIFY_TOKEN:-}"
[[ -z "${TOKEN:-}" ]] && TOKEN='-'

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

# Build payload once (no echo -e)
payload="$(printf "%s\t%s\t%s\t%s\t%s\t%s\n" "$TOKEN" "$timeout" "$urgency" "$SOURCE" "$title" "$body")"

# Require nc
command -v nc >/dev/null 2>&1 || { echo "notify: nc not found" >&2; exit 127; }

# Detect supported flags (portable-ish)
nc_help="$(nc -h 2>&1 || true)"

# OpenBSD netcat supports: -q (quit after EOF), often also -N
# BusyBox netcat is more limited.
nc_args=()

# overall connect/write timeout
if printf '%s' "$nc_help" | grep -q -- ' -w '; then
  nc_args+=(-w 1)
fi

# close immediately after stdin ends
if printf '%s' "$nc_help" | grep -q -- ' -q '; then
  nc_args+=(-q 0)
elif printf '%s' "$nc_help" | grep -q -- ' -N '; then
  nc_args+=(-N)
fi

# Send (do not swallow errors silently; still keep script non-fatal for callers)
if ! printf '%s' "$payload" | nc "${nc_args[@]}" "$HOST" "$PORT" >/dev/null 2>&1; then
  # best-effort: if connection fails, don't crash pipelines
  exit 0
fi
