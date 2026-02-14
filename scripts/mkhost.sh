#!/usr/bin/env bash
# mkhost.sh — vhost + runtime chooser (PHP/Node) for LocalDevStack

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
# 1) Colors + UI
###############################################################################
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
CYAN=$'\033[0;36m'
YELLOW=$'\033[1;33m'
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

# Preflight templates
required_tpls=(
  redirect.nginx.conf
  http.nginx.conf https.nginx.conf
  http.node.nginx.conf https.node.nginx.conf
  proxy-http.nginx.conf proxy-https.nginx.conf
  http.apache.conf https.apache.conf
)

for f in "${required_tpls[@]}"; do
  [[ -r "$TEMPLATE_DIR/$f" ]] || {
    echo "Error: missing template: $TEMPLATE_DIR/$f" >&2
    echo "Debug: TEMPLATE_DIR=$TEMPLATE_DIR" >&2
    ls -la "$TEMPLATE_DIR" >&2 || true
    exit 1
  }
done
###############################################################################
# 3) Generic input helpers (centralized)
###############################################################################
trim() { echo "${1:-}" | xargs; }

prompt_line() {
  # prompt_line <stepN> <stepT> <label> <suffix> <default_display?>
  local n="$1" t="$2" label="$3" suffix="${4:-}" defdisp="${5:-}"
  if [[ -n "$defdisp" ]]; then
    echo -e "${YELLOW}Step ${n} of ${t}:${NC} ${CYAN}${label}${NC}${suffix} (${YELLOW}${defdisp}${NC}): "
  else
    echo -e "${YELLOW}Step ${n} of ${t}:${NC} ${CYAN}${label}${NC}${suffix}: "
  fi
}

step_ask_text_required() {
  # step_ask_text_required <n> <t> <label> <var> [hint]
  local n="$1" t="$2" label="$3" __var="$4" hint="${5:-}"
  local ans="" suffix=""
  [[ -n "$hint" ]] && suffix=" ${YELLOW}(${hint})${NC}"
  while true; do
    read -e -r -p "$(prompt_line "$n" "$t" "$label" "$suffix")" ans
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
  [[ -n "$hint" ]] && suffix=" ${YELLOW}(${hint})${NC}"
  read -e -r -p "$(prompt_line "$n" "$t" "$label" "$suffix" "$def")" ans
  ans="$(trim "${ans:-$def}")"
  [[ -n "$ans" ]] || ans="$def"
  printf -v "$__var" '%s' "$ans"
}

step_yn_default() {
  # step_yn_default <n> <t> <label> <var> <default_y_or_n> [hint]
  # Shows explicit answer option: (y/N) or (Y/n)
  local n="$1" t="$2" label="$3" __var="$4" def="${5:-n}" hint="${6:-}"
  local ans="" suffix="" opt=""
  [[ -n "$hint" ]] && suffix=" ${YELLOW}(${hint})${NC}"
  def="${def,,}"
  if [[ "$def" == "y" ]]; then opt=" ${YELLOW}(Y/n)${NC}"; else opt=" ${YELLOW}(y/N)${NC}"; fi
  while true; do
    read -e -r -p "$(echo -e "${YELLOW}Step ${n} of ${t}:${NC} ${CYAN}${label}${NC}${suffix}${opt}: ")" ans
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
  [[ -n "$hint" ]] && suffix=" ${YELLOW}(${hint})${NC}"
  while true; do
    read -e -r -p "$(prompt_line "$n" "$t" "$label" "$suffix")" ans
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
  [[ -n "$hint" ]] && suffix=" ${YELLOW}(${hint})${NC}"
  while true; do
    read -e -r -p "$(prompt_line "$n" "$t" "$label" "$suffix" "$def_disp")" ans
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

  if [[ -d "$base/public" ]]; then
    out+=("/public")
  fi

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
  [[ -r "$tpl" ]] || { err "Template not readable: $tpl"; exit 1; }

  local tmp; tmp="$(mktemp)"
  sed \
    -e "s|{{SERVER_NAME}}|$(sed_escape_repl "$DOMAIN_NAME")|g" \
    -e "s|{{DOC_ROOT}}|$(sed_escape_repl "$DOC_ROOT")|g" \
    -e "s|{{CLIENT_MAX_BODY_SIZE}}|$(sed_escape_repl "$CLIENT_MAX_BODY_SIZE")|g" \
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
  ok "Node compose generated: ${token}"
  ok "Node service: ${svc}  profile: ${profile}  port: ${NODE_PORT}"
  [[ -n "${NODE_CMD:-}" ]] && warn "Node override baked into compose: ${NODE_CMD}"
}

###############################################################################
# 10) Config generation
###############################################################################
create_configuration() {
  mkdir -p "$VHOST_NGINX_DIR" "$VHOST_APACHE_DIR"

  local nginx_conf="${VHOST_NGINX_DIR}/${DOMAIN_NAME}.conf"
  local apache_conf="${VHOST_APACHE_DIR}/${DOMAIN_NAME}.conf"

  ENABLE_CLIENT_VERIFICATION="${ENABLE_CLIENT_VERIFICATION:-ssl_verify_client off;}"

  if [[ "$APP_TYPE" == "node" ]]; then
    SERVER_TYPE="Nginx"
  fi

  if [[ "$SERVER_TYPE" == "Nginx" ]]; then
    if [[ "$ENABLE_REDIRECTION" == "y" ]]; then
      render_template "${TEMPLATE_DIR}/redirect.nginx.conf" "$nginx_conf"
    elif [[ "$KEEP_HTTP" == "y" || "$ENABLE_HTTPS" == "n" ]]; then
      if [[ "$APP_TYPE" == "node" ]]; then
        render_template "${TEMPLATE_DIR}/http.node.nginx.conf" "$nginx_conf"
      else
        render_template "${TEMPLATE_DIR}/http.nginx.conf" "$nginx_conf"
      fi
    else
      : >"$nginx_conf"
      chmod 0644 "$nginx_conf"
    fi

    if [[ "$ENABLE_HTTPS" == "y" ]]; then
      local tmp; tmp="$(mktemp)"
      cat "$nginx_conf" >"$tmp" 2>/dev/null || true

      if [[ "$APP_TYPE" == "node" ]]; then
        render_template "${TEMPLATE_DIR}/https.node.nginx.conf" "$nginx_conf"
      else
        render_template "${TEMPLATE_DIR}/https.nginx.conf" "$nginx_conf"
      fi

      if [[ -s "$tmp" ]]; then
        cat "$tmp" >"${nginx_conf}.tmpmerge"
        cat "$nginx_conf" >>"${nginx_conf}.tmpmerge"
        install -m 0644 "${nginx_conf}.tmpmerge" "$nginx_conf"
        rm -f "${nginx_conf}.tmpmerge"
      fi
      rm -f "$tmp"

      command -v certify >/dev/null 2>&1 && certify
    fi

  elif [[ "$SERVER_TYPE" == "Apache" ]]; then
    env_set "APACHE_ACTIVE" "apache"

    if [[ "$ENABLE_REDIRECTION" == "y" ]]; then
      render_template "${TEMPLATE_DIR}/redirect.nginx.conf" "$nginx_conf"
      : >"$apache_conf"
      chmod 0644 "$apache_conf"
    elif [[ "$KEEP_HTTP" == "y" || "$ENABLE_HTTPS" == "n" ]]; then
      render_template "${TEMPLATE_DIR}/proxy-http.nginx.conf" "$nginx_conf"
      render_template "${TEMPLATE_DIR}/http.apache.conf" "$apache_conf"
    else
      : >"$nginx_conf"
      : >"$apache_conf"
      chmod 0644 "$nginx_conf" "$apache_conf"
    fi

    if [[ "$ENABLE_HTTPS" == "y" ]]; then
      local tmpn tmpa
      tmpn="$(mktemp)"; tmpa="$(mktemp)"
      cat "$nginx_conf"  >"$tmpn" 2>/dev/null || true
      cat "$apache_conf" >"$tmpa" 2>/dev/null || true

      render_template "${TEMPLATE_DIR}/proxy-https.nginx.conf" "$nginx_conf"
      render_template "${TEMPLATE_DIR}/https.apache.conf" "$apache_conf"

      if [[ -s "$tmpn" ]]; then
        cat "$tmpn" >"${nginx_conf}.tmpmerge"
        cat "$nginx_conf" >>"${nginx_conf}.tmpmerge"
        install -m 0644 "${nginx_conf}.tmpmerge" "$nginx_conf"
        rm -f "${nginx_conf}.tmpmerge"
      fi
      if [[ -s "$tmpa" ]]; then
        cat "$tmpa" >"${apache_conf}.tmpmerge"
        cat "$apache_conf" >>"${apache_conf}.tmpmerge"
        install -m 0644 "${apache_conf}.tmpmerge" "$apache_conf"
        rm -f "${apache_conf}.tmpmerge"
      fi
      rm -f "$tmpn" "$tmpa"

      command -v certify >/dev/null 2>&1 && certify
    fi
  else
    err "Invalid server type: ${SERVER_TYPE:-}"
    return 1
  fi

  if [[ "$APP_TYPE" == "php" ]]; then
    env_set "ACTIVE_PHP_PROFILE" "${PHP_CONTAINER_PROFILE}"
    env_set "ACTIVE_NODE_PROFILE" ""
  else
    env_set "ACTIVE_PHP_PROFILE" ""
  fi

  ok "Saved configuration for: ${DOMAIN_NAME}"
}

###############################################################################
# 11) Flow
###############################################################################
cleanup_vars() {
  unset -v DOMAIN_NAME APP_TYPE SERVER_TYPE \
    ENABLE_HTTPS ENABLE_REDIRECTION KEEP_HTTP \
    DOC_ROOT CLIENT_MAX_BODY_SIZE CLIENT_MAX_BODY_SIZE_APACHE \
    ENABLE_STREAMING PROXY_STREAMING_INCLUDE FASTCGI_STREAMING_INCLUDE APACHE_STREAMING_INCLUDE \
    ENABLE_CLIENT_VERIFICATION CLIENT_VERIF \
    PHP_VERSION PHP_CONTAINER_PROFILE PHP_CONTAINER PHP_APACHE_CONTAINER_PROFILE PHP_APACHE_CONTAINER \
    NODE_VERSION NODE_CMD NODE_PROFILE NODE_SERVICE NODE_CONTAINER \
    NODE_DIR_TOKEN || true
}

choose_app_type_step2() {
  say "${CYAN}  1) PHP${NC}"
  say "${CYAN}  2) NodeJs${NC}"
  local sel
  pick_index_required 2 9 "App type (choose 1-2)" 2 sel
  case "$sel" in
  1) APP_TYPE="php"; ok "Selected: PHP" ;;
  2) APP_TYPE="node"; ok "Selected: NodeJs" ;;
  *) err "Invalid selection."; exit 1 ;;
  esac
}

choose_server_type_step4() {
  say "${CYAN}  1) Nginx${NC}"
  say "${CYAN}  2) Apache${NC}"
  local sel
  pick_index_required 4 9 "Server type (choose 1-2)" 2 sel
  case "$sel" in
  1) SERVER_TYPE="Nginx"; ok "Selected: Nginx" ;;
  2) SERVER_TYPE="Apache"; ok "Selected: Apache" ;;
  *) err "Invalid selection."; exit 1 ;;
  esac
}

choose_protocol_step5() {
  say "${CYAN}  1) HTTP only${NC}"
  say "${CYAN}  2) HTTPS only${NC}"
  say "${CYAN}  3) Both HTTP and HTTPS${NC}"
  local sel
  pick_index_default_value 5 9 "HTTP/HTTPS mode (choose 1-3)" 3 3 "Both" sel
  case "$sel" in
  1) ENABLE_HTTPS="n"; ENABLE_REDIRECTION="n"; KEEP_HTTP="y" ;;
  2) ENABLE_HTTPS="y"; ENABLE_REDIRECTION="n"; KEEP_HTTP="n" ;;
  3)
    ENABLE_HTTPS="y"
    # FIX #1: redirection default is y and explicit (Y/n) shown
    step_yn_default 5 9 "HTTP → HTTPS redirection" ENABLE_REDIRECTION "y"
    if [[ "$ENABLE_REDIRECTION" == "y" ]]; then KEEP_HTTP="n"; else KEEP_HTTP="y"; fi
    ;;
  *) err "Invalid selection."; exit 1 ;;
  esac
}

prompt_php_runtime_step3() {
  require_versions_db
  say "${CYAN}PHP versions:${NC}"

  mapfile -t active_rows < <(jq -r '.php.active[]? | "\(.version)|\(.debut)|\(.eol)"' "$RUNTIME_VERSIONS_DB")
  mapfile -t dep_rows    < <(jq -r '.php.deprecated[]? | "\(.version)|\(.eol)"' "$RUNTIME_VERSIONS_DB")

  local idx_map_type=() idx_map_value=()
  local n=0

  printf "  %2d) %-7s %s\n" 0 "Custom" "Version"
  idx_map_type[0]="custom"; idx_map_value[0]=""

  say "${CYAN}Active (supported):${NC}"
  for r in "${active_rows[@]}"; do
    [[ "$n" -ge "$MAX_VERSIONS" ]] && break
    n=$((n+1))
    IFS='|' read -r v debut eol <<<"$r"
    printf "  %2d) %-7s %s\n" "$n" "$v" "$(fmt_range "$debut" "$eol")"
    idx_map_type[$n]="php"; idx_map_value[$n]="$v"
  done

  say "${CYAN}Deprecated (EOL):${NC}"
  for r in "${dep_rows[@]}"; do
    [[ "$n" -ge "$MAX_VERSIONS" ]] && break
    n=$((n+1))
    IFS='|' read -r v eol <<<"$r"
    printf "  %2d) %-7s %s\n" "$n" "$v" "$(fmt_eol_tilde "$eol")"
    idx_map_type[$n]="php"; idx_map_value[$n]="$v"
  done

  local printed_max="$n"
  local sel def_idx=1 def_disp="${idx_map_value[1]:-1}"
  pick_index_default_value 3 9 "Runtime (select 0-${printed_max})" "$printed_max" "$def_idx" "$def_disp" sel

  if [[ "${idx_map_type[$sel]}" == "custom" ]]; then
    local custom=""
    while true; do
      step_ask_text_required 3 9 "PHP version (Major.Minor)" custom "e.g., 8.4"
      if php_is_valid_custom "$custom"; then
        PHP_VERSION="$custom"; break
      fi
      err "Invalid / unknown PHP version."
    done
  else
    PHP_VERSION="${idx_map_value[$sel]:-}"
    [[ -n "$PHP_VERSION" ]] || { err "Invalid selection."; exit 1; }
  fi

  PHP_CONTAINER_PROFILE="php${PHP_VERSION//./}"
  PHP_APACHE_CONTAINER_PROFILE="php${PHP_VERSION//./}apache"
  PHP_CONTAINER="PHP_${PHP_VERSION}"
  PHP_APACHE_CONTAINER="PHP_${PHP_VERSION}_APACHE"
  ok "Selected PHP version: $PHP_VERSION"
}

prompt_node_runtime_step3() {
  require_versions_db

  local current_major lts_major
  current_major="$(jq -r '.node.tags.current // ""' "$RUNTIME_VERSIONS_DB")"
  lts_major="$(jq -r '.node.tags.lts // ""' "$RUNTIME_VERSIONS_DB")"

  say "${CYAN}Node versions:${NC}"

  mapfile -t active_rows < <(jq -r '.node.active[]? | "\(.version)|\(.debut)|\(.eol)|\(.lts)"' "$RUNTIME_VERSIONS_DB")
  mapfile -t dep_rows    < <(jq -r '.node.deprecated[]? | "\(.version)|\(.eol)"' "$RUNTIME_VERSIONS_DB")

  local idx_map_type=() idx_map_value=()
  local n=0

  printf "  %2d) %-7s %s\n" 0 "Custom" "Version"
  idx_map_type[0]="custom"; idx_map_value[0]=""

  n=1; printf "  %2d) %-7s %s\n" "$n" "CURRENT" "(v${current_major})"
  idx_map_type[$n]="tag"; idx_map_value[$n]="current"

  n=2; printf "  %2d) %-7s %s\n" "$n" "LTS" "(v${lts_major})"
  idx_map_type[$n]="tag"; idx_map_value[$n]="lts"

  local slots_left=$((MAX_VERSIONS - 3))

  say "${CYAN}Active (supported):${NC}"
  for r in "${active_rows[@]}"; do
    [[ "$slots_left" -le 0 ]] && break
    n=$((n+1)); slots_left=$((slots_left-1))
    IFS='|' read -r v debut eol lts <<<"$r"
    if [[ "$lts" == "true" ]]; then
      printf "  %2d) %-7s %s LTS\n" "$n" "v${v}" "$(fmt_range "$debut" "$eol")"
    else
      printf "  %2d) %-7s %s\n" "$n" "v${v}" "$(fmt_range "$debut" "$eol")"
    fi
    idx_map_type[$n]="node"; idx_map_value[$n]="$v"
  done

  say "${CYAN}Deprecated (EOL):${NC}"
  for r in "${dep_rows[@]}"; do
    [[ "$slots_left" -le 0 ]] && break
    n=$((n+1)); slots_left=$((slots_left-1))
    IFS='|' read -r v eol <<<"$r"
    printf "  %2d) %-7s %s\n" "$n" "v${v}" "$(fmt_eol_tilde "$eol")"
    idx_map_type[$n]="node"; idx_map_value[$n]="$v"
  done

  local printed_max="$n"
  local sel def_idx=2 def_disp="LTS"
  pick_index_default_value 3 9 "Runtime (select 0-${printed_max})" "$printed_max" "$def_idx" "$def_disp" sel

  case "${idx_map_type[$sel]:-}" in
  node) NODE_VERSION="${idx_map_value[$sel]}" ;;
  tag)  NODE_VERSION="${idx_map_value[$sel]}" ;;
  custom)
    local custom=""
    while true; do
      step_ask_text_required 3 9 "Node major" custom "e.g., 24"
      if node_is_valid_custom "$custom"; then
        NODE_VERSION="$custom"; break
      fi
      err "Invalid / unknown Node major."
    done
    ;;
  *) err "Invalid selection."; exit 1 ;;
  esac

  ok "Selected Node version: $NODE_VERSION"
}

choose_doc_root_step6() {
  local opts=()
  opts+=("<Custom Path>")

  while IFS= read -r -d '' v; do opts+=("$v"); done < <(collect_docroot_options || true)

  say "${CYAN}Doc root suggestions from ${APP_SCAN_DIR}:${NC}"
  print_two_column_menu opts 0

  local max=$(( ${#opts[@]} - 1 ))
  local sel
  pick_index_required 6 9 "Doc root (choose 0-${max})" "$max" sel

  if [[ "$sel" == "0" ]]; then
    step_ask_text_required 6 9 "Doc root" DOC_ROOT "e.g., /site/public"
    DOC_ROOT="$(normalize_rel_path "$DOC_ROOT")"
  else
    DOC_ROOT="$(normalize_rel_path "${opts[$sel]}")"
    ok "Selected Doc root: $DOC_ROOT"
  fi
}

configure_server() {
  require_versions_db

  # 1) Domain (required, one-line)
  while true; do
    step_ask_text_required 1 9 "Domain" DOMAIN_NAME "e.g., app.localhost / example.com"
    validate_domain "$DOMAIN_NAME" && break
    warn "Invalid domain name. Try again."
  done

  # 2) App type (NO default)
  choose_app_type_step2

  # 3) Runtime versions (default index shown as VALUE)
  if [[ "$APP_TYPE" == "php" ]]; then
    prompt_php_runtime_step3
  else
    prompt_node_runtime_step3
  fi

  # 4) Server type (NO default; PHP only)
  if [[ "$APP_TYPE" == "php" ]]; then
    choose_server_type_step4
  else
    SERVER_TYPE="Nginx"
    step_yn_default 4 9 "Custom Node start command" _NODE_CMD_YN "n"
    if [[ "$_NODE_CMD_YN" == "y" ]]; then
      step_ask_text_required 4 9 "Node command" NODE_CMD "npm run dev / npm start / node server.js"
      NODE_CMD="$(trim "$NODE_CMD")"
    else
      NODE_CMD=""
    fi
    unset -v _NODE_CMD_YN || true
  fi

  # 5) HTTP/HTTPS mode (default 3)
  choose_protocol_step5

  # 6) Doc root (NO default)
  choose_doc_root_step6

  # 7) Client body size (default 10)
  local _MB=""
  step_ask_text_default 7 9 "Client body size (MB)" _MB "10"
  while [[ ! "$_MB" =~ ^[0-9]+$ ]]; do
    err "Invalid number."
    step_ask_text_default 7 9 "Client body size (MB)" _MB "10"
  done
  CLIENT_MAX_BODY_SIZE_APACHE=$((_MB * 1000000))
  CLIENT_MAX_BODY_SIZE="${_MB}M"
  unset -v _MB || true

  # 8) Streaming/SSE mode (default n) — FIX #2 ensured here
  PROXY_STREAMING_INCLUDE=""
  FASTCGI_STREAMING_INCLUDE=""
  APACHE_STREAMING_INCLUDE=""
  step_yn_default 8 9 "Streaming/SSE mode" ENABLE_STREAMING "n"
  if [[ "$ENABLE_STREAMING" == "y" ]]; then
    PROXY_STREAMING_INCLUDE="include /etc/nginx/proxy_streaming;"
    FASTCGI_STREAMING_INCLUDE="include /etc/nginx/fastcgi_streaming;"
    APACHE_STREAMING_INCLUDE=$'  # Streaming/SSE tuning\n  ProxyTimeout 3600\n  Timeout 3600\n  Header set Cache-Control "no-cache"\n  Header set X-Accel-Buffering "no"\n'
  fi

  # 9) Client verification (default n) — FIX #3 ensured here
  if [[ "${ENABLE_HTTPS:-n}" != "y" ]]; then
    ENABLE_CLIENT_VERIFICATION="ssl_verify_client off;"
    ok "Client verification disabled (HTTPS not enabled)."
  else
    step_yn_default 9 9 "Client certificate verification (mTLS)" CLIENT_VERIF "n"
    if [[ "$CLIENT_VERIF" == "y" ]]; then
      ENABLE_CLIENT_VERIFICATION="ssl_verify_client on;"
      warn "Client verification enabled. Ensure client certs are configured."
    else
      ENABLE_CLIENT_VERIFICATION="ssl_verify_client off;"
    fi
  fi

  if [[ "$APP_TYPE" == "node" ]]; then
    create_node_compose
  fi

  create_configuration
}

###############################################################################
# 12) CLI flags
###############################################################################
case "${1:-}" in
--RESET)
  env_set "APACHE_ACTIVE" ""
  env_set "ACTIVE_PHP_PROFILE" ""
  env_set "ACTIVE_NODE_PROFILE" ""
  ok "Reset done."
  ;;
--ACTIVE_PHP_PROFILE)  env_get "ACTIVE_PHP_PROFILE" ;;
--ACTIVE_NODE_PROFILE) env_get "ACTIVE_NODE_PROFILE" ;;
--APACHE_ACTIVE)       env_get "APACHE_ACTIVE" ;;
*)
  configure_server
  cleanup_vars
  ;;
esac
