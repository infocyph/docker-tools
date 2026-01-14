#!/bin/bash
set -euo pipefail

if ! /usr/local/bin/certify >/dev/null 2>&1; then
  echo "[entrypoint] Certification failed" >&2
fi

exec "$@"
