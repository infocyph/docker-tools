#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_STORE="$ROOT/scripts/shells/env-store.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

STORE="$TMP/env-store.json"

run_store() {
  ENV_STORE_JSON="$STORE" ENV_STORE_LOCK_TIMEOUT_MS=10000 bash "$ENV_STORE" "$@"
}

fail() {
  printf 'env-store-concurrency: %s\n' "$*" >&2
  exit 1
}

command -v flock >/dev/null 2>&1 || fail 'flock command is required for this test'

run_store reset >/dev/null
chmod 0640 "$STORE"

pids=()
for i in $(seq 1 32); do
  run_store set "KEY_${i}" "value-${i}" >/dev/null &
  pids+=("$!")
done
for pid in "${pids[@]}"; do
  wait "$pid"
done

jq -e '.data | length == 32' "$STORE" >/dev/null || fail 'concurrent writes lost keys'
for i in $(seq 1 32); do
  jq -e --arg key "KEY_${i}" --arg value "value-${i}" '.data[$key] == $value' "$STORE" >/dev/null \
    || fail "missing or corrupt KEY_${i}"
done

mode="$(stat -c '%a' "$STORE")"
[[ "$mode" == '640' ]] || fail "store mode changed after atomic replacement: $mode"

# Hold the kernel advisory lock and prove writers fail boundedly rather than corrupting state.
exec 9>"${STORE}.lock"
flock -n 9 || fail 'unable to acquire test lock'
if ENV_STORE_JSON="$STORE" ENV_STORE_LOCK_TIMEOUT_MS=150 bash "$ENV_STORE" set LOCKED blocked >/dev/null 2>&1; then
  fail 'writer unexpectedly bypassed held advisory lock'
fi
jq -e '.data | has("LOCKED") | not' "$STORE" >/dev/null || fail 'blocked writer modified the store'

# Releasing/closing the descriptor must make the lock immediately recoverable, with no stale PID cleanup.
flock -u 9
exec 9>&-
run_store set RECOVERED yes >/dev/null
[[ "$(run_store get RECOVERED)" == 'yes' ]] || fail 'store did not recover after advisory lock release'

BAD="$TMP/malformed.json"
printf '{not-json\n' >"$BAD"
if ENV_STORE_JSON="$BAD" ENV_STORE_LOCK_TIMEOUT_MS=1000 bash "$ENV_STORE" set TEST value >/dev/null 2>&1; then
  fail 'malformed store was silently overwritten'
fi
grep -q '{not-json' "$BAD" || fail 'malformed store contents were replaced'

printf 'env-store-concurrency: ok\n'
