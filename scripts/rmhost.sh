#!/usr/bin/env bash
# delhost - remove vhost configs for domain(s) (nginx/apache/node) and track delete intents in ENV_STORE
set -euo pipefail

###############################################################################
# UI
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

env_get() {
  grep -E "^$1=" "$ENV_STORE" 2>/dev/null | cut -d'=' -f2- || true
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
  read -r -p "$(printf "%b%s (y/N): %b" "$YELLOW" "$prompt" "$NC")" ans
  ans="$(trim "$ans")"; ans="${ans,,}"
  [[ "$ans" == "y" || "$ans" == "yes" ]]
}

###############################################################################
# Domain selection
###############################################################################
list_nginx_domains() {
  [[ -d "$NGINX_DIR" ]] || return 0
  find "$NGINX_DIR" -maxdepth 1 -type f -name '*.conf' -printf '%f\n' 2>/dev/null \
    | sed -E 's/\.conf$//' \
    | LC_ALL=C sort -u
}

pick_domain_interactive() {
  local domains=() line
  while IFS= read -r line; do
    [[ -n "$line" ]] && domains+=("$line")
  done < <(list_nginx_domains || true)

  if ((${#domains[@]} == 0)); then
    local d=""
    read -r -p "$(printf "%bEnter domain to delete:%b " "$CYAN" "$NC")" d
    echo "$(trim "$d")"
    return 0
  fi

  say "${CYAN}Available domains (from nginx):${NC}"
  local i
  for ((i=0; i<${#domains[@]}; i++)); do
    printf "  %2d) %s\n" $((i+1)) "${domains[i]}"
  done

  local ans=""
  while true; do
    read -r -p "$(printf "%bSelect domain (1-%d) or type domain:%b " "$CYAN" "${#domains[@]}" "$NC")" ans
    ans="$(trim "$ans")"
    [[ -n "$ans" ]] || { err "Input cannot be empty."; continue; }

    if [[ "$ans" =~ ^[0-9]+$ ]]; then
      local idx=$((ans-1))
      (( idx >= 0 && idx < ${#domains[@]} )) || { err "Out of range."; continue; }
      echo "${domains[idx]}"
      return 0
    fi

    echo "$ans"
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
  find "$APACHE_DIR" -maxdepth 1 -type f -name '*.conf' -print -quit 2>/dev/null | grep -q .
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
  # input: plan file
  local plan="$1"
  say "${CYAN}Planned deletions:${NC}"
  while IFS=$'\t' read -r domain token nginx_conf apache_conf node_yaml php_ver del_nginx del_apache del_node; do
    say "${YELLOW}- ${domain}${NC} ${CYAN}(token=${token})${NC}"
    [[ "$del_nginx"  == "y" ]] && say "   - $nginx_conf"
    [[ "$del_apache" == "y" ]] && say "   - $apache_conf"
    [[ "$del_node"   == "y" ]] && say "   - $node_yaml"
  done <"$plan"
}

execute_plan() {
  local plan="$1"

  # Clear delete envs for this run; then set based on what actually got deleted
  env_set "APACHE_DELETE" ""
  env_set "DELETE_PHP_PROFILE" ""
  env_set "DELETE_NODE_PROFILE" ""

  local any_apache_deleted="n"

  while IFS=$'\t' read -r domain token nginx_conf apache_conf node_yaml php_ver del_nginx del_apache del_node; do
    say "${CYAN}Deleting:${NC} ${domain}"

    if [[ "$del_nginx" == "y" ]]; then
      rm -f -- "$nginx_conf"
      ok "Deleted: $nginx_conf"
    fi

    if [[ "$del_apache" == "y" ]]; then
      rm -f -- "$apache_conf"
      ok "Deleted: $apache_conf"
      any_apache_deleted="y"
    fi

    if [[ "$del_node" == "y" ]]; then
      rm -f -- "$node_yaml"
      ok "Deleted: $node_yaml"
      env_set "DELETE_NODE_PROFILE" "node_${token}"
    fi

    if [[ -n "$php_ver" ]]; then
      local php_profile; php_profile="$(php_profile_from_version "$php_ver")"
      if [[ -n "$php_profile" ]] && ! any_vhost_references_php_version "$php_ver"; then
        env_set "DELETE_PHP_PROFILE" "$php_profile"
      fi
    fi
  done <"$plan"

  # APACHE_DELETE rule (after all deletes)
  if [[ "$any_apache_deleted" == "y" ]] && apache_has_any_vhosts; then
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
# MULTI-DOMAIN + BATCH CONFIRM:
# - If args present: treat each as a domain
# - If no args: interactive pick one domain
  plan="$(mktemp)"

  if (($# == 0)); then
    d="$(pick_domain_interactive)"
    d="$(trim "$d")"
    [[ -n "$d" ]] || die "No domain provided."
    build_plan_for_domain "$d" >>"$plan" || true
  else
    for d in "$@"; do
      d="$(trim "$d")"
      [[ -n "$d" ]] || continue
      build_plan_for_domain "$d" >>"$plan" || true
    done
  fi

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
  ok "APACHE_DELETE=$(env_get APACHE_DELETE)"
  ok "DELETE_NODE_PROFILE=$(env_get DELETE_NODE_PROFILE)"
  ok "DELETE_PHP_PROFILE=$(env_get DELETE_PHP_PROFILE)"
  ;;
esac
