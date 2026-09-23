#!/usr/bin/env bash
set -euo pipefail

PHP_BIN="${DOCSTRUCT_PHP_BIN:-/usr/bin/php}"
IMPL="${DOCSTRUCT_IMPL:-/usr/local/lib/docker-tools/docstruct.php}"
GRAPHIFY_IMPL="${DOCSTRUCT_GRAPHIFY_IMPL:-/usr/local/lib/docker-tools/docstruct-graphify.php}"
CONTEXT_IMPL="${DOCSTRUCT_CONTEXT_IMPL:-/usr/local/lib/docker-tools/docstruct-context.php}"

if [[ ! -r "$IMPL" ]]; then
  local_impl="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)/php/docstruct.php"
  [[ -r "$local_impl" ]] && IMPL="$local_impl"
fi

[[ -x "$PHP_BIN" ]] || { printf 'docstruct: php runtime not found: %s\n' "$PHP_BIN" >&2; exit 69; }

if [[ "${1:-}" == context ]]; then
  shift
  if [[ ! -r "$CONTEXT_IMPL" ]]; then
    local_context_impl="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)/php/docstruct-context.php"
    [[ -r "$local_context_impl" ]] && CONTEXT_IMPL="$local_context_impl"
  fi
  [[ -r "$CONTEXT_IMPL" ]] || { printf 'docstruct: review-context builder not found: %s\n' "$CONTEXT_IMPL" >&2; exit 66; }
  exec "$PHP_BIN" "$CONTEXT_IMPL" "$@"
fi

if [[ "${1:-}" == graphify ]]; then
  shift
  if [[ ! -r "$GRAPHIFY_IMPL" ]]; then
    local_graphify_impl="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)/php/docstruct-graphify.php"
    [[ -r "$local_graphify_impl" ]] && GRAPHIFY_IMPL="$local_graphify_impl"
  fi
  [[ -r "$GRAPHIFY_IMPL" ]] || { printf 'docstruct: Graphify exporter not found: %s\n' "$GRAPHIFY_IMPL" >&2; exit 66; }
  exec "$PHP_BIN" "$GRAPHIFY_IMPL" "$@"
fi

[[ -r "$IMPL" ]] || { printf 'docstruct: implementation not found: %s\n' "$IMPL" >&2; exit 66; }
exec "$PHP_BIN" "$IMPL" "$@"
