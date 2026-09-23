#!/usr/bin/env bash
set -euo pipefail

PHP_BIN="${DOCSTRUCT_PHP_BIN:-/usr/bin/php}"
IMPL="${DOCSTRUCT_IMPL:-/usr/local/lib/docker-tools/docstruct.php}"

if [[ ! -r "$IMPL" ]]; then
  local_impl="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)/php/docstruct.php"
  [[ -r "$local_impl" ]] && IMPL="$local_impl"
fi

[[ -x "$PHP_BIN" ]] || { printf 'docstruct: php runtime not found: %s\n' "$PHP_BIN" >&2; exit 69; }
[[ -r "$IMPL" ]] || { printf 'docstruct: implementation not found: %s\n' "$IMPL" >&2; exit 66; }

exec "$PHP_BIN" "$IMPL" "$@"
