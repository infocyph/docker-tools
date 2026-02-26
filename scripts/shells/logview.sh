#!/usr/bin/env bash
set -euo pipefail

: "${LOGVIEW_BIND:=0.0.0.0}"
: "${LOGVIEW_PORT:=9911}"

php -S "${LOGVIEW_BIND}:${LOGVIEW_PORT}" /app/logviewer/app/index.php
