#!/bin/bash
set -euo pipefail

PORT="${NOTIFY_TCP_PORT:-9901}"
TOKEN="${NOTIFY_TOKEN:-}"
[[ -z "$TOKEN" ]] && TOKEN='-'

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

# sanitize (one-line protocol)
SOURCE="${SOURCE//$'\n'/ }"; SOURCE="${SOURCE//$'\r'/ }"; SOURCE="${SOURCE//$'\t'/ }"
title="${title//$'\n'/ }";   title="${title//$'\r'/ }";   title="${title//$'\t'/ }"
body="${body//$'\n'/ }";     body="${body//$'\r'/ }";     body="${body//$'\t'/ }"

# New protocol (6 fields): token \t timeout \t urgency \t source \t title \t body
printf "%s\t%s\t%s\t%s\t%s\t%s\n" "$TOKEN" "$timeout" "$urgency" "$SOURCE" "$title" "$body" \
  | nc -w 1 "127.0.0.1" "$PORT"
