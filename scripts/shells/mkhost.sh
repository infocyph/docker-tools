#!/usr/bin/env bash
# mkhost.sh — vhost + runtime chooser (PHP/Node/ProxyIP) for LocalDevStack
#
# App types:
#  - PHP: Nginx or Apache (proxied by Nginx)
#  - NodeJs: Nginx reverse proxy to per-domain Node service
#  - Proxy (Fixed IP): Nginx reverse proxy to a pinned upstream IP (:80/:443) with upstream Host/SNI

set -euo pipefail

###############################################################################
# 0) Constants / Tunables
###############################################################################
readonly RUNTIME_VERSIONS_DB="${RUNTIME_VERSIONS_DB:-/etc/share/runtime-versions.json}"
readonly MAX_VERSIONS="${MAX_VERSIONS:-16}"
readonly NGINX_TEMPLATE_DIR="${NGINX_TEMPLATE_DIR:-/etc/http-templates/nginx}"
readonly APACHE_TEMPLATE_DIR="${APACHE_TEMPLATE_DIR:-/etc/http-templates/apache}"
readonly DOCKER_TEMPLATE_DIRECTORY="${DOCKER_TEMPLATE_DIRECTORY:-/etc/docker-templates}"
readonly VHOST_NGINX_DIR="${VHOST_NGINX_DIR:-/etc/share/vhosts/nginx}"
readonly VHOST_APACHE_DIR="${VHOST_APACHE_DIR:-/etc/share/vhosts/apache}"
readonly VHOST_FPM_DIR="${VHOST_FPM_DIR:-/etc/share/vhosts/fpm}"
readonly FPM_TEMPLATE_DIR="${FPM_TEMPLATE_DIR:-/etc/fpm-templates}"
readonly PHP_FPM_SOCK_DIR="${PHP_FPM_SOCK_DIR:-/home/${USERNAME}/.run/php-fpm}"
readonly WEB_FPM_SOCK_DIR="${WEB_FPM_SOCK_DIR:-/run/php-fpm}"
readonly VHOST_DOCKER_COMPOSE_DIR="${VHOST_DOCKER_COMPOSE_DIR:-/etc/share/vhosts/docker-compose}"
readonly ENV_STORE_JSON="${ENV_STORE_JSON:-/etc/share/state/env-store.json}"
readonly MKHOST_STATE_KEY="${MKHOST_STATE_KEY:-MKHOST_STATE}"
readonly NODE_PORT="${NODE_PORT:-3000}"
readonly COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-LocalDevStack}"
readonly APP_SCAN_DIR="${APP_SCAN_DIR:-/app}"

###############################################################################
# 1) Colors + UI (higher contrast)
###############################################################################
BOLD=$'\033[1m'
DIM=$'\033[2m'
RED=$'\033[1;31m'
GREEN=$'\033[1;32m'
CYAN=$'\033[1;36m'
YELLOW=$'\033[1;33m'
MAGENTA=$'\033[1;35m'
NC=$'\033[0m'

say()  { echo -e "$*"; }
ok()   { say "${GREEN}$*${NC}"; }
warn() { say "${YELLOW}$*${NC}"; }
err()  { say "${RED}$*${NC}"; }

###############################################################################
# 2) Preconditions
###############################################################################
need_cmd() { command -v "$1" >/dev/null 2>&1 || { err "Error: '$1' not found."; exit 1; }; }

require_versions_db() {
  need_cmd jq
  [[ -r "$RUNTIME_VERSIONS_DB" ]] || { err "Error: versions DB not found/readable: $RUNTIME_VERSIONS_DB"; exit 1; }
}

# Preflight templates (fail fast; do NOT print template directory)
required_tpls=(
  "nginx:redirect.nginx.conf"
  "nginx:http.nginx.conf"
  "nginx:https.nginx.conf"
  "nginx:http.node.nginx.conf"
  "nginx:https.node.nginx.conf"
  "nginx:proxy-http.nginx.conf"
  "nginx:proxy-https.nginx.conf"
  "nginx:proxy-fixedip-http.nginx.conf"
  "nginx:proxy-fixedip-https.nginx.conf"
  "apache:http.apache.conf"
  "apache:https.apache.conf"
  "node:node.compose.yaml"
  "php:php.compose.yaml"
)

preflight_templates() {
  local entry kind f dir
  for entry in "${required_tpls[@]}"; do
    kind="${entry%%:*}"
    f="${entry#*:}"
    case "$kind" in
      nginx)  dir="$NGINX_TEMPLATE_DIR" ;;
      apache) dir="$APACHE_TEMPLATE_DIR" ;;
      node|php) dir="$DOCKER_TEMPLATE_DIRECTORY" ;;
      *) err "Error: invalid template kind: $kind"; exit 1 ;;
    esac
    [[ -r "$dir/$f" ]] || { err "Error: missing template: $f"; exit 1; }
  done
}

###############################################################################
# 3) Generic input helpers (single-line step prompts)
###############################################################################
trim() { echo "${1:-}" | xargs; }

_prompt_line() {
  # _prompt_line <n> <t> <label> <suffix> <default_display?>
  local n="$1" t="$2" label="$3" suffix="${4:-}" defdisp="${5:-}"
  if [[ -n "$defdisp" ]]; then
    echo -e "${YELLOW}${BOLD}Step ${n} of ${t}:${NC} ${CYAN}${BOLD}${label}${NC}${suffix} (${YELLOW}${BOLD}${defdisp}${NC}): "
  else
    echo -e "${YELLOW}${BOLD}Step ${n} of ${t}:${NC} ${CYAN}${BOLD}${label}${NC}${suffix}: "
  fi
}

step_ask_text_required() {
  # step_ask_text_required <n> <t> <label> <var> [hint]
  local n="$1" t="$2" label="$3" __var="$4" hint="${5:-}"
  local ans="" suffix=""
  [[ -n "$hint" ]] && suffix=" ${DIM}(${hint})${NC}"
  while true; do
    read -e -r -p "$(_prompt_line "$n" "$t" "$label" "$suffix")" ans
    ans="$(trim "$ans")"
    [[ -n "$ans" ]] || { err "Input cannot be empty."; continue; }
    printf -v "$__var" '%s' "$ans"
    return 0
  done
}

step_ask_text_default() {
  # step_ask_text_default <n> <t> <label> <var> <default_value> [hint]
  local n="$1" t="$2" label="$3" __var="$4" def="$5" hint="${6:-}"
  local ans="" suffix=""
  [[ -n "$hint" ]] && suffix=" ${DIM}(${hint})${NC}"
  read -e -r -p "$(_prompt_line "$n" "$t" "$label" "$suffix" "$def")" ans
  ans="$(trim "${ans:-$def}")"
  [[ -n "$ans" ]] || ans="$def"
  printf -v "$__var" '%s' "$ans"
}

step_yn_default() {
  # step_yn_default <n> <t> <label> <var> <default_y_or_n> [hint]
  local n="$1" t="$2" label="$3" __var="$4" def="${5:-n}" hint="${6:-}"
  local ans="" suffix="" opt=""
  [[ -n "$hint" ]] && suffix=" ${DIM}(${hint})${NC}"
  def="${def,,}"
  if [[ "$def" == "y" ]]; then opt=" ${YELLOW}(Y/n)${NC}"; else opt=" ${YELLOW}(y/N)${NC}"; fi
  while true; do
    read -e -r -p "$(echo -e "${YELLOW}${BOLD}Step ${n} of ${t}:${NC} ${CYAN}${BOLD}${label}${NC}${suffix}${opt}: ")" ans
    ans="$(trim "$ans")"
    ans="${ans,,}"
    [[ -z "$ans" ]] && ans="$def"
    case "$ans" in
    y|yes) printf -v "$__var" '%s' "y"; return 0 ;;
    n|no)  printf -v "$__var" '%s' "n"; return 0 ;;
    *) err "Enter y or n." ;;
    esac
  done
}

# Non-step confirmation (used for final proceed; NOT counted as a step)
ask_yn_default() {
  # ask_yn_default <label> <var> <default_y_or_n>
  local label="$1" __var="$2" def="${3:-y}"
  local ans="" opt=""
  def="${def,,}"
  if [[ "$def" == "y" ]]; then opt=" ${YELLOW}(Y/n)${NC}"; else opt=" ${YELLOW}(y/N)${NC}"; fi
  while true; do
    read -e -r -p "$(echo -e "${CYAN}${BOLD}${label}${NC}${opt}: ")" ans
    ans="$(trim "$ans")"
    ans="${ans,,}"
    [[ -z "$ans" ]] && ans="$def"
    case "$ans" in
    y|yes) printf -v "$__var" '%s' "y"; return 0 ;;
    n|no)  printf -v "$__var" '%s' "n"; return 0 ;;
    *) err "Enter y or n." ;;
    esac
  done
}

pick_index_required() {
  # pick_index_required <n> <t> <label> <max> <var> [hint]
  local n="$1" t="$2" label="$3" max="$4" __var="$5" hint="${6:-}"
  local ans="" suffix=""
  [[ -n "$hint" ]] && suffix=" ${DIM}(${hint})${NC}"
  while true; do
    read -e -r -p "$(_prompt_line "$n" "$t" "$label" "$suffix")" ans
    ans="$(trim "$ans")"
    [[ "$ans" =~ ^[0-9]+$ ]] || { err "Enter a number."; continue; }
    (( ans >= 0 && ans <= max )) || { err "Out of range (0-${max})."; continue; }
    printf -v "$__var" '%s' "$ans"
    return 0
  done
}

pick_index_default_value() {
  # pick_index_default_value <n> <t> <label> <max> <default_index> <default_display> <var> [hint]
  local n="$1" t="$2" label="$3" max="$4" def_i="$5" def_disp="$6" __var="$7" hint="${8:-}"
  local ans="" suffix=""
  [[ -n "$hint" ]] && suffix=" ${DIM}(${hint})${NC}"
  while true; do
    read -e -r -p "$(_prompt_line "$n" "$t" "$label" "$suffix" "$def_disp")" ans
    ans="$(trim "$ans")"
    [[ -z "$ans" ]] && ans="$def_i"
    [[ "$ans" =~ ^[0-9]+$ ]] || { err "Enter a number."; continue; }
    (( ans >= 0 && ans <= max )) || { err "Out of range (0-${max})."; continue; }
    printf -v "$__var" '%s' "$ans"
    return 0
  done
}

###############################################################################
# 4) Env store helpers
###############################################################################
env_store_exec() {
  command -v env-store >/dev/null 2>&1 || { err "Error: 'env-store' not found."; exit 1; }
  local store_json="$ENV_STORE_JSON"
  env ENV_STORE_JSON="$store_json" env-store "$@"
}

env_set() {
  local key="$1" value="$2"
  env_store_exec set "$key" "$value" >/dev/null
}
env_get() {
  local key="$1"
  env_store_exec get "$key" || true
}

env_set_json() {
  local key="$1" value_json="$2"
  env_store_exec set-json "$key" "$value_json" >/dev/null
}

mkhost_sync_state() {
  local state_json ts apache_active active_php active_node
  ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || true)"
  apache_active="$(env_get "APACHE_ACTIVE")"
  active_php="$(env_get "ACTIVE_PHP_PROFILE")"
  active_node="$(env_get "ACTIVE_NODE_PROFILE")"

  state_json="$(jq -cn \
    --arg ts "$ts" \
    --arg apache_active "$apache_active" \
    --arg active_php "$active_php" \
    --arg active_node "$active_node" \
    '{
      version: 1,
      updated_at: $ts,
      state: {
        apache_active: $apache_active,
        active_php_profile: $active_php,
        active_node_profile: $active_node
      }
    }')"

  env_set_json "$MKHOST_STATE_KEY" "$state_json"
}

mkhost_get_state_json() {
  env_store_exec get-json "$MKHOST_STATE_KEY" --default-json '{}' || printf '{}\n'
}

###############################################################################
# 5) Validation helpers
###############################################################################
validate_domain() {
  local d="$1"
  local re='^([a-zA-Z0-9]([-a-zA-Z0-9]{0,61}[a-zA-Z0-9])?\.)+(localhost|local|test|loc|[a-zA-Z]{2,})$'
  [[ "$d" =~ $re ]]
}

validate_ipv4() {
  local ip="$1"
  [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
  local o IFS='.'
  read -r o1 o2 o3 o4 <<<"$ip"
  for o in "$o1" "$o2" "$o3" "$o4"; do
    [[ "$o" =~ ^[0-9]+$ ]] || return 1
    (( o >= 0 && o <= 255 )) || return 1
  done
  return 0
}

validate_ipv6_loose() {
  local ip="$1"
  # Loose but practical validation (covers common forms including ::)
  [[ "$ip" =~ ^[0-9a-fA-F:]+$ ]] || return 1
  [[ "$ip" == *:* ]] || return 1
  return 0
}

validate_ip() {
  local ip="$1"
  validate_ipv4 "$ip" && return 0
  validate_ipv6_loose "$ip" && return 0
  return 1
}

validate_port() {
  local p="${1:-}"
  [[ "$p" =~ ^[0-9]+$ ]] || return 1
  (( p >= 1 && p <= 65535 ))
}


normalize_rel_path() {
  local p
  p="$(trim "${1:-}")"
  [[ "$p" == /* ]] || p="/$p"
  while [[ "$p" == *"//"* ]]; do p="${p//\/\//\/}"; done
  [[ "$p" != "/" ]] && p="${p%/}"
  echo "$p"
}

slugify() { echo "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/_/g; s/^_+|_+$//g'; }

to_env_key() {
  local v; v="$(trim "${1:-}")"; v="${v,,}"
  case "$v" in
  current) echo "CURRENT" ;;
  lts)     echo "LTS" ;;
  '')      echo "" ;;
  *) echo "$v" | sed -E 's/[^0-9]+//g' ;;
  esac
}

fmt_range() {
  local debut="${1:-}" eol="${2:-}"
  [[ -z "$debut" || "$debut" == "null" ]] && debut="unknown"
  [[ -z "$eol"   || "$eol"   == "null" ]] && eol="unknown"
  echo "(${debut} to ${eol})"
}

fmt_eol_tilde() {
  local eol="${1:-}"
  [[ -z "$eol" || "$eol" == "null" ]] && eol="unknown"
  echo "(~${eol})"
}

###############################################################################
# 6) Version validators (JSON-driven)
###############################################################################
php_is_valid_custom() {
  local v="$1"
  [[ "$v" =~ ^[0-9]+\.[0-9]+$ ]] || return 1
  jq -e --arg v "$v" '.php.all[]? | select(.version == $v)' "$RUNTIME_VERSIONS_DB" >/dev/null 2>&1
}

node_is_valid_custom() {
  local v="$1"
  [[ "$v" =~ ^[0-9]+$ ]] || return 1
  jq -e --arg v "$v" '.node.all[]? | select(.version == $v)' "$RUNTIME_VERSIONS_DB" >/dev/null 2>&1
}

###############################################################################
# 7) Doc-root suggestions (two-column menu)
###############################################################################
collect_docroot_options() {
  local base="$APP_SCAN_DIR"
  local -a out=()

  [[ -d "$base/public" ]] && out+=("/public")

  if [[ -d "$base" ]]; then
    while IFS= read -r -d '' d; do
      local name; name="$(basename "$d")"
      [[ "$name" == .* ]] && continue
      out+=("/$name")
      [[ -d "$d/public" ]] && out+=("/$name/public")
    done < <(find "$base" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null || true)
  fi

  # de-dup
  local seen="|" opt
  local -a uniq=()
  for opt in "${out[@]}"; do
    opt="${opt:-}"
    [[ -n "$opt" ]] || continue
    if [[ "$seen" != *"|$opt|"* ]]; then
      seen="${seen}${opt}|"
      uniq+=("$opt")
    fi
  done

  # Grouped sort:
  #  - group_key: "/x" for "/x" and "/x/public"
  #  - depth: slash count ("/x" < "/x/public")
  #  - full path: final tiebreaker
  local rec path full depth group key
  while IFS= read -r -d '' rec; do
    path="${rec#*$'\t'}"; path="${path#*$'\t'}"; path="${path#*$'\t'}"
    [[ -n "$path" ]] && printf '%s\0' "$path"
  done < <(
    for path in "${uniq[@]}"; do
      [[ -n "$path" ]] || continue
      depth="${path//[^\/]/}"; depth="${#depth}"
      group="$path"
      if [[ "$group" == */public ]]; then
        group="${group%/public}"
        [[ -n "$group" ]] || group="/"
      fi
      key="${group,,}"
      printf '%s\t%s\t%s\t%s\0' "$key" "$depth" "$path" "$path"
    done | LC_ALL=C sort -z -f -t $'\t' -k1,1 -k2,2n -k3,3
  )
}

print_two_column_menu() {
  local arr_name="$1" start="$2"
  local -n arr="$arr_name"

  local i width=0
  for ((i=start; i<${#arr[@]}; i++)); do
    ((${#arr[i]} > width)) && width=${#arr[i]}
  done
  ((width < 10)) && width=10
  local colw=$((width + 7))

  local idx
  for ((idx=start; idx<${#arr[@]}; idx+=2)); do
    local left_i="$idx"
    local right_i=$((idx+1))
    local left="  $(printf '%3d) ' "$left_i")${arr[left_i]}"
    if (( right_i < ${#arr[@]} )); then
      local right="  $(printf '%3d) ' "$right_i")${arr[right_i]}"
      printf "%-${colw}s%s\n" "$left" "$right"
    else
      printf "%s\n" "$left"
    fi
  done
}

###############################################################################
# 8) Template rendering
###############################################################################
sed_escape_repl() { echo "${1:-}" | sed -e 's/[\/&|\\]/\\&/g'; }

render_template() {
  local tpl="$1" outFile="$2"
  [[ -r "$tpl" ]] || { err "Template not readable: $(basename "$tpl")"; exit 1; }

  local tmp; tmp="$(mktemp)"

  # Defaults (avoid set -u surprises)
  : "${DOMAIN_NAME:=}"
  : "${DOC_ROOT:=}"
  : "${CLIENT_MAX_BODY_SIZE:=}"
  : "${CLIENT_MAX_BODY_SIZE_APACHE:=}"
  : "${PROXY_STREAMING_INCLUDE:=}"
  : "${FASTCGI_STREAMING_INCLUDE:=}"
  : "${APACHE_STREAMING_INCLUDE:=}"
  : "${PHP_APACHE_CONTAINER:=}"
  : "${APACHE_CONTAINER:=APACHE}"
  : "${PHP_CONTAINER:=}"

  : "${PHP_FCGI_PASS:=}"
  : "${APACHE_PHP_HANDLER:=}"
  : "${FPM_POOL_NAME:=}"
  : "${FPM_SOCK_PATH:=}"
  : "${FPM_ERROR_LOG:=}"
  : "${FPM_ACCESS_LOG:=}"
  : "${FPM_USER:=www-data}"
  : "${FPM_GROUP:=www-data}"
  : "${ENABLE_CLIENT_VERIFICATION:=ssl_verify_client off;}"
  : "${NODE_CONTAINER:=}"
  : "${NODE_PORT:=3000}"
  : "${NODE_ACCESS_LOG_FILE:=}"
  : "${NODE_ERROR_LOG_FILE:=}"
  : "${PHP_PROFILE:=}"
  : "${PHP_SERVICE:=}"
  : "${PHP_CONTAINER_NAME:=}"
  : "${PHP_HOSTNAME:=}"
  : "${PHP_KEY:=}"
  : "${PHP_VERSION:=}"

  : "${PROXY_IP:=}"
  : "${PROXY_HOST:=}"
  : "${PROXY_HTTP_PORT:=80}"
  : "${PROXY_HTTPS_PORT:=443}"
  : "${PROXY_COOKIE_EXACT_INCLUDE:=}"
  : "${PROXY_COOKIE_PARENT_INCLUDE:=}"
  : "${PROXY_REDIRECT_INCLUDE:=}"
  : "${PROXY_WS_INCLUDE:=}"
  : "${PROXY_SUBFILTER_INCLUDE:=}"
  : "${PROXY_CSP_INCLUDE:=}"

  # Bash-native templating (supports multiline replacements safely).
  # IMPORTANT: token/value arrays MUST be aligned 1:1 in the same order.
  local -a _tpl_tokens=(
    '{{SERVER_NAME}}' '{{DOC_ROOT}}' '{{CLIENT_MAX_BODY_SIZE}}' '{{CLIENT_MAX_BODY_SIZE_APACHE}}'
    '{{PROXY_STREAMING_INCLUDE}}' '{{FASTCGI_STREAMING_INCLUDE}}' '{{APACHE_STREAMING_INCLUDE}}'
    '{{PHP_APACHE_CONTAINER}}' '{{APACHE_CONTAINER}}' '{{PHP_CONTAINER}}'
    '{{CLIENT_VERIFICATION}}'
    '{{NODE_CONTAINER}}' '{{NODE_PORT}}'
    '{{PROXY_IP}}' '{{PROXY_HOST}}' '{{PROXY_HTTP_PORT}}' '{{PROXY_HTTPS_PORT}}'
    '{{PROXY_COOKIE_EXACT_INCLUDE}}' '{{PROXY_COOKIE_PARENT_INCLUDE}}' '{{PROXY_REDIRECT_INCLUDE}}'
    '{{PROXY_WS_INCLUDE}}' '{{PROXY_SUBFILTER_INCLUDE}}' '{{PROXY_CSP_INCLUDE}}'
    '{{COMPOSE_PROJECT_NAME}}' '{{NODE_SERVICE}}' '{{NODE_CONTAINER_NAME}}' '{{NODE_HOSTNAME}}'
    '{{PHP_FCGI_PASS}}' '{{APACHE_PHP_HANDLER}}'
    '{{POOL_NAME}}' '{{SOCK_PATH}}' '{{ERROR_LOG}}' '{{ACCESS_LOG}}' '{{FPM_USER}}' '{{FPM_GROUP}}'
    '{{NODE_PROFILE}}' '{{NODE_VERSION}}' '{{NODE_KEY}}' '{{NODE_CMD_LINE}}'
    '{{NODE_ACCESS_LOG_FILE}}' '{{NODE_ERROR_LOG_FILE}}'
    '{{PHP_PROFILE}}' '{{PHP_SERVICE}}' '{{PHP_CONTAINER_NAME}}' '{{PHP_HOSTNAME}}' '{{PHP_KEY}}' '{{PHP_VERSION}}'
  )

  local -a _tpl_values=(
    "$DOMAIN_NAME" "$DOC_ROOT" "$CLIENT_MAX_BODY_SIZE" "$CLIENT_MAX_BODY_SIZE_APACHE"
    "$PROXY_STREAMING_INCLUDE" "$FASTCGI_STREAMING_INCLUDE" "$APACHE_STREAMING_INCLUDE"
    "$PHP_APACHE_CONTAINER" "$APACHE_CONTAINER" "$PHP_CONTAINER"
    "$ENABLE_CLIENT_VERIFICATION"
    "$NODE_CONTAINER" "$NODE_PORT"
    "$PROXY_IP" "$PROXY_HOST" "$PROXY_HTTP_PORT" "$PROXY_HTTPS_PORT"
    "$PROXY_COOKIE_EXACT_INCLUDE" "$PROXY_COOKIE_PARENT_INCLUDE" "$PROXY_REDIRECT_INCLUDE"
    "$PROXY_WS_INCLUDE" "$PROXY_SUBFILTER_INCLUDE" "$PROXY_CSP_INCLUDE"
    "${COMPOSE_PROJECT_NAME:-}" "${NODE_SERVICE:-}" "${NODE_CONTAINER_NAME:-}" "${NODE_HOSTNAME:-}"
    "$PHP_FCGI_PASS" "$APACHE_PHP_HANDLER"
    "$FPM_POOL_NAME" "$FPM_SOCK_PATH" "$FPM_ERROR_LOG" "$FPM_ACCESS_LOG" "$FPM_USER" "$FPM_GROUP"
    "${NODE_PROFILE:-}" "${NODE_VERSION:-}" "${NODE_KEY:-}" "${NODE_CMD_LINE:-}"
    "${NODE_ACCESS_LOG_FILE:-}" "${NODE_ERROR_LOG_FILE:-}"
    "${PHP_PROFILE:-}" "${PHP_SERVICE:-}" "${PHP_CONTAINER_NAME:-}" "${PHP_HOSTNAME:-}" "${PHP_KEY:-}" "${PHP_VERSION:-}"
  )

  # Sanity check: prevent silent template corruption
  if ((${#_tpl_tokens[@]} != ${#_tpl_values[@]})); then
    err "Template token/value mismatch: tokens=${#_tpl_tokens[@]} values=${#_tpl_values[@]}"
    exit 1
  fi

  local line i tok val
  while IFS= read -r line || [[ -n "$line" ]]; do
    for ((i = 0; i < ${#_tpl_tokens[@]}; i++)); do
      tok="${_tpl_tokens[$i]}"
      val="${_tpl_values[$i]}"
      line="${line//$tok/$val}"
    done
    printf '%s\n' "$line"
  done <"$tpl" >"$tmp"

  install -m 0644 "$tmp" "$outFile"
  rm -f "$tmp"
}

###############################################################################
# 8b) LDS metadata headers (written into generated configs)
###############################################################################
_meta_kv() { # _meta_kv <k> <v>
  local k="$1" v="${2:-}"
  [[ -n "$v" ]] && printf '# LDS-META: %s=%s\n' "$k" "$v"
}

meta_header_nginx() {
  # Emits comment header for nginx vhost config (single-domain context)
  local domain="$DOMAIN_NAME"
  _meta_kv "domain" "$domain"
  _meta_kv "app" "${APP_TYPE:-}"
  _meta_kv "server" "nginx"
  _meta_kv "docroot" "${DOC_ROOT:-}"
  if [[ "${APP_TYPE:-}" == "php" ]]; then
    _meta_kv "php_version" "${PHP_VERSION:-}"
    _meta_kv "php_profile" "${PHP_CONTAINER_PROFILE:-}"
    _meta_kv "php_container" "${PHP_CONTAINER:-}"
    _meta_kv "fpm_pool" "${VHOST_FPM_DIR}/${PHP_CONTAINER_PROFILE}/${domain}.conf"
    _meta_kv "fpm_mode" "${PHP_UPSTREAM_MODE:-tcp}"
    if [[ "${PHP_UPSTREAM_MODE:-tcp}" == "socket" ]]; then
      _meta_kv "fpm_template" "$(basename "${PHP_FPM_TEMPLATE:-}")"
      _meta_kv "sock_web" "${WEB_FPM_SOCK_DIR}/${domain}.sock"
      _meta_kv "sock_fpm" "${PHP_FPM_SOCK_DIR}/${domain}.sock"
    else
      _meta_kv "fcgi" "${PHP_CONTAINER:-}:9000"
    fi
  elif [[ "${APP_TYPE:-}" == "node" ]]; then
    _meta_kv "node_version" "${NODE_VERSION:-}"
    _meta_kv "node_profile" "${NODE_PROFILE:-}"
    _meta_kv "node_service" "${NODE_SERVICE:-}"
    _meta_kv "node_container" "${NODE_CONTAINER_NAME:-}"
    _meta_kv "node_port" "${NODE_PORT:-}"
  elif [[ "${APP_TYPE:-}" == "proxyip" ]]; then
    _meta_kv "proxy_host" "${PROXY_HOST:-}"
    _meta_kv "proxy_ip" "${PROXY_IP:-}"
    _meta_kv "proxy_http_port" "${PROXY_HTTP_PORT:-80}"
    _meta_kv "proxy_https_port" "${PROXY_HTTPS_PORT:-443}"
  fi
}


prepend_header_if_missing() {
  # prepend_header_if_missing <header_fn> <file>
  local header_fn="$1" f="$2"
  [[ -f "$f" ]] || return 0
  if head -n 5 "$f" | grep -q '^# LDS-META:'; then
    return 0
  fi
  local tmp; tmp="$(mktemp)"
  "$header_fn" >"$tmp"
  printf '# LDS-META: generated_at=%s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" >>"$tmp"
  printf '# LDS-META: project=%s\n' "${COMPOSE_PROJECT_NAME:-}" >>"$tmp"
  printf '\n' >>"$tmp"
  cat "$f" >>"$tmp"
  install -m 0644 "$tmp" "$f"
  rm -f "$tmp"
}

###############################################################################
# 9) Compose generators (Node per-domain, PHP per-version)
###############################################################################

compose_on_exists_mode() {
  local mode="${COMPOSE_FILE_ON_EXISTS:-replace}"
  mode="${mode,,}"
  case "$mode" in
    replace|overwrite) echo "replace" ;;
    skip) echo "skip" ;;
    *)
      warn "Invalid COMPOSE_FILE_ON_EXISTS='${mode}'; using 'replace'"
      echo "replace"
      ;;
  esac
}

write_compose_template() {
  # write_compose_template <template> <out>
  # return codes:
  #   0  -> created
  #   10 -> skipped (exists + mode=skip)
  #   11 -> replaced (exists + mode=replace)
  local tpl="$1" outPath="$2"
  local existed=0 mode=""
  [[ -e "$outPath" ]] && existed=1
  mode="$(compose_on_exists_mode)"
  if (( existed )) && [[ "$mode" == "skip" ]]; then
    return 10
  fi
  render_template "$tpl" "$outPath"
  if (( existed )); then
    return 11
  fi
  return 0
}

create_node_compose() {
  mkdir -p "$VHOST_DOCKER_COMPOSE_DIR"

  local domain_token token svc cname profile node_key
  domain_token="$(slugify "$DOMAIN_NAME")"
  token="${NODE_DIR_TOKEN:-$domain_token}"

  svc="node_${token}"
  cname="NODE_${token^^}"
  profile="node_${token}"

  NODE_SERVICE="$svc"
  NODE_CONTAINER="$svc"
  NODE_PROFILE="$profile"

  node_key="$(to_env_key "$NODE_VERSION")"

  local outPath="${VHOST_DOCKER_COMPOSE_DIR}/${token}.yaml"

  # Prepare compose templating vars
  NODE_CONTAINER_NAME="$cname"
  NODE_HOSTNAME="$svc"
  NODE_KEY="$node_key"
  NODE_ACCESS_LOG_FILE="${DOMAIN_NAME}.access.log"
  NODE_ERROR_LOG_FILE="${DOMAIN_NAME}.error.log"

  if [[ -n "${NODE_CMD:-}" ]]; then
    # Preserve one-line command (no newlines) and keep YAML safe.
    local esc
    esc="${NODE_CMD//$'\r'/}"
    esc="${esc//$'\n'/ }"
    esc="${esc//\\/\\\\}"
    esc="${esc//\"/\\\"}"
    NODE_CMD_LINE='- NODE_CMD=${NODE_CMD:-"'"${esc}"'"}'
  else
    NODE_CMD_LINE='- NODE_CMD=${NODE_CMD:-}'
  fi

  local tpl="${DOCKER_TEMPLATE_DIRECTORY}/node.compose.yaml"
  local compose_rc=0
  write_compose_template "$tpl" "$outPath" || compose_rc=$?
  case "$compose_rc" in
    0)  NODE_COMPOSE_ACTION="created" ;;
    10) NODE_COMPOSE_ACTION="skipped" ;;
    11) NODE_COMPOSE_ACTION="replaced" ;;
    *)  return "$compose_rc" ;;
  esac

  env_set "ACTIVE_NODE_PROFILE" "$profile"
  NODE_COMPOSE_FILE_BASENAME="$(basename "$outPath")"
}

create_php_compose() {
  mkdir -p "$VHOST_DOCKER_COMPOSE_DIR"

  local profile php_key svc cname host outPath tpl
  profile="${PHP_CONTAINER_PROFILE}"
  php_key="$(to_env_key "$PHP_VERSION")"
  svc="$profile"
  cname="PHP_${PHP_VERSION}"
  host="php-${php_key}"

  PHP_PROFILE="$profile"
  PHP_SERVICE="$svc"
  PHP_CONTAINER_NAME="$cname"
  PHP_HOSTNAME="$host"
  PHP_KEY="$php_key"

  outPath="${VHOST_DOCKER_COMPOSE_DIR}/${profile}.yaml"
  tpl="${DOCKER_TEMPLATE_DIRECTORY}/php.compose.yaml"

  local compose_rc=0
  write_compose_template "$tpl" "$outPath" || compose_rc=$?
  case "$compose_rc" in
    0)  PHP_COMPOSE_ACTION="created" ;;
    10) PHP_COMPOSE_ACTION="skipped" ;;
    11) PHP_COMPOSE_ACTION="replaced" ;;
    *)  return "$compose_rc" ;;
  esac

  PHP_COMPOSE_FILE_BASENAME="$(basename "$outPath")"
}

###############################################################################
# 10) Config generation
###############################################################################
_write_empty_conf() { : >"$1"; chmod 0644 "$1"; }

_merge_confs() {
  # merge existing content + new content into target
  local existing="$1" target="$2"
  if [[ -s "$existing" ]]; then
    cat "$existing" >"${target}.tmpmerge"
    cat "$target" >>"${target}.tmpmerge"
    install -m 0644 "${target}.tmpmerge" "$target"
    rm -f "${target}.tmpmerge"
  fi
}

create_configuration() {
  mkdir -p "$VHOST_NGINX_DIR" "$VHOST_APACHE_DIR" "$VHOST_FPM_DIR"

  local nginx_conf="${VHOST_NGINX_DIR}/${DOMAIN_NAME}.conf"
  local apache_conf="${VHOST_APACHE_DIR}/${DOMAIN_NAME}.conf"
  local fpm_conf="${VHOST_FPM_DIR}/${DOMAIN_NAME}.conf"

  # Per-version FPM pool config path (isolate pools per PHP profile)
  local fpm_dir=""
  if [[ "${APP_TYPE:-}" == "php" ]]; then
    fpm_dir="${VHOST_FPM_DIR}/${PHP_CONTAINER_PROFILE}"
    ( umask 022; mkdir -p "$fpm_dir" )
    chmod 0755 "$VHOST_FPM_DIR" "$fpm_dir" || true
    fpm_conf="${fpm_dir}/${DOMAIN_NAME}.conf"
  fi

  # Compute PHP upstream placeholders for templates
  if [[ "${APP_TYPE:-}" == "php" ]]; then
    if [[ "${PHP_UPSTREAM_MODE:-tcp}" == "socket" ]]; then
      local sock_fpm="${PHP_FPM_SOCK_DIR}/${DOMAIN_NAME}.sock"
      local sock_web="${WEB_FPM_SOCK_DIR}/${DOMAIN_NAME}.sock"
      PHP_FCGI_PASS="unix:${sock_web}"
      APACHE_PHP_HANDLER="SetHandler \"proxy:unix:${sock_web}|fcgi://localhost/\""

      # Render per-domain FPM pool config (used by php-fpm include dir mounting)
      if [[ -n "${PHP_FPM_TEMPLATE:-}" ]]; then
        FPM_POOL_NAME="$DOMAIN_NAME"
        FPM_SOCK_PATH="$sock_fpm"
        FPM_ERROR_LOG="/var/log/php-fpm/${DOMAIN_NAME}.error.log"
        FPM_ACCESS_LOG="/var/log/php-fpm/${DOMAIN_NAME}.access.log"
        render_template "$PHP_FPM_TEMPLATE" "$fpm_conf"
      else
        warn "Socket mode enabled but no FPM template selected; skipping pool generation for ${DOMAIN_NAME}"
        _write_empty_conf "$fpm_conf"
      fi
    else
      # TCP (current behavior)
      PHP_FCGI_PASS="${PHP_CONTAINER}:9000"
      APACHE_PHP_HANDLER="SetHandler \"proxy:fcgi://${PHP_CONTAINER}:9000\""
      _write_empty_conf "$fpm_conf"
    fi
  else
    _write_empty_conf "$fpm_conf"
  fi


  ENABLE_CLIENT_VERIFICATION="${ENABLE_CLIENT_VERIFICATION:-ssl_verify_client off;}"

  # Node is always proxied by Nginx
  if [[ "$APP_TYPE" == "node" || "$APP_TYPE" == "proxyip" ]]; then
    SERVER_TYPE="Nginx"
  fi

  # ---------------------------------------------------------------------------
  # NGINX (PHP/Node/ProxyIP) and Apache (PHP only)
  # ---------------------------------------------------------------------------
  if [[ "$SERVER_TYPE" == "Nginx" ]]; then
    # Nginx-only: php via fastcgi, node via proxy, proxyip via pinned upstream proxy
    if [[ "$ENABLE_REDIRECTION" == "y" ]]; then
      render_template "${NGINX_TEMPLATE_DIR}/redirect.nginx.conf" "$nginx_conf"
    elif [[ "$KEEP_HTTP" == "y" || "$ENABLE_HTTPS" == "n" ]]; then
      case "$APP_TYPE" in
        node)    render_template "${NGINX_TEMPLATE_DIR}/http.node.nginx.conf" "$nginx_conf" ;;
        proxyip) render_template "${NGINX_TEMPLATE_DIR}/proxy-fixedip-http.nginx.conf" "$nginx_conf" ;;
        *)       render_template "${NGINX_TEMPLATE_DIR}/http.nginx.conf" "$nginx_conf" ;;
      esac
    else
      _write_empty_conf "$nginx_conf"
    fi

    if [[ "$ENABLE_HTTPS" == "y" ]]; then
      local tmp; tmp="$(mktemp)"
      cat "$nginx_conf" >"$tmp" 2>/dev/null || true

      case "$APP_TYPE" in
        node)    render_template "${NGINX_TEMPLATE_DIR}/https.node.nginx.conf" "$nginx_conf" ;;
        proxyip) render_template "${NGINX_TEMPLATE_DIR}/proxy-fixedip-https.nginx.conf" "$nginx_conf" ;;
        *)       render_template "${NGINX_TEMPLATE_DIR}/https.nginx.conf" "$nginx_conf" ;;
      esac

      _merge_confs "$tmp" "$nginx_conf"
      rm -f "$tmp"
    fi

  elif [[ "$SERVER_TYPE" == "Apache" ]]; then
    env_set "APACHE_ACTIVE" "apache"

    if [[ "$ENABLE_REDIRECTION" == "y" ]]; then
      render_template "${NGINX_TEMPLATE_DIR}/redirect.nginx.conf" "$nginx_conf"
      _write_empty_conf "$apache_conf"
    elif [[ "$KEEP_HTTP" == "y" || "$ENABLE_HTTPS" == "n" ]]; then
      render_template "${NGINX_TEMPLATE_DIR}/proxy-http.nginx.conf" "$nginx_conf"
      render_template "${APACHE_TEMPLATE_DIR}/http.apache.conf" "$apache_conf"
    else
      _write_empty_conf "$nginx_conf"
      _write_empty_conf "$apache_conf"
    fi

    if [[ "$ENABLE_HTTPS" == "y" ]]; then
      local tmpn tmpa
      tmpn="$(mktemp)"; tmpa="$(mktemp)"
      cat "$nginx_conf"  >"$tmpn" 2>/dev/null || true
      cat "$apache_conf" >"$tmpa" 2>/dev/null || true

      render_template "${NGINX_TEMPLATE_DIR}/proxy-https.nginx.conf" "$nginx_conf"
      render_template "${APACHE_TEMPLATE_DIR}/https.apache.conf" "$apache_conf"

      _merge_confs "$tmpn" "$nginx_conf"
      _merge_confs "$tmpa" "$apache_conf"
      rm -f "$tmpn" "$tmpa"
    fi
  else
    err "Invalid server type: ${SERVER_TYPE:-}"
    return 1
  fi

  # Active profiles bookkeeping
  if [[ "$APP_TYPE" == "php" ]]; then
    env_set "ACTIVE_PHP_PROFILE" "${PHP_CONTAINER_PROFILE}"
    env_set "ACTIVE_NODE_PROFILE" ""
  elif [[ "$APP_TYPE" == "node" ]]; then
    env_set "ACTIVE_PHP_PROFILE" ""
    # ACTIVE_NODE_PROFILE already set by create_node_compose
  else
    # proxyip
    env_set "ACTIVE_PHP_PROFILE" ""
    env_set "ACTIVE_NODE_PROFILE" ""
  fi
  mkhost_sync_state


  # Add LDS metadata header (helps tools resolve container/profile/docroot without parsing)
  prepend_header_if_missing meta_header_nginx "$nginx_conf"

  GENERATED_NGINX_CONF_BASENAME="$(basename "$nginx_conf")"
  GENERATED_APACHE_CONF_BASENAME="$(basename "$apache_conf")"
}

###############################################################################
# 11) Flow + summary
###############################################################################
cleanup_vars() {
  unset -v DOMAINS DOMAIN_NAME APP_TYPE SERVER_TYPE ENABLE_HTTPS ENABLE_REDIRECTION KEEP_HTTP \
    DOC_ROOT CLIENT_MAX_BODY_SIZE CLIENT_MAX_BODY_SIZE_APACHE ENABLE_STREAMING PROXY_STREAMING_INCLUDE \
    FASTCGI_STREAMING_INCLUDE APACHE_STREAMING_INCLUDE ENABLE_CLIENT_VERIFICATION CLIENT_VERIF \
    PHP_VERSION PHP_CONTAINER_PROFILE PHP_CONTAINER PHP_APACHE_CONTAINER_PROFILE PHP_APACHE_CONTAINER \
    NODE_VERSION NODE_CMD NODE_ACCESS_LOG_FILE NODE_ERROR_LOG_FILE PHP_UPSTREAM_MODE PHP_FPM_SOCKET PHP_FPM_TEMPLATE PHP_FCGI_PASS APACHE_PHP_HANDLER FPM_POOL_NAME FPM_SOCK_PATH FPM_ERROR_LOG FPM_ACCESS_LOG NODE_PROFILE NODE_SERVICE NODE_CONTAINER NODE_COMPOSE_FILE_BASENAME NODE_COMPOSE_ACTION \
    PHP_PROFILE PHP_SERVICE PHP_CONTAINER_NAME PHP_HOSTNAME PHP_KEY PHP_COMPOSE_FILE_BASENAME PHP_COMPOSE_ACTION \
    NODE_DIR_TOKEN GENERATED_NGINX_CONF_BASENAME GENERATED_APACHE_CONF_BASENAME \
    PROXY_HOST PROXY_IP PROXY_HTTP_PORT PROXY_HTTPS_PORT PROXY_COOKIE_EXACT_INCLUDE PROXY_COOKIE_PARENT_INCLUDE PROXY_REDIRECT_INCLUDE \
    PROXY_WS_INCLUDE PROXY_SUBFILTER_INCLUDE PROXY_CSP_INCLUDE PROXY_REWRITE_YN PARENT_COOKIE_DOMAIN || true
}

choose_app_type() {
  # Non-step prompt: app type selection happens before step counting in each flow.
  say "${CYAN}  1) PHP${NC}"
  say "${CYAN}  2) NodeJs${NC}"
  say "${CYAN}  3) Proxy (Fixed IP)${NC}"
  local sel=""
  while true; do
    read -e -r -p "$(echo -e "${YELLOW}${BOLD}App type (choose 1-3)${NC}: ")" sel
    sel="$(trim "$sel")"
    [[ "$sel" =~ ^[1-3]$ ]] || { err "Enter 1, 2 or 3."; continue; }
    break
  done
  case "$sel" in
  1) APP_TYPE="php"; ok "Selected: PHP" ;;
  2) APP_TYPE="node"; ok "Selected: NodeJs" ;;
  3) APP_TYPE="proxyip"; ok "Selected: Proxy (Fixed IP)" ;;
  esac
}


choose_server_type() {
  # choose_server_type <n> <t>
  local n="$1" t="$2"
  say "${CYAN}  1) Nginx${NC}"
  say "${CYAN}  2) Apache${NC}"
  local sel
  pick_index_required "$n" "$t" "Server type (choose 1-2)" 2 sel
  case "$sel" in
  1) SERVER_TYPE="Nginx"; ok "Selected: Nginx" ;;
  2) SERVER_TYPE="Apache"; ok "Selected: Apache" ;;
  *) err "Invalid selection."; exit 1 ;;
  esac
}

choose_protocol() {
  # choose_protocol <n> <t>
  local n="$1" t="$2"
  say "${CYAN}  1) HTTP only${NC}"
  say "${CYAN}  2) HTTPS only${NC}"
  say "${CYAN}  3) Both HTTP and HTTPS${NC}"
  local sel
  pick_index_default_value "$n" "$t" "HTTP/HTTPS mode (choose 1-3)" 3 3 "Both" sel
  case "$sel" in
  1) ENABLE_HTTPS="n"; ENABLE_REDIRECTION="n"; KEEP_HTTP="y" ;;
  2) ENABLE_HTTPS="y"; ENABLE_REDIRECTION="n"; KEEP_HTTP="n" ;;
  3)
    ENABLE_HTTPS="y"
    step_yn_default "$n" "$t" "HTTP → HTTPS redirection" ENABLE_REDIRECTION "y"
    if [[ "$ENABLE_REDIRECTION" == "y" ]]; then KEEP_HTTP="n"; else KEEP_HTTP="y"; fi
    ;;
  *) err "Invalid selection."; exit 1 ;;
  esac
}

prompt_php_runtime() {
  # prompt_php_runtime <n> <t>
  local n="$1" t="$2"
  require_versions_db
  say "${CYAN}PHP versions:${NC}"

  mapfile -t active_rows < <(jq -r '.php.active[]? | "\(.version)|\(.debut)|\(.eol)"' "$RUNTIME_VERSIONS_DB")
  mapfile -t dep_rows    < <(jq -r '.php.deprecated[]? | "\(.version)|\(.eol)"' "$RUNTIME_VERSIONS_DB")

  local idx_map_type=() idx_map_value=()
  local i=0

  printf "  %2d) %-7s %s\n" 0 "Custom" "Version"
  idx_map_type[0]="custom"; idx_map_value[0]=""

  say "${CYAN}Active (supported):${NC}"
  for r in "${active_rows[@]}"; do
    [[ "$i" -ge "$MAX_VERSIONS" ]] && break
    i=$((i+1))
    IFS='|' read -r v debut eol <<<"$r"
    printf "  %2d) %-7s %s\n" "$i" "$v" "$(fmt_range "$debut" "$eol")"
    idx_map_type[$i]="php"; idx_map_value[$i]="$v"
  done

  say "${CYAN}Deprecated (EOL):${NC}"
  for r in "${dep_rows[@]}"; do
    [[ "$i" -ge "$MAX_VERSIONS" ]] && break
    i=$((i+1))
    IFS='|' read -r v eol <<<"$r"
    printf "  %2d) %-7s %s\n" "$i" "$v" "$(fmt_eol_tilde "$eol")"
    idx_map_type[$i]="php"; idx_map_value[$i]="$v"
  done

  local printed_max="$i"
  local sel def_idx=1 def_disp="${idx_map_value[1]:-1}"
  pick_index_default_value "$n" "$t" "Runtime (select 0-${printed_max})" "$printed_max" "$def_idx" "$def_disp" sel

  if [[ "${idx_map_type[$sel]}" == "custom" ]]; then
    local custom=""
    while true; do
      step_ask_text_required "$n" "$t" "PHP version" custom "Major.Minor (e.g., 8.4)"
      if php_is_valid_custom "$custom"; then PHP_VERSION="$custom"; break; fi
      err "Invalid / unknown PHP version."
    done
  else
    PHP_VERSION="${idx_map_value[$sel]:-}"
    [[ -n "$PHP_VERSION" ]] || { err "Invalid selection."; exit 1; }
  fi

  PHP_CONTAINER_PROFILE="php${PHP_VERSION//./}"
  PHP_CONTAINER="PHP_${PHP_VERSION}"
  PHP_APACHE_CONTAINER="PHP_${PHP_VERSION}_APACHE"
  ok "Selected PHP version: $PHP_VERSION"
}

prompt_node_runtime() {
  # prompt_node_runtime <n> <t>
  local n="$1" t="$2"
  require_versions_db

  local current_major lts_major
  current_major="$(jq -r '.node.tags.current // ""' "$RUNTIME_VERSIONS_DB")"
  lts_major="$(jq -r '.node.tags.lts // ""' "$RUNTIME_VERSIONS_DB")"

  say "${CYAN}Node versions:${NC}"

  mapfile -t active_rows < <(jq -r '.node.active[]? | "\(.version)|\(.debut)|\(.eol)|\(.lts)"' "$RUNTIME_VERSIONS_DB")
  mapfile -t dep_rows    < <(jq -r '.node.deprecated[]? | "\(.version)|\(.eol)"' "$RUNTIME_VERSIONS_DB")

  local idx_map_type=() idx_map_value=()
  local i=0

  printf "  %2d) %-7s %s\n" 0 "Custom" "Version"
  idx_map_type[0]="custom"; idx_map_value[0]=""

  i=1; printf "  %2d) %-7s %s\n" "$i" "CURRENT" "(v${current_major})"
  idx_map_type[$i]="tag"; idx_map_value[$i]="current"

  i=2; printf "  %2d) %-7s %s\n" "$i" "LTS" "(v${lts_major})"
  idx_map_type[$i]="tag"; idx_map_value[$i]="lts"

  local slots_left=$((MAX_VERSIONS - 3))

  say "${CYAN}Active (supported):${NC}"
  for r in "${active_rows[@]}"; do
    [[ "$slots_left" -le 0 ]] && break
    i=$((i+1)); slots_left=$((slots_left-1))
    IFS='|' read -r v debut eol lts <<<"$r"
    if [[ "$lts" == "true" ]]; then
      printf "  %2d) %-7s %s LTS\n" "$i" "v${v}" "$(fmt_range "$debut" "$eol")"
    else
      printf "  %2d) %-7s %s\n" "$i" "v${v}" "$(fmt_range "$debut" "$eol")"
    fi
    idx_map_type[$i]="node"; idx_map_value[$i]="$v"
  done

  say "${CYAN}Deprecated (EOL):${NC}"
  for r in "${dep_rows[@]}"; do
    [[ "$slots_left" -le 0 ]] && break
    i=$((i+1)); slots_left=$((slots_left-1))
    IFS='|' read -r v eol <<<"$r"
    printf "  %2d) %-7s %s\n" "$i" "v${v}" "$(fmt_eol_tilde "$eol")"
    idx_map_type[$i]="node"; idx_map_value[$i]="$v"
  done

  local printed_max="$i"
  local sel def_idx=2 def_disp="LTS"
  pick_index_default_value "$n" "$t" "Runtime (select 0-${printed_max})" "$printed_max" "$def_idx" "$def_disp" sel

  case "${idx_map_type[$sel]:-}" in
  node) NODE_VERSION="${idx_map_value[$sel]}" ;;
  tag)  NODE_VERSION="${idx_map_value[$sel]}" ;;
  custom)
    local custom=""
    while true; do
      step_ask_text_required "$n" "$t" "Node major" custom "e.g., 24"
      if node_is_valid_custom "$custom"; then NODE_VERSION="$custom"; break; fi
      err "Invalid / unknown Node major."
    done
    ;;
  *) err "Invalid selection."; exit 1 ;;
  esac

  ok "Selected Node version: $NODE_VERSION"
}

choose_doc_root() {
  # choose_doc_root <n> <t>
  local n="$1" t="$2"
  local opts=()
  opts+=("<Custom Path>")
  while IFS= read -r -d '' v; do
    v="$(trim "$v")"
    [[ -n "$v" ]] && opts+=("$v")
  done < <(collect_docroot_options || true)

  say "${CYAN}Doc root suggestions from ${APP_SCAN_DIR}:${NC}"
  print_two_column_menu opts 0

  local max=$(( ${#opts[@]} - 1 ))
  local sel
  pick_index_required "$n" "$t" "Doc root (choose 0-${max})" "$max" sel

  if [[ "$sel" == "0" ]]; then
    step_ask_text_required "$n" "$t" "Doc root" DOC_ROOT "e.g., /site/public"
    DOC_ROOT="$(normalize_rel_path "$DOC_ROOT")"
  else
    DOC_ROOT="$(normalize_rel_path "${opts[$sel]}")"
    ok "Selected Doc root: $DOC_ROOT"
  fi
}

prompt_php_fpm_socket_mode() {
  # prompt_php_fpm_socket_mode <step> <t>
  local step="$1" t="$2"
  PHP_UPSTREAM_MODE="tcp"
  PHP_FPM_TEMPLATE=""
  step_yn_default "$step" "$t" "Use a dedicated PHP-FPM unix socket for this domain" PHP_FPM_SOCKET "n" "isolates per-domain logs"
  if [[ "${PHP_FPM_SOCKET:-n}" == "y" ]]; then
    PHP_UPSTREAM_MODE="socket"

    # Template selection (only if multiple templates exist)
    local -a tpls=()
    if [[ -d "$FPM_TEMPLATE_DIR" ]]; then
      while IFS= read -r -d '' f; do tpls+=("$f"); done < <(find "$FPM_TEMPLATE_DIR" -maxdepth 1 -type f \( -name '*.conf.tpl' -o -name '*.tpl' \) -print0 | sort -z)
    fi

    if ((${#tpls[@]} == 0)); then
      warn "No FPM templates found in: $FPM_TEMPLATE_DIR (socket mode will fail unless templates are added)"
      PHP_FPM_TEMPLATE=""
      return 0
    fi

    if ((${#tpls[@]} == 1)); then
      PHP_FPM_TEMPLATE="${tpls[0]}"
      ok "Using FPM template: $(basename "$PHP_FPM_TEMPLATE")"
      return 0
    fi

    say "${DIM}Available FPM templates:${NC}"
    local i
    for ((i=0; i<${#tpls[@]}; i++)); do
      say "  $((i+1))) $(basename "${tpls[$i]}")"
    done

    local pick=""
    while true; do
      read -e -r -p "$(echo -e "${YELLOW}Select template${NC} ${DIM}(1-${#tpls[@]})${NC}: ")" pick
      pick="$(trim "$pick")"
      [[ "$pick" =~ ^[0-9]+$ ]] || { warn "Enter a number."; continue; }
      ((pick>=1 && pick<=${#tpls[@]})) || { warn "Out of range."; continue; }
      PHP_FPM_TEMPLATE="${tpls[$((pick-1))]}"
      ok "Selected FPM template: $(basename "$PHP_FPM_TEMPLATE")"
      break
    done
  fi
}

parse_domains_step1() {
  local raw="$1"
  raw="${raw//,/ }"
  raw="$(trim "$raw")"
  [[ -n "$raw" ]] || return 1

  local -a tmp=()
  local d
  for d in $raw; do
    d="$(trim "$d")"
    [[ -n "$d" ]] || continue
    validate_domain "$d" || return 1
    tmp+=("$d")
  done
  ((${#tmp[@]} > 0)) || return 1

  local seen="|"
  local -a out=()
  for d in "${tmp[@]}"; do
    if [[ "$seen" != *"|$d|"* ]]; then
      seen="${seen}${d}|"
      out+=("$d")
    fi
  done

  DOMAINS=("${out[@]}")
  return 0
}

print_summary() {
  echo

  local key="${DIM}"
  local head="${CYAN}${BOLD}"
  local line="${DIM}────────────────────────────────────────────────────────${NC}"

  _chip() { # _chip <y|n> <onText> <offText>
    if [[ "${1:-n}" == "y" ]]; then
      echo -e "${GREEN}${BOLD}${2:-Enabled}${NC}"
    else
      echo -e "${YELLOW}${BOLD}${3:-Disabled}${NC}"
    fi
  }

  local proto="HTTP only"
  if [[ "${ENABLE_HTTPS:-n}" == "y" && "${KEEP_HTTP:-n}" == "y" ]]; then
    proto="Both (HTTP + HTTPS)"
  elif [[ "${ENABLE_HTTPS:-n}" == "y" && "${KEEP_HTTP:-n}" == "n" ]]; then
    if [[ "${ENABLE_REDIRECTION:-n}" == "y" ]]; then
      proto="Both (Redirect HTTP → HTTPS)"
    else
      proto="HTTPS only"
    fi
  fi

  say "${head}Summary${NC}"
  say "${line}"

  say "${key}Domains:${NC}              ${BOLD}${CYAN}${DOMAINS[*]}${NC}"
  case "${APP_TYPE:-}" in
    php)     say "${key}App type:${NC}             ${BOLD}PHP${NC}" ;;
    node)    say "${key}App type:${NC}             ${BOLD}NODE${NC}" ;;
    proxyip) say "${key}App type:${NC}             ${BOLD}PROXY (FIXED IP)${NC}" ;;
    *)       say "${key}App type:${NC}             ${BOLD}${APP_TYPE^^}${NC}" ;;
  esac

  if [[ "$APP_TYPE" == "php" ]]; then
    say "${key}PHP version:${NC}          ${BOLD}${PHP_VERSION}${NC} ${DIM}(profile: ${PHP_CONTAINER_PROFILE})${NC}"
    say "${key}Server type:${NC}          ${BOLD}${SERVER_TYPE}${NC}"
    say "${key}Doc root:${NC}             ${BOLD}${DOC_ROOT}${NC}"
  # PHP-FPM mode (kept concise in summary)
    if [[ "${PHP_UPSTREAM_MODE:-tcp}" == "socket" ]]; then
      say "${key}PHP-FPM mode:${NC}         ${BOLD}Unix socket${NC}"
      if [[ -n "${PHP_FPM_TEMPLATE:-}" ]]; then
        say "${key}FPM template:${NC}         ${BOLD}$(basename "${PHP_FPM_TEMPLATE}")${NC}"
      fi
    else
      say "${key}PHP-FPM mode:${NC}         ${BOLD}TCP (${PHP_CONTAINER}:9000)${NC}"
    fi

  elif [[ "$APP_TYPE" == "node" ]]; then
    say "${key}Node version:${NC}         ${BOLD}${NODE_VERSION}${NC}"
    say "${key}Server type:${NC}          ${BOLD}Nginx${NC}"
    say "${key}Doc root:${NC}             ${BOLD}${DOC_ROOT}${NC}"
  elif [[ "$APP_TYPE" == "proxyip" ]]; then
    say "${key}Upstream host:${NC}        ${BOLD}${PROXY_HOST}${NC}"
    say "${key}Upstream IP:${NC}          ${BOLD}${PROXY_IP}${NC}"
    say "${key}Server type:${NC}          ${BOLD}Nginx${NC}"
    say "${key}Upstream ports:${NC}       ${BOLD}http:${PROXY_HTTP_PORT:-80} https:${PROXY_HTTPS_PORT:-443}${NC}"
  fi

  say "${key}Protocol mode:${NC}        ${BOLD}${proto}${NC}"
  say "${key}Client body size:${NC}     ${BOLD}${CLIENT_MAX_BODY_SIZE}${NC}"
  say "${key}Streaming/SSE:${NC}        $(_chip "${ENABLE_STREAMING:-n}" "Enabled" "Disabled")"

  if [[ "$APP_TYPE" == "proxyip" ]]; then
    say "${key}WebSockets:${NC}           $(_chip "${PROXY_WS_ENABLED:-n}" "Enabled" "Disabled")"
    say "${key}Cookies/Redirects:${NC}    $(_chip "${PROXY_REWRITE_YN:-n}" "Rewrite Enabled" "Rewrite Disabled")"
  fi

  say "${key}mTLS:${NC}                 $(_chip "${CLIENT_VERIF:-n}" "Enabled" "Disabled")"

  echo
}

run_certify_if_available() {
  command -v certify >/dev/null 2>&1 || return 0

  if certify >/dev/null; then
    say "${MAGENTA}${BOLD}Certificates:${NC} ${BOLD}Generated/Updated${NC}"
  else
    warn "! Certificates: Generation failed (showing output):"
    certify || true
  fi
}

finalize_body_size() {
  # finalize_body_size <step> <t>
  local step_body="$1" t="$2"
  local _MB=""
  step_ask_text_default "$step_body" "$t" "Client body size (MB)" _MB "10"
  while [[ ! "$_MB" =~ ^[0-9]+$ ]]; do
    err "Invalid number."
    step_ask_text_default "$step_body" "$t" "Client body size (MB)" _MB "10"
  done
  CLIENT_MAX_BODY_SIZE_APACHE=$((_MB * 1000000))
  CLIENT_MAX_BODY_SIZE="${_MB}M"
  unset -v _MB || true
}

finalize_streaming() {
  # finalize_streaming <step> <t>
  local step_stream="$1" t="$2"
  PROXY_STREAMING_INCLUDE=""
  FASTCGI_STREAMING_INCLUDE=""
  APACHE_STREAMING_INCLUDE=""
  step_yn_default "$step_stream" "$t" "Streaming/SSE mode" ENABLE_STREAMING "n"
  if [[ "$ENABLE_STREAMING" == "y" ]]; then
    PROXY_STREAMING_INCLUDE="include /etc/nginx/proxy_streaming;"
    FASTCGI_STREAMING_INCLUDE="include /etc/nginx/fastcgi_streaming;"
    APACHE_STREAMING_INCLUDE=$'  # Streaming/SSE tuning\n  ProxyTimeout 3600\n  Timeout 3600\n  Header set Cache-Control "no-cache"\n  Header set X-Accel-Buffering "no"\n'
  fi
}

prompt_mtls() {
  # prompt_mtls <step> <t>
  local step_mtls="$1" t="$2"
  CLIENT_VERIF="n"
  if [[ "${ENABLE_HTTPS:-n}" != "y" ]]; then
    ENABLE_CLIENT_VERIFICATION="ssl_verify_client off;"
    ok "Client verification disabled (HTTPS not enabled)."
    return 0
  fi
  step_yn_default "$step_mtls" "$t" "Client certificate verification (mTLS)" CLIENT_VERIF "n"
  if [[ "$CLIENT_VERIF" == "y" ]]; then
    ENABLE_CLIENT_VERIFICATION="ssl_verify_client on;"
    warn "Client verification enabled. Ensure client certs are configured."
  else
    ENABLE_CLIENT_VERIFICATION="ssl_verify_client off;"
  fi
}

generate_all_domains() {
  if [[ "$APP_TYPE" == "php" ]]; then
    create_php_compose
    ok "  ✔ PHP compose ${PHP_COMPOSE_ACTION}"
    say "    ${DIM}file:${NC} ${BOLD}${PHP_COMPOSE_FILE_BASENAME}${NC}  ${DIM}profile:${NC} ${BOLD}${PHP_CONTAINER_PROFILE}${NC}"
  fi

  local d
  for d in "${DOMAINS[@]}"; do
    DOMAIN_NAME="$d"

    say "${MAGENTA}${BOLD}Generating:${NC} ${BOLD}${DOMAIN_NAME}${NC}"

    if [[ "$APP_TYPE" == "node" ]]; then
      create_node_compose
      ok "  ✔ Node compose ${NODE_COMPOSE_ACTION}"
      say "    ${DIM}service:${NC} ${BOLD}${NODE_SERVICE}${NC}  ${DIM}profile:${NC} ${BOLD}${NODE_PROFILE}${NC}  ${DIM}port:${NC} ${BOLD}${NODE_PORT}${NC}"
    fi

    create_configuration

    ok "  ✔ Configuration Saved"
    echo
  done

  run_certify_if_available
}

###############################################################################
# 12) ProxyIP helpers
###############################################################################
prompt_proxy_host() {
  # prompt_proxy_host <step> <t>
  local n="$1" t="$2"
  local h=""
  while true; do
    step_ask_text_required "$n" "$t" "Upstream host" h "e.g., me.example.com or example.com"
    h="$(trim "$h")"
    # allow broad hostnames; just block spaces/slashes
    if [[ "$h" =~ ^[A-Za-z0-9._-]+$ ]] && [[ "$h" == *.* ]]; then
      PROXY_HOST="$h"
      return 0
    fi
    err "Invalid host."
  done
}

prompt_proxy_ip() {
  # prompt_proxy_ip <step> <t>
  local n="$1" t="$2"
  local ip=""
  while true; do
    step_ask_text_required "$n" "$t" "Upstream IP" ip "IPv4/IPv6 (e.g., 192.40.2.67)"
    ip="$(trim "$ip")"
    if validate_ip "$ip"; then
      PROXY_IP="$ip"
      return 0
    fi
    err "Invalid IP."
  done
}

prompt_proxy_ports() {
  # prompt_proxy_ports <step> <t>
  local n="$1" t="$2"
  local raw="" def="" p1="" p2="" extra=""

  # Determine what we need based on selected protocol + redirection
  # - HTTP only              => ask one port (http)
  # - HTTPS only             => ask one port (https)
  # - Both + redirection     => ask one port (https)
  # - Both + no redirection  => ask two ports (http,https) as CSV
  local need="both"
  if [[ "${ENABLE_HTTPS:-n}" != "y" ]]; then
    need="http"
  elif [[ "${KEEP_HTTP:-n}" != "y" ]]; then
    need="https"
  elif [[ "${ENABLE_REDIRECTION:-n}" == "y" ]]; then
    need="https"
  else
    need="both"
  fi

  case "$need" in
    http)
      def="80"
      while true; do
        step_ask_text_default "$n" "$t" "Upstream port" raw "$def" "http port (default 80)"
        raw="$(trim "$raw")"
        validate_port "$raw" || { err "Invalid port."; continue; }
        PROXY_HTTP_PORT="$raw"
        PROXY_HTTPS_PORT="${PROXY_HTTPS_PORT:-443}"
        return 0
      done
      ;;
    https)
      def="443"
      while true; do
        step_ask_text_default "$n" "$t" "Upstream port" raw "$def" "https port (default 443)"
        raw="$(trim "$raw")"
        validate_port "$raw" || { err "Invalid port."; continue; }
        PROXY_HTTPS_PORT="$raw"
        PROXY_HTTP_PORT="${PROXY_HTTP_PORT:-80}"
        return 0
      done
      ;;
    both)
      def="80,443"
      while true; do
        step_ask_text_default "$n" "$t" "Upstream ports" raw "$def" "http,https (e.g., 8080,8443)"
        raw="$(trim "$raw")"
        raw="${raw// /}"
        IFS=',' read -r p1 p2 extra <<<"$raw"
        [[ -n "${p1:-}" && -n "${p2:-}" && -z "${extra:-}" ]] || { err "Enter two ports as CSV: http,https"; continue; }
        validate_port "$p1" || { err "Invalid http port."; continue; }
        validate_port "$p2" || { err "Invalid https port."; continue; }
        PROXY_HTTP_PORT="$p1"
        PROXY_HTTPS_PORT="$p2"
        return 0
      done
      ;;
    *)
      err "Internal error: port need mode invalid."
      return 1
      ;;
  esac
}

proxyip_set_feature_includes() {
  # Called after protocol is chosen and after optional prompts
  PROXY_COOKIE_EXACT_INCLUDE=""
  PROXY_COOKIE_PARENT_INCLUDE=""
  PROXY_REDIRECT_INCLUDE=""
  PROXY_WS_INCLUDE=""
  PROXY_SUBFILTER_INCLUDE=""
  PROXY_CSP_INCLUDE=""

  if [[ "${PROXY_WS_ENABLED:-n}" == "y" ]]; then
    PROXY_WS_INCLUDE="include /etc/nginx/proxy_websocket;"
  fi

  # Inline sub_filter rules (proxy-params.sh doesn't generate proxy_sub_filter include)
  if [[ "${PROXY_SUBFILTER_ENABLED:-n}" == "y" ]]; then
    PROXY_SUBFILTER_INCLUDE=$'sub_filter_once off;
sub_filter_types text/html text/css application/javascript;
'
    PROXY_SUBFILTER_INCLUDE+=$'sub_filter "https://'"${PROXY_HOST}"'" "$scheme://$host";
'
    PROXY_SUBFILTER_INCLUDE+=$'sub_filter "http://'"${PROXY_HOST}"'" "$scheme://$host";
'
  fi

  if [[ "${PROXY_CSP_ENABLED:-n}" == "y" ]]; then
    PROXY_CSP_INCLUDE="include /etc/nginx/proxy_csp_relax;"
  fi

  # Templates already contain: proxy_redirect off;
  # Only add explicit rewrite rule when enabled (keep the browser on {{SERVER_NAME}})
  if [[ "${PROXY_REWRITE_YN:-n}" == "y" ]]; then
    # cookie rewrite (keep single-line to avoid literal "\n" in output)
    PROXY_COOKIE_EXACT_INCLUDE="proxy_cookie_domain ${PROXY_HOST} ${DOMAIN_NAME}; proxy_cookie_path / /;"

    if [[ -n "${PARENT_COOKIE_DOMAIN:-}" ]]; then
      PROXY_COOKIE_PARENT_INCLUDE="proxy_cookie_domain ${PARENT_COOKIE_DOMAIN} ${DOMAIN_NAME};"
    fi

    # redirect rewrite (avoid expanding $scheme/$host under set -u)
    local rehost="${PROXY_HOST//./\.}"
    PROXY_REDIRECT_INCLUDE="proxy_redirect ~^https?://${rehost}(:[0-9]+)?(/.*)?$ "'$scheme://$host$2;'
  fi
}

###############################################################################
# 13) Config flows
###############################################################################
configure_php() {
  local T=10

  while true; do
    local raw=""
    step_ask_text_required 1 "$T" "Domain" raw "space/comma separated (e.g., a.localhost, b.localhost)"
    if parse_domains_step1 "$raw"; then break; fi
    warn "Invalid domain(s). Try again."
  done

  prompt_php_runtime 2 "$T"
  choose_server_type 3 "$T"
  choose_protocol 4 "$T"
  choose_doc_root 5 "$T"
  prompt_php_fpm_socket_mode 6 "$T"

  finalize_body_size 8 "$T"
  finalize_streaming 9 "$T"
  prompt_mtls 10 "$T"

  print_summary
  local PROCEED="y"
  ask_yn_default "Proceed with generation" PROCEED "y"
  [[ "$PROCEED" == "y" ]] || { warn "Cancelled."; return 0; }
  echo

  generate_all_domains
}

configure_node() {
  local T=9

  while true; do
    local raw=""
    step_ask_text_required 1 "$T" "Domain" raw "space/comma separated (e.g., a.localhost, b.localhost)"
    if parse_domains_step1 "$raw"; then break; fi
    warn "Invalid domain(s). Try again."
  done

  prompt_node_runtime 2 "$T"

  SERVER_TYPE="Nginx"
  step_yn_default 3 "$T" "Custom Node start command" _NODE_CMD_YN "n"
  if [[ "$_NODE_CMD_YN" == "y" ]]; then
    step_ask_text_required 3 "$T" "Node command" NODE_CMD "npm run dev / npm start / node server.js"
    NODE_CMD="$(trim "$NODE_CMD")"
  else
    NODE_CMD=""
  fi
  unset -v _NODE_CMD_YN || true

  choose_protocol 4 "$T"
  choose_doc_root 5 "$T"

  finalize_body_size 7 "$T"
  finalize_streaming 8 "$T"
  prompt_mtls 9 "$T"

  print_summary
  local PROCEED="y"
  ask_yn_default "Proceed with generation" PROCEED "y"
  [[ "$PROCEED" == "y" ]] || { warn "Cancelled."; return 0; }
  echo

  generate_all_domains
}

configure_proxyip() {
  local T=13

  # 2) Domain(s)
  while true; do
    local raw=""
    step_ask_text_required 1 "$T" "Domain" raw "space/comma separated (e.g., xyz.localhost)"
    if parse_domains_step1 "$raw"; then break; fi
    warn "Invalid domain(s). Try again."
  done

  # 3) Upstream host
  prompt_proxy_host 2 "$T"

  # 4) Upstream IP
  prompt_proxy_ip 3 "$T"

  # 5) Protocol
  choose_protocol 4 "$T"

  # 5) Upstream port(s)
  prompt_proxy_ports 5 "$T"


  # 6) Body size
  finalize_body_size 6 "$T"

  # 7) Streaming
  finalize_streaming 7 "$T"

  # 8) WebSockets
  PROXY_WS_ENABLED="n"
  step_yn_default 8 "$T" "WebSockets/HMR support" PROXY_WS_ENABLED "n"

  # 9) Rewrite/cookies/redirects + last resort tweaks + mTLS
  PROXY_REWRITE_YN="y"
  step_yn_default 9 "$T" "Rewrite cookies + redirects for upstream host" PROXY_REWRITE_YN "y"

  PARENT_COOKIE_DOMAIN=""
  if [[ "$PROXY_REWRITE_YN" == "y" ]]; then
    step_ask_text_default 10 "$T" "Parent cookie domain (optional)" PARENT_COOKIE_DOMAIN "" "e.g., .sslcommerz.com"
    PARENT_COOKIE_DOMAIN="$(trim "$PARENT_COOKIE_DOMAIN")"
    if [[ -n "$PARENT_COOKIE_DOMAIN" && "${PARENT_COOKIE_DOMAIN:0:1}" != "." ]]; then
      PARENT_COOKIE_DOMAIN=".${PARENT_COOKIE_DOMAIN}"
    fi
  fi

  PROXY_SUBFILTER_ENABLED="n"
  step_yn_default 11 "$T" "Enable sub_filter URL rewrite (last resort)" PROXY_SUBFILTER_ENABLED "n"

  PROXY_CSP_ENABLED="n"
  step_yn_default 12 "$T" "Relax Content-Security-Policy (last resort)" PROXY_CSP_ENABLED "n"

  # mTLS last (still step 9)
  prompt_mtls 13 "$T"

  # ProxyIP doesn't use docroot in templates
  DOC_ROOT="/"

  # Summary + confirm
  print_summary
  local PROCEED="y"
  ask_yn_default "Proceed with generation" PROCEED "y"
  [[ "$PROCEED" == "y" ]] || { warn "Cancelled."; return 0; }
  echo

  # Generate with proxyip includes computed per-domain (needs DOMAIN_NAME)
  local d
  for d in "${DOMAINS[@]}"; do
    DOMAIN_NAME="$d"
    proxyip_set_feature_includes
    say "${MAGENTA}${BOLD}Generating:${NC} ${BOLD}${DOMAIN_NAME}${NC}"
    create_configuration
    ok "  ✔ Configuration Saved"
    echo
  done

  run_certify_if_available
}

configure_server() {
  require_versions_db
  preflight_templates

  choose_app_type

  case "$APP_TYPE" in
    php)     configure_php ;;
    node)    configure_node ;;
    proxyip) configure_proxyip ;;
    *) err "Invalid app type: ${APP_TYPE:-}"; exit 1 ;;
  esac
}

###############################################################################
# 14) CLI flags
###############################################################################
case "${1:-}" in
--RESET)
  env_set "APACHE_ACTIVE" ""
  env_set "ACTIVE_PHP_PROFILE" ""
  env_set "ACTIVE_NODE_PROFILE" ""
  mkhost_sync_state
  ;;
--ACTIVE_PHP_PROFILE)  env_get "ACTIVE_PHP_PROFILE" ;;
--ACTIVE_NODE_PROFILE) env_get "ACTIVE_NODE_PROFILE" ;;
--APACHE_ACTIVE)       env_get "APACHE_ACTIVE" ;;
--JSON|--STATE_JSON)   mkhost_get_state_json ;;
*)
  configure_server
  cleanup_vars
  ;;
esac
