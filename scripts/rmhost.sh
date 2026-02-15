#!/usr/bin/env bash
# rmhost - remove vhost configs for domain(s) (nginx/apache/node) and track delete intents in ENV_STORE
set -euo pipefail

###############################################################################
# UI
###############################################################################
BOLD=$'\033[1m'
DIM=$'\033[2m'
RED=$'\033[1;31m'
GREEN=$'\033[1;32m'
CYAN=$'\033[1;36m'
YELLOW=$'\033[1;33m'
NC=$'\033[0m'

say()  { echo -e "$*"; }
ok()   { say "${GREEN}${BOLD}$*${NC}"; }
warn() { say "${YELLOW}${BOLD}$*${NC}"; }
err()  { say "${RED}${BOLD}$*${NC}"; }
die()  { err "Error: $*"; exit 1; }

trim() { echo "${1:-}" | xargs; }

###############################################################################
# Paths / env store
###############################################################################
VHOST_ROOT="${VHOST_ROOT:-/etc/share/vhosts}"
NGINX_DIR="${NGINX_DIR:-${VHOST_ROOT}/nginx}"
APACHE_DIR="${APACHE_DIR:-${VHOST_ROOT}/apache}"
NODE_DIR="${NODE_DIR:-${VHOST_ROOT}/node}"

ENV_STORE="${ENV_STORE:-/etc/environment}"

###############################################################################
# ENV helpers (same style as mkhost)
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

env_add_csv_unique() {
  # env_add_csv_unique KEY VALUE  => append VALUE to KEY as comma-list (unique)
  local key="$1" value="$2"
  value="$(trim "$value")"
  [[ -n "$value" ]] || return 0

  local cur; cur="$(trim "$(env_get "$key")")"
  if [[ -z "$cur" ]]; then
    env_set "$key" "$value"
    return 0
  fi

  local IFS=',' x
  for x in $cur; do
    x="$(trim "$x")"
    [[ "$x" == "$value" ]] && return 0
  done

  env_set "$key" "${cur},${value}"
}

###############################################################################
# Helpers
###############################################################################
validate_domain() {
  local d="$1"
  local re='^([a-zA-Z0-9]([-a-zA-Z0-9]{0,61}[a-zA-Z0-9])?\.)+(localhost|local|test|loc|[a-zA-Z]{2,})$'
  [[ "$d" =~ $re ]]
}

slugify() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/_/g; s/^_+|_+$//g'
}

confirm_default_n() {
  local prompt="$1" ans=""
  # prints exactly once:  "<prompt> (y/N): "
  printf "%b%b%s%b %b(y/%bN%b): %b" \
    "$CYAN" "$BOLD" "$prompt" "$NC" \
    "$YELLOW" "$BOLD" "$NC" \
    "$NC"
  read -r ans
  ans="$(trim "$ans")"; ans="${ans,,}"
  [[ "$ans" == "y" || "$ans" == "yes" ]]
}

###############################################################################
# Domain selection (MULTI, LIST-ONLY)
###############################################################################
list_nginx_domains() {
  # Alpine/BusyBox safe: no find -printf
  [[ -d "$NGINX_DIR" ]] || return 0

  local f base
  shopt -s nullglob 2>/dev/null || true

  for f in "$NGINX_DIR"/*.conf; do
    [[ -f "$f" ]] || continue
    base="$(basename "$f")"
    base="${base%.conf}"
    [[ -n "$base" ]] && printf '%s\n' "$base"
  done | LC_ALL=C sort -u
}

load_domain_list() {
  DOM_LIST=()
  local line
  while IFS= read -r line; do
    [[ -n "$line" ]] && DOM_LIST+=("$line")
  done < <(list_nginx_domains || true)
}

parse_domain_input() {
  local input="$1"
  input="$(trim "$input")"
  PICKED_DOMAINS=()
  [[ -n "$input" ]] || return 1

  # normalize: commas -> spaces, collapse multiple spaces
  input="${input//,/ }"
  input="$(echo "$input" | xargs)"

  local tok
  for tok in $input; do
    tok="$(trim "$tok")"
    [[ -n "$tok" ]] || continue

    [[ "$tok" =~ ^[0-9]+$ ]] || return 1

    local idx=$((tok-1))
    (( idx >= 0 && idx < ${#DOM_LIST[@]} )) || return 1
    PICKED_DOMAINS+=("${DOM_LIST[$idx]}")
  done

  # dedupe preserve order
  local seen="|" out=() d
  for d in "${PICKED_DOMAINS[@]}"; do
    if [[ "$seen" != *"|$d|"* ]]; then
      seen="${seen}${d}|"
      out+=("$d")
    fi
  done
  PICKED_DOMAINS=("${out[@]}")
  ((${#PICKED_DOMAINS[@]} > 0))
}

pick_domains_interactive() {
  load_domain_list

  if ((${#DOM_LIST[@]} == 0)); then
    warn "No domains found in: ${NGINX_DIR}"
    warn "Nothing to delete."
    exit 2
  fi

  say "${CYAN}${BOLD}Available domains (from nginx):${NC}"
  local i
  for ((i=0; i<${#DOM_LIST[@]}; i++)); do
    printf "  %2d) %s\n" $((i+1)) "${DOM_LIST[i]}"
  done

  local ans=""
  while true; do
    read -r -p "$(printf "%bSelect domain(s) (e.g. 1,2,6 or 1 2 6):%b " "$CYAN" "$NC")" ans
    ans="$(trim "$ans")"
    [[ -n "$ans" ]] || { err "Selection cannot be empty."; continue; }

    # allow digits, commas, spaces only
    [[ "$ans" =~ ^[0-9,\ ]+$ ]] || { err "Only numbers, commas, spaces allowed."; continue; }

    parse_domain_input "$ans" || { err "Invalid selection."; continue; }
    DOMAINS=("${PICKED_DOMAINS[@]}")
    return 0
  done
}

###############################################################################
# PHP profile inference + reference scan (STRICT)
###############################################################################
extract_php_version_from_file() {
  local f="$1"
  [[ -r "$f" ]] || return 0
  grep -Eo 'PHP_[0-9]+\.[0-9]+' "$f" 2>/dev/null | head -n1 | sed -E 's/^PHP_//' || true
}

php_profile_from_version() {
  local v="$1"
  [[ "$v" =~ ^[0-9]+\.[0-9]+$ ]] || { echo ""; return 0; }
  echo "php${v//./}"
}

any_vhost_references_php_version() {
  local ver="$1"
  [[ -n "$ver" ]] || return 1
  local pat="PHP_${ver}"
  [[ -d "$NGINX_DIR"  ]] && grep -R -n -F "$pat" "$NGINX_DIR"  >/dev/null 2>&1 && return 0
  [[ -d "$APACHE_DIR" ]] && grep -R -n -F "$pat" "$APACHE_DIR" >/dev/null 2>&1 && return 0
  return 1
}

apache_has_any_vhosts() {
  [[ -d "$APACHE_DIR" ]] || return 1
  for f in "$APACHE_DIR"/*.conf; do
    [[ -f "$f" ]] && return 0
  done
  return 1
}

###############################################################################
# Plan build (batch) and execution
###############################################################################
# Plan rows: domain<TAB>token<TAB>nginx_conf<TAB>apache_conf<TAB>node_yaml<TAB>php_ver<TAB>del_nginx<TAB>del_apache<TAB>del_node
build_plan_for_domain() {
  local domain="$1"
  validate_domain "$domain" || { warn "Skipping invalid domain: $domain"; return 3; }

  local token; token="$(slugify "$domain")"
  local nginx_conf="${NGINX_DIR}/${domain}.conf"
  local apache_conf="${APACHE_DIR}/${domain}.conf"
  local node_yaml="${NODE_DIR}/${token}.yaml"

  local del_nginx="n" del_apache="n" del_node="n"
  [[ -e "$nginx_conf"  ]] && del_nginx="y"
  [[ -e "$apache_conf" ]] && del_apache="y"
  [[ -e "$node_yaml"   ]] && del_node="y"

  if [[ "$del_nginx$del_apache$del_node" == "nnn" ]]; then
    warn "Nothing to delete for ${domain}"
    return 2
  fi

  local php_ver=""
  [[ "$del_nginx" == "y"  ]] && php_ver="$(extract_php_version_from_file "$nginx_conf"  || true)"
  [[ -z "$php_ver" && "$del_apache" == "y" ]] && php_ver="$(extract_php_version_from_file "$apache_conf" || true)"

  printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
    "$domain" "$token" "$nginx_conf" "$apache_conf" "$node_yaml" "$php_ver" "$del_nginx" "$del_apache" "$del_node"
}

print_plan() {
  local plan="$1"
  say "${CYAN}${BOLD}Planned deletions:${NC}"
  while IFS=$'\t' read -r domain token nginx_conf apache_conf node_yaml php_ver del_nginx del_apache del_node; do
    say "${YELLOW}- ${domain}${NC} ${DIM}(token=${token})${NC}"
    [[ "$del_nginx"  == "y" ]] && say "   ${DIM}- ${nginx_conf}${NC}"
    [[ "$del_apache" == "y" ]] && say "   ${DIM}- ${apache_conf}${NC}"
    [[ "$del_node"   == "y" ]] && say "   ${DIM}- ${node_yaml}${NC}"
  done <"$plan"
  echo
}

execute_plan() {
  local plan="$1"

  env_set "APACHE_DELETE" ""
  env_set "DELETE_PHP_PROFILE" ""
  env_set "DELETE_NODE_PROFILE" ""

  while IFS=$'\t' read -r domain token nginx_conf apache_conf node_yaml php_ver del_nginx del_apache del_node; do
    say "${CYAN}${BOLD}Deleting:${NC} ${BOLD}${domain}${NC}"

    if [[ "$del_nginx" == "y" ]]; then
      rm -f -- "$nginx_conf"
      ok "  ✔ Deleted domain configuration"
    fi

    if [[ "$del_apache" == "y" ]]; then
      rm -f -- "$apache_conf"
    fi

    if [[ "$del_node" == "y" ]]; then
      rm -f -- "$node_yaml"
      env_add_csv_unique "DELETE_NODE_PROFILE" "node_${token}"
    fi

    if [[ -n "$php_ver" ]]; then
      local php_profile; php_profile="$(php_profile_from_version "$php_ver")"
      if [[ -n "$php_profile" ]] && ! any_vhost_references_php_version "$php_ver"; then
        env_add_csv_unique "DELETE_PHP_PROFILE" "$php_profile"
      fi
    fi

    echo
  done <"$plan"

  # If there is no apache vhost conf left -> request removing apache profile.
  if ! apache_has_any_vhosts; then
    env_set "APACHE_DELETE" "apache"
  else
    env_set "APACHE_DELETE" ""
  fi
}

###############################################################################
# CLI flags (requested)
###############################################################################
case "${1:-}" in
--RESET)
  env_set "APACHE_DELETE" ""
  env_set "DELETE_PHP_PROFILE" ""
  env_set "DELETE_NODE_PROFILE" ""
  ok "Reset done."
  ;;
--DELETE_PHP_PROFILE)  env_get "DELETE_PHP_PROFILE" ;;
--DELETE_NODE_PROFILE) env_get "DELETE_NODE_PROFILE" ;;
--APACHE_DELETE)       env_get "APACHE_DELETE" ;;
*)
  plan="$(mktemp)"
  DOMAINS=()

  if (($# == 0)); then
    pick_domains_interactive
  else
    # args mode still supported, but your main flow is list-only when no args.
    raw="$*"
    raw="${raw//,/ }"
    raw="$(trim "$raw")"
    for d in $raw; do
      d="$(trim "$d")"
      [[ -n "$d" ]] && DOMAINS+=("$d")
    done
  fi

  ((${#DOMAINS[@]} > 0)) || die "No domain selected."

  for d in "${DOMAINS[@]}"; do
    d="$(trim "$d")"
    [[ -n "$d" ]] || continue
    build_plan_for_domain "$d" >>"$plan" || true
  done

  if [[ ! -s "$plan" ]]; then
    rm -f "$plan"
    warn "Nothing to delete."
    exit 2
  fi

  print_plan "$plan"
  confirm_default_n "Proceed to delete ALL planned domains?" || { warn "Cancelled."; rm -f "$plan"; exit 0; }

  execute_plan "$plan"
  rm -f "$plan"

  ok "Done."
  ;;
esac
