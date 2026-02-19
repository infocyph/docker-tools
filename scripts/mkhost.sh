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

readonly TEMPLATE_DIR="${TEMPLATE_DIR:-/etc/http-templates}"
readonly VHOST_NGINX_DIR="${VHOST_NGINX_DIR:-/etc/share/vhosts/nginx}"
readonly VHOST_APACHE_DIR="${VHOST_APACHE_DIR:-/etc/share/vhosts/apache}"
readonly VHOST_NODE_DIR="${VHOST_NODE_DIR:-/etc/share/vhosts/node}"

readonly ENV_STORE="${ENV_STORE:-/etc/environment}"

readonly NODE_PORT="${NODE_PORT:-3000}"
readonly COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-LocalDevStack}"

readonly APP_SCAN_DIR="${APP_SCAN_DIR:-/app}"   # for doc-root suggestions

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
  redirect.nginx.conf
  http.nginx.conf https.nginx.conf
  http.node.nginx.conf https.node.nginx.conf
  proxy-http.nginx.conf proxy-https.nginx.conf
  http.apache.conf https.apache.conf
  proxy-fixedip-http.nginx.conf
  proxy-fixedip-https.nginx.conf
)

preflight_templates() {
  local f
  for f in "${required_tpls[@]}"; do
    [[ -r "$TEMPLATE_DIR/$f" ]] || { err "Error: missing template: $f"; exit 1; }
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
env_set() {
  local key="$1" value="$2"
  touch "$ENV_STORE"
  if grep -qE "^${key}=" "$ENV_STORE"; then
    sed -i "s|^${key}=.*|${key}=${value}|" "$ENV_STORE"
  else
    echo "${key}=${value}" >>"$ENV_STORE"
  fi
}
env_get() { grep -E "^$1=" "$ENV_STORE" 2>/dev/null | cut -d'=' -f2- || true; }

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
  local out=()

  [[ -d "$base/public" ]] && out+=("/public")

  if [[ -d "$base" ]]; then
    while IFS= read -r -d '' d; do
      local name; name="$(basename "$d")"
      [[ "$name" == .* ]] && continue
      out+=("/$name")
      [[ -d "$d/public" ]] && out+=("/$name/public")
    done < <(find "$base" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null || true)
  fi

  local seen="|"
  local opt
  for opt in "${out[@]}"; do
    if [[ "$seen" != *"|$opt|"* ]]; then
      seen="${seen}${opt}|"
      printf '%s\0' "$opt"
    fi
  done
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
  local tpl="$1" out="$2"
  [[ -r "$tpl" ]] || { err "Template not readable: $(basename "$tpl")"; exit 1; }

  local tmp; tmp="$(mktemp)"
  sed \
    -e "s|{{SERVER_NAME}}|$(sed_escape_repl "${DOMAIN_NAME:-}")|g" \
    -e "s|{{DOC_ROOT}}|$(sed_escape_repl "${DOC_ROOT:-}")|g" \
    -e "s|{{CLIENT_MAX_BODY_SIZE}}|$(sed_escape_repl "${CLIENT_MAX_BODY_SIZE:-10M}")|g" \
    -e "s|{{CLIENT_MAX_BODY_SIZE_APACHE}}|$(sed_escape_repl "${CLIENT_MAX_BODY_SIZE_APACHE:-}")|g" \
    -e "s|{{PROXY_STREAMING_INCLUDE}}|$(sed_escape_repl "${PROXY_STREAMING_INCLUDE:-}")|g" \
    -e "s|{{FASTCGI_STREAMING_INCLUDE}}|$(sed_escape_repl "${FASTCGI_STREAMING_INCLUDE:-}")|g" \
    -e "s|{{APACHE_STREAMING_INCLUDE}}|$(sed_escape_repl "${APACHE_STREAMING_INCLUDE:-}")|g" \
    -e "s|{{PHP_APACHE_CONTAINER}}|$(sed_escape_repl "${PHP_APACHE_CONTAINER:-}")|g" \
    -e "s|{{APACHE_CONTAINER}}|$(sed_escape_repl "${APACHE_CONTAINER:-APACHE}")|g" \
    -e "s|{{PHP_CONTAINER}}|$(sed_escape_repl "${PHP_CONTAINER:-}")|g" \
    -e "s|{{CLIENT_VERIFICATION}}|$(sed_escape_repl "${ENABLE_CLIENT_VERIFICATION:-ssl_verify_client off;}")|g" \
    -e "s|{{NODE_CONTAINER}}|$(sed_escape_repl "${NODE_CONTAINER:-}")|g" \
    -e "s|{{NODE_PORT}}|$(sed_escape_repl "${NODE_PORT}")|g" \
    -e "s|{{PROXY_IP}}|$(sed_escape_repl "${PROXY_IP:-}")|g" \
-e "s|{{PROXY_HTTP_PORT}}|$(sed_escape_repl "${PROXY_HTTP_PORT:-80}")|g" \
-e "s|{{PROXY_HTTPS_PORT}}|$(sed_escape_repl "${PROXY_HTTPS_PORT:-443}")|g" \
    -e "s|{{PROXY_HOST}}|$(sed_escape_repl "${PROXY_HOST:-}")|g" \
    -e "s|{{PROXY_COOKIE_EXACT_INCLUDE}}|$(sed_escape_repl "${PROXY_COOKIE_EXACT_INCLUDE:-}")|g" \
    -e "s|{{PROXY_COOKIE_PARENT_INCLUDE}}|$(sed_escape_repl "${PROXY_COOKIE_PARENT_INCLUDE:-}")|g" \
    -e "s|{{PROXY_REDIRECT_INCLUDE}}|$(sed_escape_repl "${PROXY_REDIRECT_INCLUDE:-}")|g" \
    -e "s|{{PROXY_WS_INCLUDE}}|$(sed_escape_repl "${PROXY_WS_INCLUDE:-}")|g" \
    -e "s|{{PROXY_SUBFILTER_INCLUDE}}|$(sed_escape_repl "${PROXY_SUBFILTER_INCLUDE:-}")|g" \
    -e "s|{{PROXY_CSP_INCLUDE}}|$(sed_escape_repl "${PROXY_CSP_INCLUDE:-}")|g" \
    "$tpl" >"$tmp"

  install -m 0644 "$tmp" "$out"
  rm -f "$tmp"
}

###############################################################################
# 9) Node compose generator
###############################################################################
create_node_compose() {
  mkdir -p "$VHOST_NODE_DIR"

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

  local out="${VHOST_NODE_DIR}/${token}.yaml"
  local tmp; tmp="$(mktemp)"

  local node_cmd_line esc
  if [[ -n "${NODE_CMD:-}" ]]; then
    esc="${NODE_CMD//$'\r'/}"
    esc="${esc//$'\n'/ }"
    esc="${esc//\\/\\\\}"
    esc="${esc//\"/\\\"}"
    node_cmd_line='- NODE_CMD=${NODE_CMD:-"'"${esc}"'"}'
  else
    node_cmd_line='- NODE_CMD=${NODE_CMD:-}'
  fi

  cat >"$tmp" <<YAML
name: ${COMPOSE_PROJECT_NAME}

services:
  ${svc}:
    container_name: ${cname}
    hostname: ${svc}
    build:
      context: docker/dockerfiles
      dockerfile: node.Dockerfile
      args:
        UID: \${UID:-1000}
        GID: \${GID:-1000}
        USERNAME: \${USER}
        NODE_VERSION: ${NODE_VERSION}
        LINUX_PKG: \${LINUX_PKG:-}
        LINUX_PKG_VERSIONED: \${LINUX_PKG_${node_key}:-}
        NODE_GLOBAL: \${NODE_GLOBAL:-}
        NODE_GLOBAL_VERSIONED: \${NODE_GLOBAL_${node_key}:-}
    environment:
      - TZ=\${TZ:-}
      - PORT=${NODE_PORT}
      - HOST=0.0.0.0
      ${node_cmd_line}
      - NPM_AUDIT=\${NPM_AUDIT:-0}
      - NPM_FUND=\${NPM_FUND:-0}
    env_file:
      - .env
    networks:
      frontend: {}
      backend: {}
      datastore: {}
    volumes:
      - "\${PROJECT_DIR:-./../application}${DOC_ROOT}:/app"
      - "./configuration/ssh:/home/\${USER}/.ssh:ro"
      - ./configuration/rootCA:/etc/share/rootCA:ro
      - "\${HOME}/.gitconfig:/home/\${USER}/.gitconfig:ro"
    depends_on:
      - server-tools
    healthcheck:
      test: ["CMD-SHELL", "node -e \"const net=require('net');const h=process.env.HOST||'127.0.0.1';const p=+process.env.PORT||${NODE_PORT};const s=net.connect(p,h);s.on('connect',()=>process.exit(0));s.on('error',()=>process.exit(1));\""]
      interval: 30s
      timeout: 5s
      retries: 5
    profiles: ["node","${profile}"]
YAML

  install -m 0644 "$tmp" "$out"
  rm -f "$tmp"

  env_set "ACTIVE_NODE_PROFILE" "$profile"
  NODE_COMPOSE_FILE_BASENAME="$(basename "$out")"
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
  mkdir -p "$VHOST_NGINX_DIR" "$VHOST_APACHE_DIR"

  local nginx_conf="${VHOST_NGINX_DIR}/${DOMAIN_NAME}.conf"
  local apache_conf="${VHOST_APACHE_DIR}/${DOMAIN_NAME}.conf"

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
      render_template "${TEMPLATE_DIR}/redirect.nginx.conf" "$nginx_conf"
    elif [[ "$KEEP_HTTP" == "y" || "$ENABLE_HTTPS" == "n" ]]; then
      case "$APP_TYPE" in
        node)    render_template "${TEMPLATE_DIR}/http.node.nginx.conf" "$nginx_conf" ;;
        proxyip) render_template "${TEMPLATE_DIR}/proxy-fixedip-http.nginx.conf" "$nginx_conf" ;;
        *)       render_template "${TEMPLATE_DIR}/http.nginx.conf" "$nginx_conf" ;;
      esac
    else
      _write_empty_conf "$nginx_conf"
    fi

    if [[ "$ENABLE_HTTPS" == "y" ]]; then
      local tmp; tmp="$(mktemp)"
      cat "$nginx_conf" >"$tmp" 2>/dev/null || true

      case "$APP_TYPE" in
        node)    render_template "${TEMPLATE_DIR}/https.node.nginx.conf" "$nginx_conf" ;;
        proxyip) render_template "${TEMPLATE_DIR}/proxy-fixedip-https.nginx.conf" "$nginx_conf" ;;
        *)       render_template "${TEMPLATE_DIR}/https.nginx.conf" "$nginx_conf" ;;
      esac

      _merge_confs "$tmp" "$nginx_conf"
      rm -f "$tmp"
    fi

    # Apache file not used in Nginx-only mode
    _write_empty_conf "$apache_conf"

  elif [[ "$SERVER_TYPE" == "Apache" ]]; then
    env_set "APACHE_ACTIVE" "apache"

    if [[ "$ENABLE_REDIRECTION" == "y" ]]; then
      render_template "${TEMPLATE_DIR}/redirect.nginx.conf" "$nginx_conf"
      _write_empty_conf "$apache_conf"
    elif [[ "$KEEP_HTTP" == "y" || "$ENABLE_HTTPS" == "n" ]]; then
      render_template "${TEMPLATE_DIR}/proxy-http.nginx.conf" "$nginx_conf"
      render_template "${TEMPLATE_DIR}/http.apache.conf" "$apache_conf"
    else
      _write_empty_conf "$nginx_conf"
      _write_empty_conf "$apache_conf"
    fi

    if [[ "$ENABLE_HTTPS" == "y" ]]; then
      local tmpn tmpa
      tmpn="$(mktemp)"; tmpa="$(mktemp)"
      cat "$nginx_conf"  >"$tmpn" 2>/dev/null || true
      cat "$apache_conf" >"$tmpa" 2>/dev/null || true

      render_template "${TEMPLATE_DIR}/proxy-https.nginx.conf" "$nginx_conf"
      render_template "${TEMPLATE_DIR}/https.apache.conf" "$apache_conf"

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
    NODE_VERSION NODE_CMD NODE_PROFILE NODE_SERVICE NODE_CONTAINER NODE_COMPOSE_FILE_BASENAME \
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
  while IFS= read -r -d '' v; do opts+=("$v"); done < <(collect_docroot_options || true)

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
  local d
  for d in "${DOMAINS[@]}"; do
    DOMAIN_NAME="$d"

    say "${MAGENTA}${BOLD}Generating:${NC} ${BOLD}${DOMAIN_NAME}${NC}"

    if [[ "$APP_TYPE" == "node" ]]; then
      create_node_compose
      ok "  ✔ Node compose generated"
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

  if [[ "${PROXY_SUBFILTER_ENABLED:-n}" == "y" ]]; then
    PROXY_SUBFILTER_INCLUDE="include /etc/nginx/proxy_sub_filter;"
  fi

  if [[ "${PROXY_CSP_ENABLED:-n}" == "y" ]]; then
    PROXY_CSP_INCLUDE="include /etc/nginx/proxy_csp_relax;"
  fi

  if [[ "${PROXY_REWRITE_YN:-n}" == "y" ]]; then
    # cookie rewrite
    PROXY_COOKIE_EXACT_INCLUDE=$'proxy_cookie_domain '"${PROXY_HOST}"' '"${DOMAIN_NAME}"';\n        proxy_cookie_path / /;'

    if [[ -n "${PARENT_COOKIE_DOMAIN:-}" ]]; then
      PROXY_COOKIE_PARENT_INCLUDE=$'proxy_cookie_domain '"${PARENT_COOKIE_DOMAIN}"' '"${DOMAIN_NAME}"';'
    fi

    # redirect rewrite
    local rehost="${PROXY_HOST//./\\.}"
    PROXY_REDIRECT_INCLUDE=$'proxy_redirect ~^https?://'"${rehost}"'(/.*)?$ $scheme://$host$1;'
  fi
}

###############################################################################
# 13) Config flows
###############################################################################
configure_php() {
  local T=9

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
  ;;
--ACTIVE_PHP_PROFILE)  env_get "ACTIVE_PHP_PROFILE" ;;
--ACTIVE_NODE_PROFILE) env_get "ACTIVE_NODE_PROFILE" ;;
--APACHE_ACTIVE)       env_get "APACHE_ACTIVE" ;;
*)
  configure_server
  cleanup_vars
  ;;
esac
