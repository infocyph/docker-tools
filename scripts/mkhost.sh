#!/bin/bash

# Define colors
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

function validate_domain() {
  local domain=$1
  local regex="^([a-zA-Z0-9][-a-zA-Z0-9]{0,253}[a-zA-Z0-9]\.)+[a-zA-Z]{2,}$"

  if [[ ! $domain =~ $regex ]]; then
    echo -e "${RED}Invalid domain name:${NC} $domain"
    return 1
  fi
  return 0
}

function prompt_for_domain() {
  while true; do
    read -e -r -p "$(echo -e "${CYAN}Enter the domain (e.g., example.com):${NC} ")" DOMAIN_NAME
    DOMAIN_NAME=$(echo "$DOMAIN_NAME" | xargs)  # Trim spaces
    if validate_domain "$DOMAIN_NAME"; then
      break
    else
      echo -e "${YELLOW}Please enter a valid domain name.${NC}"
    fi
  done
}

function validate_input() {
  local input="$1"
  local message="$2"
  while [[ -z "$input" ]]; do
    echo -e "${RED}${message}${NC}"
    read -e -r input
  done
  echo "$input"
}

function choose_server_type() {
  echo -e "${CYAN}Choose the server to configure:${NC}"
  PS3="$(echo -e "${YELLOW}👉 Select server type: ${NC}") "
  select server_type in "Nginx" "Apache"; do
    if [[ "$server_type" == "Nginx" || "$server_type" == "Apache" ]]; then
      SERVER_TYPE=$server_type
      echo -e "${GREEN}You have selected $server_type.${NC}"
      break
    else
      echo -e "${RED}Invalid option, please select again.${NC}"
    fi
  done
}

function prompt_for_http_https() {
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
      ENABLE_REDIRECTION=${ENABLE_REDIRECTION,,} # normalize to lowercase
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

function prompt_for_client_verification() {
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

function prompt_for_doc_root() {
  read -e -r -p "$(echo -e "${CYAN}Enter the relative DocumentRoot (e.g., /site/public):${NC} ")" DOC_ROOT
  DOC_ROOT=$(validate_input "$DOC_ROOT" "DocumentRoot cannot be empty. Please enter a valid DocumentRoot:")
  DOC_ROOT=$(echo "$DOC_ROOT" | xargs)
}

function prompt_for_client_max_body_size() {
  read -e -r -p "$(echo -e "${CYAN}Enter the maximum client body size (MB, default 10):${NC} ")" CLIENT_MAX_BODY_SIZE
  CLIENT_MAX_BODY_SIZE=${CLIENT_MAX_BODY_SIZE:-10}

  while [[ ! "$CLIENT_MAX_BODY_SIZE" =~ ^[0-9]+$ ]]; do
    echo -e "${RED}Invalid input. Please enter a valid number (e.g., 12):${NC}"
    read -e -r CLIENT_MAX_BODY_SIZE
  done

  CLIENT_MAX_BODY_SIZE_APACHE=$((CLIENT_MAX_BODY_SIZE * 1000000))
  CLIENT_MAX_BODY_SIZE="${CLIENT_MAX_BODY_SIZE}M"
}

function prompt_for_php_version() {
  echo -e "${CYAN}Choose the PHP version:${NC}"
  PS3="$(echo -e "${YELLOW}👉 Select PHP version: ${NC}") "
  local PHP_VERSION
  select PHP_VERSION in "7.3" "7.4" "8.0" "8.1" "8.2" "8.3" "8.4"; do
    if [[ -n "$PHP_VERSION" ]]; then
      PHP_CONTAINER_PROFILE="php${PHP_VERSION//./}"
      PHP_APACHE_CONTAINER_PROFILE="php${PHP_VERSION//./}apache"
      PHP_CONTAINER="PHP_${PHP_VERSION}"
      PHP_APACHE_CONTAINER="PHP_${PHP_VERSION}_APACHE"
      echo -e "${GREEN}You have selected PHP version $PHP_VERSION.${NC}"
      break
    else
      echo -e "${RED}Invalid option, please select again.${NC}"
    fi
  done
}

function generate_conf_from_template() {
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
      "$template_file" >>"$output_file"
}

update_env() {
  local key="$1" value="$2"
  sed -i "s|^${key}=.*|${key}=${value}|" "/etc/environment"
}

function create_configuration() {
  local CONFIG_NGINX="/etc/share/vhosts/nginx/${DOMAIN_NAME}.conf"
  local CONFIG_APACHE="/etc/share/vhosts/apache/${DOMAIN_NAME}.conf"
  local CONFIG_FILE
  local base_template_path="/etc/http-templates"

  rm -f "$CONFIG_NGINX" "$CONFIG_APACHE"

  if [[ "$SERVER_TYPE" == "Nginx" ]]; then
    CONFIG_FILE=$CONFIG_NGINX
  elif [[ "$SERVER_TYPE" == "Apache" ]]; then
    CONFIG_FILE=$CONFIG_APACHE
    update_env "APACHE_ACTIVE" "apache"
  else
    echo -e "${RED}Invalid server type: $SERVER_TYPE${NC}"
    return 1
  fi
  if [[ "$ENABLE_REDIRECTION" == "y" ]]; then
    generate_conf_from_template "$base_template_path/redirect.nginx.conf" "$CONFIG_NGINX"
  elif [[ "$KEEP_HTTP" == "y" || "$ENABLE_HTTPS" == "n" ]]; then
    [[ "$SERVER_TYPE" == "Apache" ]] && generate_conf_from_template "$base_template_path/proxy-http.nginx.conf" "$CONFIG_NGINX"
    generate_conf_from_template "$base_template_path/http.${SERVER_TYPE,,}.conf" "$CONFIG_FILE"
  fi

  if [[ "$ENABLE_HTTPS" == "y" ]]; then
    [[ "$SERVER_TYPE" == "Apache" ]] && generate_conf_from_template "$base_template_path/proxy-https.nginx.conf" "$CONFIG_NGINX"
    generate_conf_from_template "$base_template_path/https.${SERVER_TYPE,,}.conf" "$CONFIG_FILE"
    certify
  fi

  [ -f "$CONFIG_NGINX" ] && chmod 644 "$CONFIG_NGINX"
  [ -f "$CONFIG_FILE" ] && chmod 644 "$CONFIG_FILE"
  update_env "ACTIVE_PHP_PROFILE" "${PHP_CONTAINER_PROFILE}"

  echo -e "\n${GREEN}Configuration for ${DOMAIN_NAME} has been saved.${NC}"
}

function show_step() {
  echo -ne "${YELLOW}Step $1 of $2: ${NC}"
}

get_env() {
  grep -E "^$1=" /etc/environment | cut -d'=' -f2-
}

function configure_server() {
  show_step 1 7
  prompt_for_domain
  show_step 2 7
  choose_server_type
  show_step 3 7
  prompt_for_http_https
  show_step 4 7
  prompt_for_doc_root
  show_step 5 7
  prompt_for_client_max_body_size
  show_step 6 7
  prompt_for_php_version

  if [[ "$ENABLE_HTTPS" == "y" ]]; then
    show_step 7 7
    prompt_for_client_verification
  else
    ENABLE_CLIENT_VERIFICATION="n"
  fi

  create_configuration
}

case "$1" in
  "--RESET")
    update_env "APACHE_ACTIVE" ""
    update_env "ACTIVE_PHP_PROFILE" ""
    ;;
  "--ACTIVE_PHP_PROFILE")
    get_env "ACTIVE_PHP_PROFILE"
    ;;
  "--APACHE_ACTIVE")
    get_env "APACHE_ACTIVE"
    ;;
  *)
    configure_server
    unset "$DOMAIN_NAME" "$SERVER_TYPE" "$ENABLE_HTTPS" "$ENABLE_REDIRECTION" \
          "$KEEP_HTTP" "$DOC_ROOT" "$CLIENT_MAX_BODY_SIZE" "CLIENT_MAX_BODY_SIZE_APACHE" "$ENABLE_CLIENT_VERIFICATION" \
          "$PHP_CONTAINER_PROFILE" "$PHP_CONTAINER" "$PHP_APACHE_CONTAINER_PROFILE" "$PHP_APACHE_CONTAINER" "$APACHE_CONTAINER"
    ;;
esac
