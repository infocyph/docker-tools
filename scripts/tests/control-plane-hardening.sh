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

proc_hits="$(grep -R -l --include='*.php' 'proc_open[[:space:]]*(' scripts/admin-panel/src scripts/admin-panel/app 2>/dev/null || true)"
while IFS= read -r file; do
  [[ -z "$file" || "$file" == 'scripts/admin-panel/src/Support/ProcessRunner.php' ]] || fail "direct proc_open() remains outside ProcessRunner: $file"
done <<<"$proc_hits"

# Filesystem-heavy log discovery should keep the native find fast path, but it
# must run through the bounded ProcessRunner rather than direct proc_open/shell.
LOG_SERVICE='scripts/admin-panel/src/Service/LogsDataService.php'
grep -q 'ProcessRunner::run' "$LOG_SERVICE" || fail 'log discovery bypasses ProcessRunner'
grep -q "'find'" "$LOG_SERVICE" || fail 'native find log discovery fast path missing'
grep -q 'RecursiveDirectoryIterator' "$LOG_SERVICE" || fail 'PHP log discovery fallback missing'

# Log viewer must use the active service/ProcessRunner path only.
if grep -q 'proc_open[[:space:]]*(' scripts/admin-panel/app/pages/logs.php; then
  fail 'legacy direct log-viewer process execution reappeared'
fi
grep -q 'ADMIN_PANEL_LOG_ROOTS' scripts/admin-panel/src/Service/LogsDataService.php || fail 'canonical admin log roots config missing'

# Dashboard must report live operational state, never template/demo business data.
DASHBOARD='scripts/admin-panel/app/pages/dashboard.php'
grep -q '/api/live-stats' "$DASHBOARD" || fail 'dashboard live status source missing'
grep -q '/api/ai-assistant' "$DASHBOARD" || fail 'dashboard optional AI status source missing'
if grep -Eqi 'Monthly Revenue|Recent Deployments|Order Status|Traffic Sources|TailAdmin-style|\$[0-9]{2,},[0-9]{3}' "$DASHBOARD"; then
  fail 'dashboard contains fabricated/demo metrics'
fi

# Admin control-plane boundary.
grep -q 'Content-Security-Policy' scripts/admin-panel/src/App/Kernel.php || fail 'admin CSP header missing'
grep -q "'samesite' => 'Strict'" scripts/admin-panel/src/App/Kernel.php || fail 'SameSite=Strict control cookie missing'
grep -q 'hash_equals' scripts/admin-panel/src/App/Kernel.php || fail 'admin token comparison missing'
grep -q 'sensitiveDownload' scripts/admin-panel/src/App/Kernel.php || fail 'mTLS artifact protection missing'
grep -q 'isSameOrigin' scripts/admin-panel/src/App/Kernel.php || fail 'same-origin mutation guard missing'

# Docker project scope and credential safety.
grep -q 'BASH_ENV=/run/lds-project.env' Dockerfile || fail 'runtime Bash project scope env missing'
grep -q 'init_project_scope' scripts/shells/entrypoint.sh || fail 'entrypoint project scope initialization missing'
grep -q 'project="unknown"' scripts/shells/entrypoint.sh || fail 'unresolved project must degrade to unknown'
grep -q 'export STATUS_PROJECT LDS_COMPOSE_PROJECT' scripts/shells/entrypoint.sh || fail 'project scope is not exported to child helpers'
if grep -Eq 'docker ps .*compose\.project.*uniq -c' scripts/shells/entrypoint.sh; then
  fail 'entrypoint project scope widens to host-wide project inference'
fi

if grep -Eq "docker ps -a?[^\n]*--format '\{\{\.Label \"com\.docker\.compose\.project\"\}\}'" scripts/shells/status.sh; then
  fail 'status still infers project from daemon-wide container population'
fi
if grep -Fq "docker ps -aq --filter 'label=com.docker.compose.service=server-tools'" scripts/shells/status.sh; then
  fail 'status still selects an unscoped server-tools container'
fi
if grep -Fq '{{range .Config.Env}}{{println .}}{{end}}' scripts/shells/status.sh; then
  fail 'status still inspects the full environment of a container'
fi
grep -q 'label=com.docker.compose.project=' scripts/shells/status.sh || fail 'status project-scoped Docker filters missing'

if grep -Fq "docker ps --filter 'label=com.docker.compose.service=nginx'" scripts/shells/monitor-tls.sh; then
  fail 'TLS monitor still selects an unscoped Nginx container'
fi
if grep -Fq "docker ps -aq --filter 'label=com.docker.compose.service=server-tools'" scripts/shells/monitor-tls.sh; then
  fail 'TLS monitor still selects an unscoped server-tools container'
fi
if grep -Eq "docker ps[^\n]*--format '\{\{\.Label \"com\.docker\.compose\.project\"\}\}'" scripts/shells/monitor-tls.sh; then
  fail 'TLS monitor still infers the project from daemon-wide containers'
fi
grep -q 'LDS_COMPOSE_PROJECT' scripts/shells/monitor-tls.sh || fail 'TLS monitor project env contract missing'
grep -q 'label=com.docker.compose.project=' scripts/shells/monitor-tls.sh || fail 'TLS monitor scoped Docker filter missing'
grep -q "nc -z -w 2" scripts/shells/monitor-tls.sh || fail 'TLS monitor fixed-argv reachability probe missing'
if grep -Eq 'bash -c ".*\/dev\/tcp/\$\{?host' scripts/shells/monitor-tls.sh; then
  fail 'TLS monitor interpolates target values into shell code'
fi

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
if grep -q '_container_env_value' scripts/shells/monitor-db.sh || grep -q '\.Config\.Env' scripts/shells/monitor-db.sh; then
  fail 'DB monitor still extracts database credentials into the Tools process'
fi
if grep -Eq 'docker exec .*-[eE][[:space:]]+[^[:space:]]*(PASS|PASSWORD)=' scripts/shells/monitor-db.sh; then
  fail 'DB monitor still forwards credential values through host-side docker exec arguments'
fi
grep -q 'MYSQL_ROOT_PASSWORD' scripts/shells/monitor-db.sh || fail 'MySQL root-only probe fallback missing'
grep -q 'POSTGRES_DB:-\$user' scripts/shells/monitor-db.sh || fail 'PostgreSQL default database fallback missing'
grep -q -- '--authenticationDatabase admin' scripts/shells/monitor-db.sh || fail 'MongoDB explicit authentication database probe missing'

# Every Docker-backed monitor must degrade instead of widening to the host daemon.
for monitor in \
  scripts/shells/status.sh \
  scripts/shells/monitor-db.sh \
  scripts/shells/monitor-drift.sh \
  scripts/shells/monitor-flows.sh \
  scripts/shells/monitor-log-heatmap.sh \
  scripts/shells/monitor-queue.sh \
  scripts/shells/monitor-runtime.sh \
  scripts/shells/monitor-slo.sh \
  scripts/shells/monitor-tls.sh \
  scripts/shells/monitor-volumes.sh; do
  if grep -Fq "docker ps --format '{{.Label \"com.docker.compose.project\"}}'" "$monitor"; then
    fail "daemon-wide Compose-project inference remains: $monitor"
  fi
  if grep -Fq "docker ps -a --format '{{.Names}}'" "$monitor"; then
    fail "daemon-wide container-name discovery remains: $monitor"
  fi
  if grep -Fq 'docker ps -aq 2>/dev/null' "$monitor"; then
    fail "daemon-wide container-id discovery remains: $monitor"
  fi
  if grep -Fq "docker ps -aq --filter 'label=com.docker.compose.service=server-tools'" "$monitor"; then
    fail "unscoped server-tools discovery remains: $monitor"
  fi
done

if grep -Fq 'docker system df -v' scripts/shells/status.sh; then
  fail 'status project volume view still reads daemon-wide detailed volume metadata'
fi
grep -q '_status_project_volume_size_rows' scripts/shells/status.sh || fail 'status project-scoped volume size helper missing'
grep -q 'monitor-volumes --json --skip-inodes' scripts/shells/status.sh || fail 'status does not preserve volume sizes through scoped monitor'
grep -q -- '--skip-inodes' scripts/shells/monitor-volumes.sh || fail 'lightweight scoped volume-size mode missing'
grep -q 'project_unresolved' scripts/shells/monitor-volumes.sh || fail 'volume monitor unresolved-project degradation missing'
if grep -Fq 'docker system df -v' scripts/shells/monitor-volumes.sh || grep -Fq 'docker volume ls' scripts/shells/monitor-volumes.sh; then
  fail 'volume monitor still reads daemon-wide volume metadata'
fi
grep -q '_volume_size_bytes' scripts/shells/monitor-volumes.sh || fail 'project-scoped volume size probe missing'
grep -q 'LDS_COMPOSE_PROJECT' scripts/shells/monitor-drift.sh || fail 'drift monitor project env contract missing'
grep -q 'LDS_COMPOSE_PROJECT' scripts/shells/monitor-flows.sh || fail 'flow monitor project env contract missing'
grep -q 'LDS_COMPOSE_PROJECT' scripts/shells/monitor-log-heatmap.sh || fail 'log heatmap project env contract missing'
grep -q 'LDS_COMPOSE_PROJECT' scripts/shells/monitor-queue.sh || fail 'queue monitor project env contract missing'
grep -q 'LDS_COMPOSE_PROJECT' scripts/shells/monitor-runtime.sh || fail 'runtime monitor project env contract missing'
grep -q 'LDS_COMPOSE_PROJECT' scripts/shells/monitor-slo.sh || fail 'SLO monitor project env contract missing'
grep -q 'LDS_COMPOSE_PROJECT' scripts/shells/monitor-volumes.sh || fail 'volume monitor project env contract missing'
if grep -Eq '_docker_exec_pref_shell .*redis-cli|redis-cli (ZCARD|ZRANGE|LLEN) .*\$key.*bash -c' scripts/shells/monitor-queue.sh; then
  fail 'queue monitor interpolates Redis keys into shell commands'
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


# Admin Panel time display follows the configured LocalDevStack TZ.
grep -q 'date_default_timezone_set' scripts/admin-panel/app/bootstrap.php || fail 'admin timezone bootstrap missing'
grep -q 'data-ap-timezone' scripts/admin-panel/app/pages/_layout_top.php || fail 'admin timezone is not exposed to browser formatter'
grep -q 'window.AdminPanelTime' scripts/admin-panel/public/js/time.js || fail 'shared admin time formatter missing'
grep -q 'formatEpochSeconds' scripts/admin-panel/app/pages/logs.php || fail 'file logs do not use shared local-time formatter'
grep -q 'localizeDockerLine' scripts/admin-panel/app/pages/docker_logs.php || fail 'Docker log timestamp localization missing'
if grep -Fq 'toISOString().slice(11, 16)' scripts/admin-panel/app/pages/logs.php scripts/admin-panel/app/pages/docker_logs.php; then
  fail 'log heatmap still renders UTC clock labels'
fi

# Docker Logs intentionally exposes only concrete service tabs.
if grep -Eq 'data-service-tab="all"|>All</button>|All services' scripts/admin-panel/app/pages/docker_logs.php; then
  fail 'Docker Logs aggregate All tab/state reappeared'
fi

# TLS monitor wrapper budget must scale beyond the old fixed 20s ceiling.
grep -q 'PROBES_PER_HOST = 5' scripts/admin-panel/src/Service/TlsMonitorService.php || fail 'TLS probe budget multiplier missing'
grep -q 'MAX_COMMAND_TIMEOUT_SECONDS = 600' scripts/admin-panel/src/Service/TlsMonitorService.php || fail 'TLS monitor hard ceiling missing'
grep -q 'commandTimeoutSeconds' scripts/admin-panel/src/Service/TlsMonitorService.php || fail 'TLS dynamic command timeout missing'

grep -q '/public/js/time.js' scripts/admin-panel/app/pages/_layout_bottom.php || fail 'admin time helper is not loaded'


core_js_size="$(wc -c < scripts/admin-panel/public/js/core.js)"
((core_js_size > 2000000)) || fail "admin core.js appears truncated/replaced"
