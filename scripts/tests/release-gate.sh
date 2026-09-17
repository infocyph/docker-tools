#!/usr/bin/env bash
set -Eeuo pipefail

IMAGE="${1:-infocyph/tools:ci}"
COMPOSE_FILE="${2:-}"

fail() {
  echo "release gate failed: $*" >&2
  exit 1
}

[[ -n "$COMPOSE_FILE" && -f "$COMPOSE_FILE" ]] || fail 'LocalDevStack companion compose file is required'

grep -Eq '^[[:space:]]*server-tools:' "$COMPOSE_FILE" || fail 'LocalDevStack server-tools service missing'
grep -Fq 'image: infocyph/tools:latest' "$COMPOSE_FILE" || fail 'LocalDevStack does not consume infocyph/tools:latest'
for contract in \
  '/app' \
  '/etc/share/rootCA' \
  '/etc/share/vhosts/apache' \
  '/etc/share/vhosts/nginx' \
  '/etc/share/vhosts/fpm' \
  '/etc/share/vhosts/composer' \
  '/etc/share/scheduler/cron-jobs' \
  '/etc/share/scheduler/supervisor' \
  '/var/run/docker.sock'; do
  grep -Fq "$contract" "$COMPOSE_FILE" || fail "LocalDevStack mount contract missing: $contract"
done

docker run --rm --entrypoint bash "$IMAGE" -lc '
  set -euo pipefail
  test -x /usr/local/bin/mkcert
  test -x /usr/local/bin/lazydocker
  test -x /usr/local/bin/composer
  test -x /usr/local/bin/gitx
  test -x /usr/local/bin/chromacat
  test -x /usr/local/bin/sqlitex
  test -x /usr/local/bin/netx
  test -x /usr/local/bin/notifierd
  test -x /usr/local/bin/show-banner
  ! command -v ollama >/dev/null 2>&1
  mkcert -version >/dev/null
  lazydocker --version >/dev/null
  composer --version --no-ansi >/dev/null
  gitx --version >/dev/null
  chromacat --version >/dev/null
  sqlitex --version >/dev/null
  netx --version >/dev/null
  bash -n /usr/local/bin/show-banner
  jq -e ".generated_at | type == \"string\"" "$RUNTIME_VERSIONS_DB" >/dev/null
  jq -e ".php.active | type == \"array\" and length > 0" "$RUNTIME_VERSIONS_DB" >/dev/null
  jq -e ".node.active | type == \"array\" and length > 0" "$RUNTIME_VERSIONS_DB" >/dev/null
'

name="tools-release-gate-${RANDOM}"
trap 'docker rm -f "$name" >/dev/null 2>&1 || true' EXIT

docker run -d --name "$name" "$IMAGE" >/dev/null
for _ in $(seq 1 30); do
  if docker exec "$name" sh -lc 'wget -qO- http://127.0.0.1:9911/ >/dev/null && tr "\0" " " </proc/1/cmdline | grep -q notifierd'; then
    echo 'release gate: ok'
    exit 0
  fi
  sleep 1
done

docker logs "$name" >&2 || true
fail 'container/admin-panel startup smoke did not become ready'
