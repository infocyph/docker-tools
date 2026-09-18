#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

fail() {
  echo "dependency contract failed: $*" >&2
  exit 1
}

assert_absent() {
  local pattern="$1"
  if grep -RInE --exclude-dir=.git --exclude='docker-tools-hardening-ai-plan.md' "$pattern" Dockerfile scripts .github README.md >/dev/null 2>&1; then
    grep -RInE --exclude-dir=.git --exclude='docker-tools-hardening-ai-plan.md' "$pattern" Dockerfile scripts .github README.md >&2 || true
    fail "forbidden pattern present: $pattern"
  fi
}

assert_present() {
  local pattern="$1" file="$2"
  grep -Eq "$pattern" "$file" || fail "expected pattern missing from $file: $pattern"
}

assert_absent 'raw\.githubusercontent\.com/infocyph/Toolset/(main|master)/'
assert_absent 'raw\.githubusercontent\.com/infocyph/Scriptomatic/master/'
assert_absent 'ollama[[:space:]]+serve'
assert_absent 'EXPOSE[[:space:]]+11434'
assert_absent 'mkcert/latest\?for=linux/amd64'

assert_present 'ARG ALPINE_REF=alpine:latest' Dockerfile
assert_present 'FROM \$\{ALPINE_REF\}' Dockerfile
assert_present 'ARG TARGETARCH' Dockerfile
assert_present 'ARG MKCERT_RELEASE=latest' Dockerfile
assert_present 'mkcert/latest\?for=\$\{TARGETOS\}/\$\{TARGETARCH\}' Dockerfile
assert_present 'mkcert-\$\{MKCERT_RELEASE\}-\$\{TARGETOS\}-\$\{TARGETARCH\}' Dockerfile
assert_present 'ARG TOOLSET_RELEASE=latest' Dockerfile
assert_present 'ARG TOOLSET_INSTALLER_SHA256=' Dockerfile
assert_present 'Toolset/releases/latest/download/install\.sh' Dockerfile
assert_present 'Toolset/releases/download/\$\{TOOLSET_RELEASE\}/install\.sh' Dockerfile
assert_present 'SCRIPTOMATIC_REF=main' Dockerfile
assert_present 'Scriptomatic/\$\{SCRIPTOMATIC_REF\}/bash/banner\.sh' Dockerfile
assert_present 'ARG LAZYDOCKER_RELEASE=latest' Dockerfile
assert_present 'lazydocker/releases/latest' Dockerfile
assert_present 'lazydocker/releases/tags/\$\{LAZYDOCKER_RELEASE\}' Dockerfile
assert_present 'checksums\.txt' Dockerfile
assert_present 'def version_parts: split\("\."\) \| map\(tonumber\);' Dockerfile
assert_present 'netcat-openbsd gzip flock' Dockerfile
assert_present 'need_cmd flock' scripts/shells/env-store.sh

# Preserve baseline image/runtime behavior while hardening lifecycle and health.
assert_present '/usr/local/bin/composer' Dockerfile
assert_present '/etc/share/scripts/tests/senv-smoke\.sh' Dockerfile
assert_present '&& init-php-dirs' Dockerfile
assert_present 'chmod -R 755 /etc/share/vhosts' Dockerfile
assert_present '/etc/profile\.d/banner-hook\.sh' Dockerfile
assert_present 'WORKDIR /app' Dockerfile
assert_present 'STOPSIGNAL SIGTERM' Dockerfile
assert_present 'ENTRYPOINT \["/usr/local/bin/entrypoint"\]' Dockerfile
assert_present 'CMD \["/usr/local/bin/notifierd"\]' Dockerfile
assert_present ': "\$\{NOTIFY_TOKEN:=\}"' scripts/shells/entrypoint.sh
assert_present 'CMD \["/usr/local/bin/tools-healthcheck"\]' Dockerfile

ripgrep_count="$(grep -oE '(^|[[:space:]])ripgrep([[:space:]\\]|$)' Dockerfile | wc -l | tr -d ' ')"
[[ "$ripgrep_count" == '1' ]] || fail "expected ripgrep exactly once in apk package list, found $ripgrep_count"

echo 'dependency contracts: ok'
