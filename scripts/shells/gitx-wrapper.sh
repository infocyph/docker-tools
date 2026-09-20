#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == 'ai-commit' ]]; then
  shift
  helper="${GITX_AI_COMMIT_BIN:-/usr/local/bin/gitx-ai-commit}"
  if [[ -x "$helper" ]]; then
    exec "$helper" "$@"
  fi
  exec bash "$helper" "$@"
fi

REAL_GITX="${GITX_TOOLSET_BIN:-/usr/local/libexec/gitx-toolset}"
[[ -x "$REAL_GITX" ]] || { echo "gitx: Toolset binary missing: $REAL_GITX" >&2; exit 127; }

exec "$REAL_GITX" "$@"
