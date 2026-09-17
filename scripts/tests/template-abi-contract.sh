#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

NGINX_CONTRACT="0.4.1"
APACHE_CONTRACT="0.4.2"
RUNNER_CONTRACT="0.5"

fail() {
  printf 'template-abi-contract: %s\n' "$*" >&2
  exit 1
}

is_allowed_nginx_include() {
  case "$1" in
    /etc/nginx/fastcgi_params|\
    /etc/nginx/fastcgi_streaming|\
    /etc/nginx/proxy_params|\
    /etc/nginx/proxy_fixedip_headers|\
    /etc/nginx/proxy_timeouts|\
    /etc/nginx/proxy_buffers|\
    /etc/nginx/proxy_websocket|\
    /etc/nginx/proxy_streaming|\
    /etc/nginx/proxy_csp_relax|\
    /etc/nginx/proxy_h2_sanitize)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

# Literal template includes and dynamic include fragments emitted by mkhost must all
# exist in the hardened Nginx 0.4.1 image contract.
mapfile -t nginx_includes < <(
  {
    grep -RhoE 'include[[:space:]]+/etc/nginx/[A-Za-z0-9._-]+;' scripts/http-templates 2>/dev/null || true
    grep -oE 'include[[:space:]]+/etc/nginx/[A-Za-z0-9._-]+;' scripts/shells/mkhost.sh 2>/dev/null || true
  } |
    awk '{print $2}' |
    sed 's/;$//' |
    sort -u
)

((${#nginx_includes[@]} > 0)) || fail 'no Nginx includes discovered'
for include_path in "${nginx_includes[@]}"; do
  is_allowed_nginx_include "$include_path" || fail "unsupported Nginx include for ${NGINX_CONTRACT}: ${include_path}"
done

# The PHP templates must use the hardened FastCGI/proxy contracts rather than
# reintroducing legacy FCGID or fixed container-IP assumptions.
grep -Rq '/etc/nginx/fastcgi_params' scripts/http-templates/php/nginx || fail 'PHP Nginx templates lost fastcgi_params contract'
grep -Rq 'proxy_h2_sanitize' scripts/http-templates/php/nginx || fail 'Apache proxy templates lost H2 sanitation include'
if grep -RniE 'mod_fcgid|fcgid' scripts/http-templates scripts/fpm-templates scripts/shells/mkhost.sh; then
  fail "legacy mod_fcgid/Fcgid contract reintroduced; Apache ${APACHE_CONTRACT} uses proxy_fcgi"
fi
if grep -RniE '172\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}|10\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}|192\.168\.[0-9]{1,3}\.[0-9]{1,3}' scripts/http-templates scripts/docker-templates scripts/fpm-templates; then
  fail 'static private-IP assumption found in generated runtime templates'
fi

# Apache 0.4.2 contract: proxy_fcgi handler placeholder, TLS path, shared public
# root CA, and HTTP/2. The image deliberately does not install mod_fcgid.
grep -q '{{APACHE_PHP_HANDLER}}' scripts/http-templates/php/apache/http.apache.conf || fail 'Apache HTTP PHP handler placeholder missing'
grep -q '{{APACHE_PHP_HANDLER}}' scripts/http-templates/php/apache/https.apache.conf || fail 'Apache HTTPS PHP handler placeholder missing'
grep -q '/etc/mkcert/lds-server.pem' scripts/http-templates/php/apache/https.apache.conf || fail 'Apache TLS certificate path drifted'
grep -q '/etc/mkcert/lds-server-key.pem' scripts/http-templates/php/apache/https.apache.conf || fail 'Apache TLS key path drifted'
grep -q '/etc/share/rootCA/rootCA.pem' scripts/http-templates/php/apache/https.apache.conf || fail 'Apache public root CA path drifted'
grep -q 'Protocols h2 http/1.1' scripts/http-templates/php/apache/https.apache.conf || fail 'Apache HTTP/2 contract missing'
grep -q 'proxy:fcgi://' scripts/shells/mkhost.sh || fail 'mkhost no longer renders Apache proxy_fcgi handlers'

# Reserved product routes remain owned by hardened Nginx/LocalDevStack, never by
# per-project host templates.
if grep -RniE '(^|[^A-Za-z0-9.-])(admin|llm)\.localhost([^A-Za-z0-9.-]|$)' scripts/http-templates scripts/docker-templates scripts/fpm-templates; then
  fail 'reserved LocalDevStack route embedded in user-generated templates'
fi

# Runner 0.5 owns the supervisor control socket/config at this path; Tools may
# edit mounted scheduler files, but reload must target Runner's real contract.
grep -q 'ADMIN_PANEL_RUNNER_SUPERVISOR_CONF=/etc/supervisor/supervisord.conf' Dockerfile || fail 'Runner supervisor config path drifted'
grep -q "DEFAULT_SUPERVISOR_CTL_CONF = '/etc/supervisor/supervisord.conf'" scripts/admin-panel/src/Service/AutomationManagerService.php || fail 'admin Runner supervisor path drifted'

printf 'template-abi-contract: ok (nginx=%s apache=%s runner=%s)\n' "$NGINX_CONTRACT" "$APACHE_CONTRACT" "$RUNNER_CONTRACT"
