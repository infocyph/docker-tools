#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

NGINX_IMAGE="${NGINX_TEMPLATE_TEST_IMAGE:-infocyph/nginx:0.4.1}"
APACHE_IMAGE="${APACHE_TEMPLATE_TEST_IMAGE:-infocyph/apache:0.4.2}"
PHP_FPM_IMAGE="${PHP_FPM_TEMPLATE_TEST_IMAGE:-php:8.4-fpm-alpine}"

fail() {
  printf 'template-runtime-smoke: %s\n' "$*" >&2
  exit 1
}

for cmd in docker openssl sed grep find; do
  command -v "$cmd" >/dev/null 2>&1 || fail "required command missing: $cmd"
done

tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT INT TERM
mkdir -p "$tmp/nginx" "$tmp/apache" "$tmp/fpm" "$tmp/certs" "$tmp/rootCA"

openssl req -x509 -newkey rsa:2048 -nodes -days 1   -subj '/CN=app.localhost'   -keyout "$tmp/certs/lds-server-key.pem"   -out "$tmp/certs/lds-server.pem" >/dev/null 2>&1
cp "$tmp/certs/lds-server.pem" "$tmp/certs/lds-client-internal.pem"
cp "$tmp/certs/lds-server-key.pem" "$tmp/certs/lds-client-internal-key.pem"
cp "$tmp/certs/lds-server.pem" "$tmp/rootCA/rootCA.pem"

render_http_template() {
  local source="$1" destination="$2"
  sed     -e 's|{{SERVER_NAME}}|app.localhost|g'     -e 's|{{DOC_ROOT}}|/public|g'     -e 's|{{CLIENT_MAX_BODY_SIZE}}|50m|g'     -e 's|{{CLIENT_MAX_BODY_SIZE_APACHE}}|50000000|g'     -e 's|{{PHP_FCGI_PASS}}|127.0.0.1:9000|g'     -e 's|{{APACHE_PHP_HANDLER}}|SetHandler "proxy:fcgi://127.0.0.1:9000"|g'     -e 's|{{APACHE_CONTAINER}}|127.0.0.1|g'     -e 's|{{NODE_CONTAINER}}|127.0.0.1|g'     -e 's|{{NODE_PORT}}|3000|g'     -e 's|{{PROXY_IP}}|127.0.0.1|g'     -e 's|{{PROXY_HOST}}|upstream.localhost|g'     -e 's|{{PROXY_HTTP_PORT}}|8080|g'     -e 's|{{PROXY_HTTPS_PORT}}|8443|g'     -e 's|{{CLIENT_VERIFICATION}}|ssl_verify_client off;|g'     -e 's|{{PROXY_STREAMING_INCLUDE}}||g'     -e 's|{{FASTCGI_STREAMING_INCLUDE}}||g'     -e 's|{{APACHE_STREAMING_INCLUDE}}||g'     -e 's|{{PROXY_COOKIE_EXACT_INCLUDE}}||g'     -e 's|{{PROXY_COOKIE_PARENT_INCLUDE}}||g'     -e 's|{{PROXY_CSP_INCLUDE}}||g'     -e 's|{{PROXY_REDIRECT_INCLUDE}}||g'     -e 's|{{PROXY_SUBFILTER_INCLUDE}}||g'     -e 's|{{PROXY_WS_INCLUDE}}||g'     "$source" >"$destination"

  if grep -Eq '{{[A-Z0-9_]+}}' "$destination"; then
    grep -nE '{{[A-Z0-9_]+}}' "$destination" >&2 || true
    fail "unresolved placeholder in $source"
  fi
}

render_fpm_template() {
  local source="$1" destination="$2"
  sed     -e 's|{{POOL_NAME}}|app_ci|g'     -e 's|{{FPM_USER}}|www-data|g'     -e 's|{{FPM_GROUP}}|www-data|g'     -e 's|{{SOCK_PATH}}|/tmp/app-ci.sock|g'     -e 's|{{ERROR_LOG}}|/tmp/app-ci.error.log|g'     -e 's|{{ACCESS_LOG}}|/tmp/app-ci.access.log|g'     "$source" >"$destination"

  grep -Eq '{{[A-Z0-9_]+}}' "$destination" && fail "unresolved FPM placeholder in $source"
  return 0
}

docker pull "$NGINX_IMAGE" >/dev/null
docker pull "$APACHE_IMAGE" >/dev/null
docker pull "$PHP_FPM_IMAGE" >/dev/null

while IFS= read -r template; do
  rendered="$tmp/nginx/zz-tools.conf"
  render_http_template "$template" "$rendered"
  docker run --rm -e AUTO_DISABLE_INVALID_CONFS=0 -e AUTO_RESTORE_DISABLED_CONFS=0     -v "$rendered:/etc/nginx/conf.d/zz-tools.conf:ro"     -v "$tmp/certs:/etc/mkcert:ro"     -v "$tmp/rootCA:/etc/share/rootCA:ro"     "$NGINX_IMAGE" nginx -t >/dev/null
done < <(find scripts/http-templates -type f -path '*/nginx/*.conf' -print | LC_ALL=C sort)

while IFS= read -r template; do
  rendered="$tmp/apache/zz-tools.conf"
  render_http_template "$template" "$rendered"
  docker run --rm     --entrypoint httpd     -v "$rendered:/usr/local/apache2/conf/vhosts/zz-tools.conf:ro"     -v "$tmp/certs:/etc/mkcert:ro"     -v "$tmp/rootCA:/etc/share/rootCA:ro"     "$APACHE_IMAGE" -t >/dev/null
done < <(find scripts/http-templates -type f -path '*/apache/*.conf' -print | LC_ALL=C sort)

while IFS= read -r template; do
  rendered="$tmp/fpm/zz-tools.conf"
  render_fpm_template "$template" "$rendered"
  docker run --rm     --entrypoint php-fpm     -v "$rendered:/usr/local/etc/php-fpm.d/zz-tools.conf:ro"     "$PHP_FPM_IMAGE" -tt >/dev/null
done < <(find scripts/fpm-templates -type f -name '*.tpl' -print | LC_ALL=C sort)

printf 'template-runtime-smoke: ok (nginx=%s apache=%s php-fpm=%s)\n'   "$NGINX_IMAGE" "$APACHE_IMAGE" "$PHP_FPM_IMAGE"
