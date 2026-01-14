#!/bin/bash
set -euo pipefail

PORT="${NOTIFY_TCP_PORT:-9901}"
TOKEN="${NOTIFY_TOKEN:-}"
[[ -z "${TOKEN:-}" ]] && TOKEN='-'

SOURCE="${NOTIFY_SOURCE:-${HOSTNAME:-svc}}"

timeout="2500"
urgency="normal"

usage() { echo "Usage: notify [-t ms] [-u low|normal|critical] <title> <body>" >&2; exit 2; }

while getopts ":t:u:" opt; do
  case "$opt" in
  t) timeout="$OPTARG" ;;
  u) urgency="$OPTARG" ;;
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

# sanitize (one-line protocol)
SOURCE="${SOURCE//$'\n'/ }"; SOURCE="${SOURCE//$'\r'/ }"; SOURCE="${SOURCE//$'\t'/ }"
title="${title//$'\n'/ }";   title="${title//$'\r'/ }";   title="${title//$'\t'/ }"
body="${body//$'\n'/ }";     body="${body//$'\r'/ }";     body="${body//$'\t'/ }"

# Build payload once (no echo -e)
payload="$(printf "%s\t%s\t%s\t%s\t%s\t%s\n" "$TOKEN" "$timeout" "$urgency" "$SOURCE" "$title" "$body")"

# Prefer netcat-openbsd behaviour if present; otherwise fall back.
# -w: overall timeout (seconds), -q: quit after EOF (seconds)
if nc -h 2>&1 | grep -q -- 'OpenBSD'; then
  printf '%s' "$payload" | nc -w 1 -q 0 127.0.0.1 "$PORT" >/dev/null 2>&1 || true
else
  # busybox/traditional: -w exists but -q may not; keep it simple
  printf '%s' "$payload" | nc -w 1 127.0.0.1 "$PORT" >/dev/null 2>&1 || true
fi
