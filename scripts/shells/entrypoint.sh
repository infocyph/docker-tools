#!/bin/bash
set -euo pipefail

if ! certify >/dev/null 2>&1; then
  echo "[entrypoint] Certification failed" >&2
fi

exec "$@"
