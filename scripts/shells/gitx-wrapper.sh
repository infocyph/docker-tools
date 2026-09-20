#!/usr/bin/env bash
set -euo pipefail

REAL_GITX="${GITX_TOOLSET_BIN:-/usr/local/libexec/gitx-toolset}"
[[ -x "$REAL_GITX" ]] || { echo "gitx: Toolset binary missing: $REAL_GITX" >&2; exit 127; }

if [[ "${1:-}" == 'ai-commit' ]]; then
  shift
  exec "${GITX_AI_COMMIT_BIN:-/usr/local/bin/gitx-ai-commit}" "$@"
fi

exec "$REAL_GITX" "$@"
