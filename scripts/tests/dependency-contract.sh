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

assert_present 'FROM alpine:latest' Dockerfile
assert_present 'ARG TARGETARCH' Dockerfile
assert_present 'mkcert/latest\?for=\$\{TARGETOS\}/\$\{TARGETARCH\}' Dockerfile
assert_present 'Toolset/releases/latest/download/install\.sh' Dockerfile
assert_present 'SCRIPTOMATIC_REF=main' Dockerfile
assert_present 'Scriptomatic/\$\{SCRIPTOMATIC_REF\}/bash/banner\.sh' Dockerfile
assert_present 'lazydocker/releases/latest' Dockerfile
assert_present 'checksums\.txt' Dockerfile
assert_present 'def version_parts: split\("\."\) \| map\(tonumber\);' Dockerfile
assert_present 'netcat-openbsd gzip flock' Dockerfile
assert_present 'need_cmd flock' scripts/shells/env-store.sh

ripgrep_count="$(grep -oE '(^|[[:space:]])ripgrep([[:space:]\\]|$)' Dockerfile | wc -l | tr -d ' ')"
[[ "$ripgrep_count" == '1' ]] || fail "expected ripgrep exactly once in apk package list, found $ripgrep_count"

echo 'dependency contracts: ok'
