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
  'release:' \
  'types: [published]' \
  'workflow_dispatch:' \
  'release_tag:' \
  'MANUAL_RELEASE_TAG:' \
  'RELEASE_TAG="$EVENT_RELEASE_TAG"' \
  'releases/tags/${MANUAL_RELEASE_TAG}' \
  'Manual recovery refuses draft/prerelease release:' \
  'EVENT_RELEASE_PRERELEASE:' \
  'Stable publish workflow refuses draft/prerelease releases.' \
  'release_json="$(gh api "repos/${GITHUB_REPOSITORY}/releases/latest")"' \
  'Check out exact Tools release source' \
  'ref: ${{ env.RELEASE_TAG }}' \
  'actions/checkout@v7' \
  'docker/setup-qemu-action@v4' \
  'docker/setup-buildx-action@v4' \
  'Snapshot rolling upstream inputs' \
  'ALPINE_REF="alpine:latest@${ALPINE_DIGEST}"' \
  'SCRIPTOMATIC_REF="$(retry get_scriptomatic_sha)"' \
  'TOOLSET_INSTALLER_SHA256=' \
  'MKCERT_SHA256_AMD64=' \
  'MKCERT_SHA256_ARM64=' \
  'Generated template runtime compatibility' \
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
  'Verify and summarize published image'; do
  require "$expected"
done


publish_block="$(awk '
  /- name: Build and push multi-architecture image/ { in_block=1 }
  in_block { print }
  /- name: Generate Docker Hub provenance attestation/ { exit }
' "$workflow")"
grep -Fq 'pull: true' <<<"$publish_block" || {
  echo 'final multi-architecture publish must follow docker-runner and pull pinned bases' >&2
  exit 1
}
if grep -Fq 'Gate published image digest' "$workflow"; then
  echo 'publish workflow must not add a second post-push runtime gate after Runner-style verification' >&2
  exit 1
fi
grep -Fq 'tools-publish-arm64-' "$workflow" || {
  echo 'arm64 candidate does not exercise the real Tools lifecycle' >&2
  exit 1
}
grep -Fq 'CANDIDATE_ALPINE_VERSION=' "$workflow" || {
  echo 'candidate rolling-version capture missing' >&2
  exit 1
}
grep -Fq 'dockerhub_image="docker.io/' "$workflow" || {
  echo 'Docker Hub published digest verification missing' >&2
  exit 1
}
grep -Fq '[[ "$alpine_version" == "$CANDIDATE_ALPINE_VERSION" ]]' "$workflow" || {
  echo 'candidate/published Alpine parity check missing' >&2
  exit 1
}
grep -Fq '[[ "$gitx_version" == "$CANDIDATE_GITX_VERSION" ]]' "$workflow" || {
  echo 'candidate/published Toolset gitx parity check missing' >&2
  exit 1
}
grep -Fq '[[ "$composer_version" == "$CANDIDATE_COMPOSER_VERSION" ]]' "$workflow" || {
  echo 'candidate/published Composer parity check missing' >&2
  exit 1
}
grep -Fq '[[ "$runtime_generated_at" == "$CANDIDATE_RUNTIME_GENERATED_AT" ]]' "$workflow" || {
  echo 'candidate/published runtime metadata parity check missing' >&2
  exit 1
}
grep -Fq '[[ "$banner_sha256" == "$CANDIDATE_BANNER_SHA256" ]]' "$workflow" || {
  echo 'candidate/published Scriptomatic banner parity check missing' >&2
  exit 1
}

for cache_scope in publish-candidate-amd64 publish-candidate-arm64 publish-multiarch; do
  grep -Fq "scope=${cache_scope},mode=max,ignore-error=true" "$workflow" || {
    echo "publish cache export must be fail-open: $cache_scope" >&2
    exit 1
  }
done

grep -Fq 'echo "- Toolset release: \`$TOOLSET_RELEASE\`"' "$workflow" || {
  echo 'candidate summary is not using resolved Toolset release pin' >&2
  exit 1
}
grep -Fq 'echo "- Scriptomatic revision: \`$SCRIPTOMATIC_REF\`"' "$workflow" || {
  echo 'candidate summary is not using resolved Scriptomatic revision pin' >&2
  exit 1
}
if grep -Fq '$toolset_release' "$workflow" || grep -Fq '$scriptomatic_main' "$workflow"; then
  echo 'publish workflow contains stale candidate-summary variables' >&2
  exit 1
fi

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
grep -Fq 'bash scripts/tests/template-abi-contract.sh' .github/workflows/check.yml || {
  echo 'static template ABI contract is not executed by CI' >&2
  exit 1
}
grep -Fq 'bash scripts/tests/template-runtime-smoke.sh' .github/workflows/check.yml || {
  echo 'runtime template ABI smoke is not executed by CI' >&2
  exit 1
}

grep -Fq 'repository: infocyph/LocalDevStack' .github/workflows/check.yml || {
  echo 'normal CI does not check out LocalDevStack for the final release gate' >&2
  exit 1
}
grep -Fq 'bash scripts/tests/release-gate.sh infocyph/tools:ci .localdevstack/docker/compose/companion.yaml' .github/workflows/check.yml || {
  echo 'normal amd64 CI does not execute the exact Tools release gate' >&2
  exit 1
}
grep -Fq 'docker exec "$name" tools-healthcheck >/dev/null 2>&1 \' scripts/tests/release-gate.sh || {
  echo 'release gate does not wait on Tools health before runtime assertions' >&2
  exit 1
}

echo 'release contracts: ok'
