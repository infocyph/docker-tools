#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

workflow='.github/workflows/docker.publish.yml'
[[ -f "$workflow" ]] || { echo 'publish workflow missing' >&2; exit 1; }

require() {
  grep -Fq "$1" "$workflow" || { echo "publish contract missing: $1" >&2; exit 1; }
}

for expected in \
  'actions/checkout@v7' \
  'docker/setup-qemu-action@v4' \
  'docker/setup-buildx-action@v4' \
  'docker/login-action@v4' \
  'docker/metadata-action@v6' \
  'docker/build-push-action@v7' \
  'actions/attest@v4' \
  'platforms: linux/amd64,linux/arm64' \
  'provenance: mode=max' \
  'sbom: true' \
  'PUBLISH_RELEASE_TAG=false' \
  'Enforce immutable release tags' \
  'scripts/tests/release-gate.sh'; do
  require "$expected"
done

if grep -Eq 'actions/checkout@v[1-6]([^0-9]|$)|docker/build-push-action@v[1-6]([^0-9]|$)|docker/login-action@v[1-3]([^0-9]|$)|docker/metadata-action@v[1-5]([^0-9]|$)' "$workflow"; then
  echo 'publish workflow contains a superseded action major' >&2
  exit 1
fi

echo 'release contracts: ok'
