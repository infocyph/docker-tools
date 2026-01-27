#!/bin/bash

# Define colors
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

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
    DOMAIN_NAME=$(echo "$DOMAIN_NAME" | xargs)
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
  # domain -> safe token for service/container names
  # example.com -> example_com
  echo "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/_/g; s/^_+|_+$//g'
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

###############################################################################
# App type
###############################################################################
choose_app_type() {
  echo -e "${CYAN}Choose app type:${NC}"
  PS3="$(echo -e "${YELLOW}👉 Select app type: ${NC}") "
  select app_type in "PHP (FastCGI)" "Node (Reverse proxy)"; do
    case "$app_type" in
    "PHP (FastCGI)")
      APP_TYPE="php"
      echo -e "${GREEN}Selected: PHP${NC}"
      break
      ;;
    "Node (Reverse proxy)")
      APP_TYPE="node"
      echo -e "${GREEN}Selected: Node${NC}"
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
      SERVER_TYPE=$server_type
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
# PHP bits
###############################################################################
prompt_for_php_version() {
  echo -e "${CYAN}Choose the PHP version:${NC}"
  PS3="$(echo -e "${YELLOW}👉 Select PHP version: ${NC}") "
  local PHP_VERSION
  select PHP_VERSION in "8.5" "8.4" "8.3" "8.2" "8.1" "8.0" "7.4" "7.3"; do
    if [[ -n "$PHP_VERSION" ]]; then
      PHP_CONTAINER_PROFILE="php${PHP_VERSION//./}"
      PHP_APACHE_CONTAINER_PROFILE="php${PHP_VERSION//./}apache"
      PHP_CONTAINER="PHP_${PHP_VERSION}"
      PHP_APACHE_CONTAINER="PHP_${PHP_VERSION}_APACHE"
      echo -e "${GREEN}You have selected PHP version $PHP_VERSION.${NC}"
      break
    fi
    echo -e "${RED}Invalid option, please select again.${NC}"
  done
}

###############################################################################
# Node bits
###############################################################################
prompt_for_node_version() {
  echo -e "${CYAN}Choose the Node version (image tag):${NC}"
  PS3="$(echo -e "${YELLOW}👉 Select Node version: ${NC}") "
  local v
  select v in "current" "22" "20" "18"; do
    if [[ -n "$v" ]]; then
      NODE_VERSION="$v"
      echo -e "${GREEN}Selected Node version: $NODE_VERSION${NC}"
      break
    fi
    echo -e "${RED}Invalid option, please select again.${NC}"
  done
}

prompt_for_node_port() {
  read -e -r -p "$(echo -e "${CYAN}Node app port inside container (default 3000):${NC} ")" NODE_PORT
  NODE_PORT="${NODE_PORT:-3000}"
  while [[ ! "$NODE_PORT" =~ ^[0-9]+$ ]] || ((NODE_PORT < 1 || NODE_PORT > 65535)); do
    echo -e "${RED}Invalid port. Enter 1-65535.${NC}"
    read -e -r NODE_PORT
  done
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
    -e "s|{{NODE_PORT}}|${NODE_PORT:-}|g" \
    "$template_file" >>"$output_file"
}

###############################################################################
# Node dynamic compose generator
###############################################################################
create_node_compose() {
  mkdir -p /etc/share/vhosts/node

  local token domain_token svc cname profile
  domain_token="$(slugify "$DOMAIN_NAME")"
  token="${NODE_DIR_TOKEN:-$domain_token}"

  svc="node_${token}"
  cname="NODE_${token^^}"
  profile="node_${token}"

  NODE_SERVICE="$svc"
  NODE_CONTAINER="$svc"
  NODE_PROFILE="$profile"

  local CONFIG_DOCKER_NODE="/etc/share/vhosts/node/${token}.yaml"
  rm -f "$CONFIG_DOCKER_NODE"

  cat >"$CONFIG_DOCKER_NODE" <<YAML
services:
  ${svc}:
    container_name: ${cname}
    hostname: ${svc}
    build:
      context: ../dockerfiles
      dockerfile: node.Dockerfile
      args:
        UID: \${UID:-1000}
        GID: \${GID:-1000}
        USERNAME: \${USER}
        NODE_VERSION: ${NODE_VERSION}
        LINUX_PKG: \${LINUX_PKG:-}
        LINUX_PKG_VERSIONED: \${LINUX_PKG_${NODE_VERSION}:-}
        NODE_GLOBAL: \${NODE_GLOBAL:-}
        NODE_GLOBAL_VERSIONED: \${NODE_GLOBAL_${NODE_VERSION}:-}
    environment:
      - TZ=\${TZ:-}
      - PORT=${NODE_PORT}
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
      test: ["CMD-SHELL", "node -e \"const net=require('net');const p=process.env.PORT||${NODE_PORT};const s=net.connect(p,'127.0.0.1');s.on('connect',()=>process.exit(0));s.on('error',()=>process.exit(1));\""]
      interval: 30s
      timeout: 5s
      retries: 5
    profiles: ["node","${profile}"]
YAML

  chmod 644 "$CONFIG_DOCKER_NODE"

  update_env "ACTIVE_NODE_PROFILE" "$profile"

  echo -e "${GREEN}Node compose generated:${NC} $CONFIG_DOCKER_NODE"
  echo -e "${GREEN}Node service:${NC} $svc  ${GREEN}profile:${NC} $profile  ${GREEN}port:${NC} $NODE_PORT"
}

###############################################################################
# Create configs
###############################################################################
create_configuration() {
  local CONFIG_NGINX="/etc/share/vhosts/nginx/${DOMAIN_NAME}.conf"
  local CONFIG_APACHE="/etc/share/vhosts/apache/${DOMAIN_NAME}.conf"
  local base_template_path="/etc/http-templates"

  rm -f "$CONFIG_NGINX" "$CONFIG_APACHE"

  # Default
  ENABLE_CLIENT_VERIFICATION="${ENABLE_CLIENT_VERIFICATION:-ssl_verify_client off;}"

  if [[ "$APP_TYPE" == "node" ]]; then
    SERVER_TYPE="Nginx" # Node always via Nginx proxy in your model
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
  # total steps vary by type, keep it simple & readable
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

  if [[ "$APP_TYPE" == "php" ]]; then
    show_step 7 9
    prompt_for_php_version
  else
    show_step 7 9
    prompt_for_node_version
    show_step 8 9
    prompt_for_node_port
    show_step 9 9
    prompt_for_node_command
  fi

  if [[ "$ENABLE_HTTPS" == "y" ]]; then
    prompt_for_client_verification
  else
    ENABLE_CLIENT_VERIFICATION="ssl_verify_client off;"
  fi

  # Node needs compose data BEFORE rendering templates (to fill {{NODE_CONTAINER}}/{{NODE_PORT}})
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
    "NODE_VERSION" "NODE_PORT" "NODE_CMD" "NODE_PROFILE" "NODE_SERVICE" "NODE_CONTAINER"
  ;;
esac
