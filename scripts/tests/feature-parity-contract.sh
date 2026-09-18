#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

fail() {
  echo "feature parity contract failed: $*" >&2
  exit 1
}

# Baseline CLI surface from docker-tools main before the hardening/AI branch.
baseline_bins=(
  certify mkhost rmhost es-policy notifierd notify senv domain-which status
  monitor-flows monitor-runtime monitor-tls monitor-db monitor-volumes
  monitor-queue monitor-slo monitor-log-heatmap monitor-drift monitor-alerts
  env-store profile-chooser init-php-dirs git-default entrypoint
)
for bin in "${baseline_bins[@]}"; do
  grep -Fq "/usr/local/bin/$bin" Dockerfile || fail "baseline image command missing: $bin"
done

# Toolchain/runtime commands present on main must remain installed.
for bin in mkcert lazydocker composer; do
  grep -Fq "/usr/local/bin/$bin" Dockerfile || fail "baseline toolchain command missing: $bin"
done

# Baseline Admin Panel views must remain available.
baseline_pages=(
  automation_cron automation_manager automation_supervisor dashboard db_health
  docker_logs drift_monitor host_manager live_stats logs queue_health slo_view
  tls_monitor volume_monitor
)
for page in "${baseline_pages[@]}"; do
  [[ -f "scripts/admin-panel/app/pages/${page}.php" ]] || fail "baseline admin page missing: $page"
done

# Baseline API/service files must remain available.
baseline_api=(
  AutomationManagerEndpoint DbHealthEndpoint DockerLogsEndpoint DriftMonitorEndpoint
  HostManagerEndpoint LiveStatsEndpoint LogHeatmapEndpoint LogsEntriesEndpoint
  LogsFilesEndpoint QueueHealthEndpoint RuntimeEventsEndpoint SloViewEndpoint
  TlsCertArtifactEndpoint TlsMonitorEndpoint VolumeMonitorEndpoint
)
for api in "${baseline_api[@]}"; do
  [[ -f "scripts/admin-panel/src/Api/${api}.php" ]] || fail "baseline admin API missing: $api"
done

# Host-generation and runtime templates are part of the public Tools contract.
baseline_templates=(
  scripts/docker-templates/node.compose.yaml
  scripts/docker-templates/php.compose.yaml
  scripts/fpm-templates/local-dynamic-warm.conf.tpl
  scripts/fpm-templates/local-ondemand.conf.tpl
  scripts/fpm-templates/local-static-high.conf.tpl
  scripts/http-templates/node/nginx/http.node.nginx.conf
  scripts/http-templates/node/nginx/https.node.nginx.conf
  scripts/http-templates/node/nginx/redirect.nginx.conf
  scripts/http-templates/php/apache/http.apache.conf
  scripts/http-templates/php/apache/https.apache.conf
  scripts/http-templates/php/nginx/http.nginx.conf
  scripts/http-templates/php/nginx/https.nginx.conf
  scripts/http-templates/php/nginx/proxy-http.nginx.conf
  scripts/http-templates/php/nginx/proxy-https.nginx.conf
  scripts/http-templates/php/nginx/redirect.nginx.conf
  scripts/http-templates/proxyip/nginx/proxy-fixedip-http.nginx.conf
  scripts/http-templates/proxyip/nginx/proxy-fixedip-https.nginx.conf
  scripts/http-templates/proxyip/nginx/redirect.nginx.conf
)
for path in "${baseline_templates[@]}"; do
  [[ -f "$path" ]] || fail "baseline template missing: $path"
done

# Preserve user-facing CLI forms/options from main.
grep -Fq 'status [--json] [--quiet] [service]' scripts/shells/status.sh || fail 'status primary CLI contract missing'
grep -Fq 'status --docker-logs-json [--service <svc>] [--since <dur>] [--grep <text>] [--tail <n>]' scripts/shells/status.sh || fail 'status Docker-log CLI contract missing'
grep -Fq 'monitor-runtime [--json] [--project <name>] [--since <dur>] [--restart-threshold <n>] [--event-limit <n>]' scripts/shells/monitor-runtime.sh || fail 'runtime monitor CLI contract missing'
grep -Fq 'monitor-tls [--json] [--domain <pattern>] [--timeout <sec>] [--retries <n>]' scripts/shells/monitor-tls.sh || fail 'TLS monitor CLI contract missing'
grep -Fq 'monitor-db [--json] [--engine <all|mysql|mariadb|postgres|redis|mongodb|elasticsearch|db-client>]' scripts/shells/monitor-db.sh || fail 'DB monitor CLI contract missing'
grep -Fq 'monitor-volumes [--json] [--top <n>] [--inode-top <n>]' scripts/shells/monitor-volumes.sh || fail 'volume monitor CLI contract missing'
grep -Fq 'monitor-queue [--json] [--since <dur>] [--pending-threshold <n>] [--heartbeat-stale-sec <n>]' scripts/shells/monitor-queue.sh || fail 'queue monitor CLI contract missing'
grep -Fq 'monitor-slo [--json] [--timeout <sec>] [--paths <csv>]' scripts/shells/monitor-slo.sh || fail 'SLO monitor CLI contract missing'
grep -Fq 'monitor-log-heatmap [--json] [--source <both|docker|file>] [--since <dur>] [--bucket-min <n>] [--top <n>] [--line-limit <n>]' scripts/shells/monitor-log-heatmap.sh || fail 'log heatmap CLI contract missing'
grep -Fq 'monitor-drift [--json]' scripts/shells/monitor-drift.sh || fail 'drift monitor CLI contract missing'
grep -Fq 'init --local' scripts/shells/senv.sh || fail 'senv local init contract missing'
grep -Fq 'init --local-only' scripts/shells/senv.sh || fail 'senv local-only init contract missing'
grep -Fq 'Use --unsafe to bypass.' scripts/shells/senv.sh || fail 'senv unsafe override contract missing'

# Notifier token authentication is an existing optional feature, including an
# explicitly empty image default so compose/env overrides continue to work.
grep -Fq 'NOTIFY_TOKEN=""' Dockerfile || fail 'NOTIFY_TOKEN image contract missing'
grep -Fq 'TOKEN="${NOTIFY_TOKEN:-}"' scripts/shells/notifierd.sh || fail 'notifierd token contract missing'
grep -Fq 'TOKEN="${NOTIFY_TOKEN:-}"' scripts/shells/notify.sh || fail 'notify token contract missing'

echo 'feature parity contracts: ok'
