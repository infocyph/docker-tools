#!/bin/bash

# Define colors
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

###############################################################################
# Runtime versions DB (baked during docker build) — REQUIRED
###############################################################################
RUNTIME_VERSIONS_DB="${RUNTIME_VERSIONS_DB:-/etc/share/runtime-versions.json}"
MAX_VERSIONS="${MAX_VERSIONS:-15}"

require_versions_db() {
  command -v jq >/dev/null 2>&1 || {
    echo -e "${RED}Error:${NC} jq not found."
    exit 1
  }
  [[ -r "$RUNTIME_VERSIONS_DB" ]] || {
    echo -e "${RED}Error:${NC} versions DB not found/readable: $RUNTIME_VERSIONS_DB"
    exit 1
  }
}

###############################################################################
# Input helpers
###############################################################################
pick_index_allow_zero() {
  # pick_index_allow_zero <max> <prompt>   (0..max)
  local max="$1" prompt="$2" ans
  while true; do
    read -e -r -p "$(echo -e "${CYAN}${prompt}${NC} ")" ans
    ans="$(echo "${ans:-}" | xargs)"
    [[ "$ans" =~ ^[0-9]+$ ]] || { echo -e "${RED}Enter a number.${NC}"; continue; }
    (( ans >= 0 && ans <= max )) || { echo -e "${RED}Out of range (0-${max}).${NC}"; continue; }
    echo "$ans"
    return 0
  done
}

###############################################################################
# Helpers
###############################################################################
validate_domain() {
  local domain=$1
  local regex="^([a-zA-Z0-9][-a-zA-Z0-9]{0,253}[a-zA-Z0-9]\.)+[a-zA-Z]{2,}$"
  if [[ ! $domain =~ $regex ]]; then
    echo -e "${RED}Invalid domain name:${NC} $domain"
    return 1
  fi
  return 0
}

prompt_for_domain() {
  while true; do
    read -e -r -p "$(echo -e "${CYAN}Enter the domain (e.g., example.com):${NC} ")" DOMAIN_NAME
    DOMAIN_NAME="$(echo "$DOMAIN_NAME" | xargs)"
    if validate_domain "$DOMAIN_NAME"; then
      break
    fi
    echo -e "${YELLOW}Please enter a valid domain name.${NC}"
  done
}

validate_input() {
  local input="$1"
  local message="$2"
  while [[ -z "$input" ]]; do
    echo -e "${RED}${message}${NC}"
    read -e -r input
  done
  echo "$input"
}

slugify() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/_/g; s/^_+|_+$//g'
}

to_env_key() {
  local v="${1:-}"
  v="$(echo "$v" | xargs)"
  v="${v,,}"

  case "$v" in
  current) echo "CURRENT" ;;
  lts)     echo "LTS" ;;
  '' )     echo "" ;;
  *)
    if [[ "$v" =~ ^[0-9]+$ ]]; then
      echo "$v"
    else
      echo "$v" | sed -E 's/[^0-9]+//g'
    fi
    ;;
  esac
}

update_env() {
  local key="$1" value="$2"
  local f="/etc/environment"
  touch "$f"
  if grep -qE "^${key}=" "$f"; then
    sed -i "s|^${key}=.*|${key}=${value}|" "$f"
  else
    echo "${key}=${value}" >>"$f"
  fi
}

get_env() {
  grep -E "^$1=" /etc/environment 2>/dev/null | cut -d'=' -f2-
}

fmt_range() {
  # fmt_range <debut> <eol> => "(debut to eol)" with fallbacks
  local debut="${1:-}" eol="${2:-}"
  [[ -z "$debut" || "$debut" == "null" ]] && debut="unknown"
  [[ -z "$eol"   || "$eol"   == "null" ]] && eol="unknown"
  echo "(${debut} to ${eol})"
}

fmt_eol_tilde() {
  # fmt_eol_tilde <eol> => "(~eol)" with fallbacks
  local eol="${1:-}"
  [[ -z "$eol" || "$eol" == "null" ]] && eol="unknown"
  echo "(~${eol})"
}

###############################################################################
# App type
###############################################################################
choose_app_type() {
  echo -e "${CYAN}Choose app type:${NC}"
  PS3="$(echo -e "${YELLOW}👉 Select app type: ${NC}") "
  select app_type in "PHP" "NodeJs"; do
    case "$app_type" in
    "PHP")
      APP_TYPE="php"
      echo -e "${GREEN}Selected: PHP${NC}"
      break
      ;;
    "NodeJs")
      APP_TYPE="node"
      echo -e "${GREEN}Selected: NodeJs${NC}"
      break
      ;;
    *)
      echo -e "${RED}Invalid option, please select again.${NC}"
      ;;
    esac
  done
}

###############################################################################
# HTTP server type (only meaningful for PHP)
###############################################################################
choose_server_type() {
  echo -e "${CYAN}Choose the server to configure:${NC}"
  PS3="$(echo -e "${YELLOW}👉 Select server type: ${NC}") "
  select server_type in "Nginx" "Apache"; do
    if [[ "$server_type" == "Nginx" || "$server_type" == "Apache" ]]; then
      SERVER_TYPE="$server_type"
      echo -e "${GREEN}You have selected $server_type.${NC}"
      break
    fi
    echo -e "${RED}Invalid option, please select again.${NC}"
  done
}

prompt_for_http_https() {
  echo -e "${CYAN}Choose the type of protocol:${NC}"
  PS3="$(echo -e "${YELLOW}👉 Select option: ${NC}") "
  select choice in "HTTP only" "HTTPS only" "Both HTTP and HTTPS"; do
    case $choice in
    "HTTP only")
      ENABLE_HTTPS="n"
      ENABLE_REDIRECTION="n"
      KEEP_HTTP="y"
      break
      ;;
    "HTTPS only")
      ENABLE_HTTPS="y"
      ENABLE_REDIRECTION="n"
      KEEP_HTTP="n"
      break
      ;;
    "Both HTTP and HTTPS")
      ENABLE_HTTPS="y"
      read -e -r -p "$(echo -e "${CYAN}Set up HTTP to HTTPS redirection? (y/N):${NC} ")" ENABLE_REDIRECTION
      ENABLE_REDIRECTION=${ENABLE_REDIRECTION,,}
      if [[ "$ENABLE_REDIRECTION" =~ ^(y|yes)$ ]]; then
        ENABLE_REDIRECTION="y"
        KEEP_HTTP="n"
      else
        ENABLE_REDIRECTION="n"
        KEEP_HTTP="y"
      fi
      break
      ;;
    *)
      echo -e "${RED}Invalid option, please select again.${NC}"
      ;;
    esac
  done
}

prompt_for_client_verification() {
  read -e -r -p "$(echo -e "${CYAN}Enable client certificate verification (mutual TLS)? (y/N):${NC} ")" client_verif_choice
  client_verif_choice=${client_verif_choice,,}
  if [[ "$client_verif_choice" =~ ^(y|yes)$ ]]; then
    ENABLE_CLIENT_VERIFICATION="ssl_verify_client on;"
    echo -e "${GREEN}Client certificate verification enabled.${RED} Ensure client certificates are in place.${NC}"
  else
    ENABLE_CLIENT_VERIFICATION="ssl_verify_client off;"
    echo -e "${YELLOW}Client certificate verification disabled.${NC}"
  fi
}

prompt_for_doc_root() {
  local input
  read -e -r -p "$(echo -e "${CYAN}Enter the relative DocumentRoot / ProjectRoot (e.g., /site/public or /my-node-app):${NC} ")" input
  input="$(validate_input "$input" "Path cannot be empty. Please enter a valid path:")"
  input="$(echo "$input" | xargs)"
  [[ "$input" == /* ]] || input="/$input"
  while [[ "$input" == *"//"* ]]; do input="${input//\/\//\/}"; done
  [[ "$input" != "/" ]] && input="${input%/}"
  DOC_ROOT="$input"
}

prompt_for_client_max_body_size() {
  read -e -r -p "$(echo -e "${CYAN}Enter the maximum client body size (MB, default 10):${NC} ")" CLIENT_MAX_BODY_SIZE
  CLIENT_MAX_BODY_SIZE=${CLIENT_MAX_BODY_SIZE:-10}
  while [[ ! "$CLIENT_MAX_BODY_SIZE" =~ ^[0-9]+$ ]]; do
    echo -e "${RED}Invalid input. Please enter a valid number (e.g., 12):${NC}"
    read -e -r CLIENT_MAX_BODY_SIZE
  done
  CLIENT_MAX_BODY_SIZE_APACHE=$((CLIENT_MAX_BODY_SIZE * 1000000))
  CLIENT_MAX_BODY_SIZE="${CLIENT_MAX_BODY_SIZE}M"
}

###############################################################################
# Version validators (JSON-driven)
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
# PHP versions (limit MAX_VERSIONS) — 0=Custom, then Active, then Deprecated
# 3 columns: INDEX | VERSION | DATES
###############################################################################
prompt_for_php_version() {
  require_versions_db

  echo -e "${CYAN}PHP versions:${NC}"

  mapfile -t active_rows < <(jq -r '.php.active[]? | "\(.version)|\(.debut)|\(.eol)"' "$RUNTIME_VERSIONS_DB")
  mapfile -t dep_rows    < <(jq -r '.php.deprecated[]? | "\(.version)|\(.eol)"' "$RUNTIME_VERSIONS_DB")

  local n=0
  local idx_map_type=() idx_map_value=()

  # 0) Custom first
  printf "  %2d) %-7s %s\n" 0 "Custom" "Version"
  idx_map_type[0]="custom"
  idx_map_value[0]=""

  echo -e "${CYAN}Active (supported):${NC}"
  for r in "${active_rows[@]}"; do
    [[ "$n" -ge "$MAX_VERSIONS" ]] && break
    n=$((n+1))
    IFS='|' read -r v debut eol <<< "$r"
    printf "  %2d) %-7s %s\n" "$n" "$v" "$(fmt_range "$debut" "$eol")"
    idx_map_type[$n]="php"
    idx_map_value[$n]="$v"
  done

  echo -e "${CYAN}Deprecated (EOL):${NC}"
  for r in "${dep_rows[@]}"; do
    [[ "$n" -ge "$MAX_VERSIONS" ]] && break
    n=$((n+1))
    IFS='|' read -r v eol <<< "$r"
    printf "  %2d) %-7s %s\n" "$n" "$v" "$(fmt_eol_tilde "$eol")"
    idx_map_type[$n]="php"
    idx_map_value[$n]="$v"
  done

  local sel PHP_VERSION custom
  sel="$(pick_index_allow_zero "$MAX_VERSIONS" "Select option (0-${MAX_VERSIONS}):")"

  if [[ "${idx_map_type[$sel]}" == "custom" ]]; then
    while true; do
      read -e -r -p "$(echo -e "${CYAN}Enter PHP version (Major.Minor, e.g., 8.4):${NC} ")" custom
      custom="$(echo "${custom:-}" | xargs)"
      if php_is_valid_custom "$custom"; then
        PHP_VERSION="$custom"
        break
      fi
      echo -e "${RED}Invalid / unknown PHP version.${NC}"
    done
  else
    PHP_VERSION="${idx_map_value[$sel]}"
    [[ -n "$PHP_VERSION" ]] || {
      echo -e "${RED}Invalid selection.${NC}"
      exit 1
    }
  fi

  PHP_CONTAINER_PROFILE="php${PHP_VERSION//./}"
  PHP_APACHE_CONTAINER_PROFILE="php${PHP_VERSION//./}apache"
  PHP_CONTAINER="PHP_${PHP_VERSION}"
  PHP_APACHE_CONTAINER="PHP_${PHP_VERSION}_APACHE"
  echo -e "${GREEN}You have selected PHP version $PHP_VERSION.${NC}"
}

###############################################################################
# Node versions (limit MAX_VERSIONS) — indices:
#   0 = Custom
#   1..15 = versions (active then deprecated)
#   16 = CURRENT
#   17 = LTS
###############################################################################
prompt_for_node_version() {
  require_versions_db

  local current_major lts_major
  current_major="$(jq -r '.node.tags.current // ""' "$RUNTIME_VERSIONS_DB")"
  lts_major="$(jq -r '.node.tags.lts // ""' "$RUNTIME_VERSIONS_DB")"

  echo -e "${CYAN}Node versions:${NC}"

  mapfile -t active_rows < <(jq -r '.node.active[]? | "\(.version)|\(.debut)|\(.eol)|\(.lts)"' "$RUNTIME_VERSIONS_DB")
  mapfile -t dep_rows    < <(jq -r '.node.deprecated[]? | "\(.version)|\(.eol)"' "$RUNTIME_VERSIONS_DB")

  local n=0
  local idx_map_type=() idx_map_value=()

  # 0) Custom first
  printf "  %2d) %-7s %s\n" 0 "Custom" "Version"
  idx_map_type[0]="custom"
  idx_map_value[0]=""

  echo -e "${CYAN}Active (supported):${NC}"
  for r in "${active_rows[@]}"; do
    [[ "$n" -ge "$MAX_VERSIONS" ]] && break
    n=$((n+1))
    IFS='|' read -r v debut eol lts <<< "$r"
    if [[ "$lts" == "true" ]]; then
      printf "  %2d) %-7s %s LTS\n" "$n" "v${v}" "$(fmt_range "$debut" "$eol")"
    else
      printf "  %2d) %-7s %s\n" "$n" "v${v}" "$(fmt_range "$debut" "$eol")"
    fi
    idx_map_type[$n]="node"
    idx_map_value[$n]="$v"
  done

  echo -e "${CYAN}Deprecated (EOL):${NC}"
  for r in "${dep_rows[@]}"; do
    [[ "$n" -ge "$MAX_VERSIONS" ]] && break
    n=$((n+1))
    IFS='|' read -r v eol <<< "$r"
    printf "  %2d) %-7s %s\n" "$n" "v${v}" "$(fmt_eol_tilde "$eol")"
    idx_map_type[$n]="node"
    idx_map_value[$n]="$v"
  done

  # Force indices 16/17 as requested (assumes MAX_VERSIONS=15)
  local CURRENT_IDX=$((MAX_VERSIONS + 1))
  local LTS_IDX=$((MAX_VERSIONS + 2))

  printf "  %2d) %-7s %s\n" "$CURRENT_IDX" "CURRENT" "(v${current_major})"
  idx_map_type[$CURRENT_IDX]="tag"
  idx_map_value[$CURRENT_IDX]="current"

  printf "  %2d) %-7s %s\n" "$LTS_IDX" "LTS" "(v${lts_major})"
  idx_map_type[$LTS_IDX]="tag"
  idx_map_value[$LTS_IDX]="lts"

  local max_sel="$LTS_IDX"
  local sel custom
  sel="$(pick_index_allow_zero "$max_sel" "Select option (0-${max_sel}):")"

  case "${idx_map_type[$sel]}" in
  node)
    NODE_VERSION="${idx_map_value[$sel]}"
    ;;
  tag)
    NODE_VERSION="${idx_map_value[$sel]}"   # current|lts
    ;;
  custom)
    while true; do
      read -e -r -p "$(echo -e "${CYAN}Enter Node major only (e.g., 24):${NC} ")" custom
      custom="$(echo "${custom:-}" | xargs)"
      if node_is_valid_custom "$custom"; then
        NODE_VERSION="$custom"
        break
      fi
      echo -e "${RED}Invalid / unknown Node major.${NC}"
    done
    ;;
  *)
    echo -e "${RED}Invalid selection.${NC}"
    exit 1
    ;;
  esac

  echo -e "${GREEN}Selected Node version: $NODE_VERSION${NC}"
}

prompt_for_node_command() {
  local def="npm run dev"
  read -e -r -p "$(echo -e "${CYAN}Node start command (default: ${def}):${NC} ")" NODE_CMD
  NODE_CMD="$(echo "${NODE_CMD:-$def}" | xargs)"
}

###############################################################################
# Template renderer
###############################################################################
generate_conf_from_template() {
  local template_file=$1
  local output_file=$2

  sed -e "s|{{SERVER_NAME}}|$DOMAIN_NAME|g" \
    -e "s|{{DOC_ROOT}}|$DOC_ROOT|g" \
    -e "s|{{CLIENT_MAX_BODY_SIZE}}|$CLIENT_MAX_BODY_SIZE|g" \
    -e "s|{{CLIENT_MAX_BODY_SIZE_APACHE}}|$CLIENT_MAX_BODY_SIZE_APACHE|g" \
    -e "s|{{PHP_APACHE_CONTAINER}}|$PHP_APACHE_CONTAINER|g" \
    -e "s|{{APACHE_CONTAINER}}|${APACHE_CONTAINER:-APACHE}|g" \
    -e "s|{{PHP_CONTAINER}}|$PHP_CONTAINER|g" \
    -e "s|{{CLIENT_VERIFICATION}}|$ENABLE_CLIENT_VERIFICATION|g" \
    -e "s|{{NODE_CONTAINER}}|${NODE_CONTAINER:-}|g" \
    -e "s|{{NODE_PORT}}|3000|g" \
    "$template_file" >>"$output_file"
}

###############################################################################
# Node dynamic compose generator (PORT always 3000)
###############################################################################
create_node_compose() {
  mkdir -p /etc/share/vhosts/node

  local token domain_token svc cname profile node_key
  domain_token="$(slugify "$DOMAIN_NAME")"
  token="${NODE_DIR_TOKEN:-$domain_token}"

  svc="node_${token}"
  cname="NODE_${token^^}"
  profile="node_${token}"

  NODE_SERVICE="$svc"
  NODE_CONTAINER="$svc"
  NODE_PROFILE="$profile"

  node_key="$(to_env_key "$NODE_VERSION")"

  local CONFIG_DOCKER_NODE="/etc/share/vhosts/node/${token}.yaml"
  rm -f "$CONFIG_DOCKER_NODE"

  cat >"$CONFIG_DOCKER_NODE" <<YAML
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
      - PORT=3000
      - HOST=0.0.0.0
    env_file:
      - .env
    networks:
      frontend: {}
      backend: {}
      datastore: {}
    volumes:
      - "\${PROJECT_DIR:-./../../../application}:/app"
      - "../../configuration/ssh:/home/\${USER}/.ssh:ro"
    depends_on:
      - server-tools
    command: ["sh","-lc","cd /app${DOC_ROOT} && exec ${NODE_CMD}"]
    healthcheck:
      test: ["CMD-SHELL", "node -e \\"const net=require('net');const p=process.env.PORT||3000;const s=net.connect(p,'127.0.0.1');s.on('connect',()=>process.exit(0));s.on('error',()=>process.exit(1));\\""]
      interval: 30s
      timeout: 5s
      retries: 5
    profiles: ["node","${profile}"]
YAML

  chmod 644 "$CONFIG_DOCKER_NODE"
  update_env "ACTIVE_NODE_PROFILE" "$profile"

  echo -e "${GREEN}Node compose generated:${NC} $CONFIG_DOCKER_NODE"
  echo -e "${GREEN}Node service:${NC} $svc  ${GREEN}profile:${NC} $profile  ${GREEN}port:${NC} 3000"
}

###############################################################################
# Create configs
###############################################################################
create_configuration() {
  local CONFIG_NGINX="/etc/share/vhosts/nginx/${DOMAIN_NAME}.conf"
  local CONFIG_APACHE="/etc/share/vhosts/apache/${DOMAIN_NAME}.conf"
  local base_template_path="/etc/http-templates"

  rm -f "$CONFIG_NGINX" "$CONFIG_APACHE"

  ENABLE_CLIENT_VERIFICATION="${ENABLE_CLIENT_VERIFICATION:-ssl_verify_client off;}"

  if [[ "$APP_TYPE" == "node" ]]; then
    SERVER_TYPE="Nginx"
  fi

  if [[ "$SERVER_TYPE" == "Nginx" ]]; then
    if [[ "$ENABLE_REDIRECTION" == "y" ]]; then
      generate_conf_from_template "$base_template_path/redirect.nginx.conf" "$CONFIG_NGINX"
    elif [[ "$KEEP_HTTP" == "y" || "$ENABLE_HTTPS" == "n" ]]; then
      if [[ "$APP_TYPE" == "node" ]]; then
        generate_conf_from_template "$base_template_path/http.node.nginx.conf" "$CONFIG_NGINX"
      else
        generate_conf_from_template "$base_template_path/http.nginx.conf" "$CONFIG_NGINX"
      fi
    fi

    if [[ "$ENABLE_HTTPS" == "y" ]]; then
      if [[ "$APP_TYPE" == "node" ]]; then
        generate_conf_from_template "$base_template_path/https.node.nginx.conf" "$CONFIG_NGINX"
      else
        generate_conf_from_template "$base_template_path/https.nginx.conf" "$CONFIG_NGINX"
      fi
      certify
    fi

    chmod 644 "$CONFIG_NGINX"

  elif [[ "$SERVER_TYPE" == "Apache" ]]; then
    update_env "APACHE_ACTIVE" "apache"

    local CONFIG_FILE="$CONFIG_APACHE"

    if [[ "$ENABLE_REDIRECTION" == "y" ]]; then
      generate_conf_from_template "$base_template_path/redirect.nginx.conf" "$CONFIG_NGINX"
    elif [[ "$KEEP_HTTP" == "y" || "$ENABLE_HTTPS" == "n" ]]; then
      generate_conf_from_template "$base_template_path/proxy-http.nginx.conf" "$CONFIG_NGINX"
      generate_conf_from_template "$base_template_path/http.apache.conf" "$CONFIG_FILE"
    fi

    if [[ "$ENABLE_HTTPS" == "y" ]]; then
      generate_conf_from_template "$base_template_path/proxy-https.nginx.conf" "$CONFIG_NGINX"
      generate_conf_from_template "$base_template_path/https.apache.conf" "$CONFIG_FILE"
      certify
    fi

    chmod 644 "$CONFIG_NGINX" "$CONFIG_FILE"
  else
    echo -e "${RED}Invalid server type: $SERVER_TYPE${NC}"
    return 1
  fi

  if [[ "$APP_TYPE" == "php" ]]; then
    update_env "ACTIVE_PHP_PROFILE" "${PHP_CONTAINER_PROFILE}"
    update_env "ACTIVE_NODE_PROFILE" ""
  else
    update_env "ACTIVE_PHP_PROFILE" ""
  fi

  echo -e "\n${GREEN}Configuration for ${DOMAIN_NAME} has been saved.${NC}"
}

###############################################################################
# UI flow
###############################################################################
show_step() {
  echo -ne "${YELLOW}Step $1 of $2: ${NC}"
}

configure_server() {
  require_versions_db

  show_step 1 9
  prompt_for_domain

  show_step 2 9
  choose_app_type

  if [[ "$APP_TYPE" == "php" ]]; then
    show_step 3 9
    choose_server_type
  else
    SERVER_TYPE="Nginx"
    echo -e "${GREEN}Node uses Nginx proxy mode.${NC}"
  fi

  show_step 4 9
  prompt_for_http_https

  show_step 5 9
  prompt_for_doc_root

  show_step 6 9
  prompt_for_client_max_body_size

  show_step 7 9
  if [[ "$APP_TYPE" == "php" ]]; then
    prompt_for_php_version
  else
    prompt_for_node_version
    show_step 9 9
    prompt_for_node_command
  fi

  if [[ "$ENABLE_HTTPS" == "y" ]]; then
    prompt_for_client_verification
  else
    ENABLE_CLIENT_VERIFICATION="ssl_verify_client off;"
  fi

  if [[ "$APP_TYPE" == "node" ]]; then
    create_node_compose
  fi

  create_configuration
}

###############################################################################
# CLI flags
###############################################################################
case "$1" in
"--RESET")
  update_env "APACHE_ACTIVE" ""
  update_env "ACTIVE_PHP_PROFILE" ""
  update_env "ACTIVE_NODE_PROFILE" ""
  ;;
"--ACTIVE_PHP_PROFILE")
  get_env "ACTIVE_PHP_PROFILE"
  ;;
"--ACTIVE_NODE_PROFILE")
  get_env "ACTIVE_NODE_PROFILE"
  ;;
"--APACHE_ACTIVE")
  get_env "APACHE_ACTIVE"
  ;;
*)
  configure_server
  unset "DOMAIN_NAME" "APP_TYPE" "SERVER_TYPE" "ENABLE_HTTPS" "ENABLE_REDIRECTION" \
    "KEEP_HTTP" "DOC_ROOT" "CLIENT_MAX_BODY_SIZE" "CLIENT_MAX_BODY_SIZE_APACHE" \
    "ENABLE_CLIENT_VERIFICATION" "PHP_CONTAINER_PROFILE" "PHP_CONTAINER" \
    "PHP_APACHE_CONTAINER_PROFILE" "PHP_APACHE_CONTAINER" "APACHE_CONTAINER" \
    "NODE_VERSION" "NODE_CMD" "NODE_PROFILE" "NODE_SERVICE" "NODE_CONTAINER"
  ;;
esac
