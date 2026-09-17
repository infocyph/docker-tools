#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

fail() {
  printf 'control-plane-hardening: %s\n' "$*" >&2
  exit 1
}

# Active execution must go through ProcessRunner only.
if grep -R -n --include='*.php' 'shell_exec[[:space:]]*(' scripts/admin-panel/src scripts/admin-panel/app 2>/dev/null; then
  fail 'direct shell_exec() remains in admin panel'
fi

proc_hits="$(grep -R -l --include='*.php' 'proc_open[[:space:]]*(' scripts/admin-panel/src 2>/dev/null || true)"
while IFS= read -r file; do
  [[ -z "$file" || "$file" == 'scripts/admin-panel/src/Support/ProcessRunner.php' ]] || fail "direct proc_open() remains outside ProcessRunner: $file"
done <<<"$proc_hits"

# logs.php still carries an old server-render fallback, but it must stay unreachable.
grep -q '^\$apLogAjaxFirst = true;$' scripts/admin-panel/app/pages/logs.php || fail 'legacy log fallback became reachable'

# Admin control-plane boundary.
grep -q 'Content-Security-Policy' scripts/admin-panel/src/App/Kernel.php || fail 'admin CSP header missing'
grep -q "'samesite' => 'Strict'" scripts/admin-panel/src/App/Kernel.php || fail 'SameSite=Strict control cookie missing'
grep -q 'hash_equals' scripts/admin-panel/src/App/Kernel.php || fail 'admin token comparison missing'
grep -q 'sensitiveDownload' scripts/admin-panel/src/App/Kernel.php || fail 'mTLS artifact protection missing'
grep -q 'sameOrigin' scripts/admin-panel/src/App/Kernel.php || fail 'same-origin mutation guard missing'

# Docker project scope and credential safety.
grep -q 'label=com.docker.compose.project=' scripts/shells/certify.sh || fail 'certificate Docker discovery is not project-scoped'
if grep -Eq 'docker ps -q[[:space:]]+2>/dev/null' scripts/shells/certify.sh; then
  fail 'certificate discovery still permits daemon-wide docker ps'
fi

grep -q 'project_unresolved' scripts/shells/monitor-db.sh || fail 'DB monitor unresolved-project degraded state missing'
if grep -Eq 'user="root"|user="postgres"|pass="12345"' scripts/shells/monitor-db.sh; then
  fail 'DB monitor contains guessed credentials'
fi
if grep -Eq 'docker ps -a --format' scripts/shells/monitor-db.sh; then
  fail 'DB monitor still widens to all daemon containers'
fi

# TLS user credential material must be explicit and password protected.
grep -q 'LDS_USER_P12_ENABLED.*:-0' scripts/shells/certify.sh || fail 'user P12 must be disabled by default'
grep -q 'requires a non-empty LDS_USER_P12_PASSWORD' scripts/shells/certify.sh || fail 'password-protected P12 guard missing'
if grep -q 'passout pass:""' scripts/shells/certify.sh; then
  fail 'passwordless P12 generation reintroduced'
fi

# Reserved LocalDevStack route ABI.
grep -q 'admin.localhost' scripts/admin-panel/src/Api/HostManagerEndpoint.php || fail 'reserved route guard missing admin.localhost'
grep -q 'llm.localhost' scripts/admin-panel/src/Api/HostManagerEndpoint.php || fail 'reserved route guard missing llm.localhost'

# Host mutations must stage first, keep certify out of staging, then validate live runtime.
grep -q 'HostTransactionService' scripts/admin-panel/src/Api/HostManagerEndpoint.php || fail 'host mutations bypass staging transaction'
grep -q 'staged_no_live_change' scripts/admin-panel/src/Service/HostTransactionService.php || fail 'host staging failure contract missing'
grep -q "PATH=.*stage.*bin:/usr/bin:/bin" scripts/admin-panel/src/Service/HostTransactionService.php || fail 'host staging PATH isolation missing'
grep -q "\['nginx', '-t'\]" scripts/admin-panel/src/Service/HostTransactionService.php || fail 'Nginx runtime validation missing'
grep -q "\['httpd', '-t'\]" scripts/admin-panel/src/Service/HostTransactionService.php || fail 'Apache runtime validation missing'

# Tools-owned health only.
grep -q 'HEALTHCHECK' Dockerfile || fail 'Tools image healthcheck missing'
grep -q 'tools-healthcheck' Dockerfile || fail 'Tools health command missing from image'

printf 'control-plane-hardening: ok\n'
