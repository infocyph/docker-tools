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
  'scripts/tests/release-gate.sh' \
  'Gate published image digest'; do
  require "$expected"
done


publish_block="$(awk '
  /- name: Build and push multi-architecture image/ { in_block=1 }
  in_block { print }
  /- name: Generate Docker Hub provenance attestation/ { exit }
' "$workflow")"
grep -Fq 'pull: false' <<<"$publish_block" || {
  echo 'final publish build must reuse tested candidate caches without forcing another rolling base pull' >&2
  exit 1
}
grep -Fq 'bash scripts/tests/release-gate.sh "$image"' "$workflow" || {
  echo 'published amd64 digest is not re-gated' >&2
  exit 1
}
grep -Fq 'docker pull --platform linux/arm64 "$image"' "$workflow" || {
  echo 'published arm64 digest verification missing' >&2
  exit 1
}

if grep -Eq 'actions/checkout@v[1-6]([^0-9]|$)|docker/build-push-action@v[1-6]([^0-9]|$)|docker/login-action@v[1-3]([^0-9]|$)|docker/metadata-action@v[1-5]([^0-9]|$)' "$workflow"; then
  echo 'publish workflow contains a superseded action major' >&2
  exit 1
fi

grep -Fq 'askai --help' scripts/tests/release-gate.sh || {
  echo 'release gate does not validate askai' >&2
  exit 1
}
grep -Fq 'aiops --help' scripts/tests/release-gate.sh || {
  echo 'release gate does not validate aiops' >&2
  exit 1
}
grep -Fq 'tools-healthcheck' scripts/tests/release-gate.sh || {
  echo 'release gate does not use the Tools-owned health contract' >&2
  exit 1
}

echo 'release contracts: ok'
