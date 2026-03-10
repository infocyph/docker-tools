#!/usr/bin/env bash
# rmhost - remove vhost configs for domain(s) (nginx/apache/node)
#        - if no args: shows domain list from nginx and lets you select by numbers (1,2,6 / 1 2 6)
#        - deletes relevant nginx/apache/node files
#        - sets delete intents in ENV_STORE:
#            APACHE_DELETE, DELETE_PHP_PROFILE, DELETE_NODE_PROFILE
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
declare -a REMOVED_DOMAINS=()

###############################################################################
# Paths / env store
###############################################################################
VHOST_ROOT="${VHOST_ROOT:-/etc/share/vhosts}"
NGINX_DIR="${NGINX_DIR:-${VHOST_ROOT}/nginx}"
APACHE_DIR="${APACHE_DIR:-${VHOST_ROOT}/apache}"
NODE_DIR="${NODE_DIR:-${VHOST_ROOT}/node}"
FPM_DIR="${FPM_DIR:-${VHOST_ROOT}/fpm}"
ENV_STORE_JSON="${ENV_STORE_JSON:-/etc/share/state/env-store.json}"
RMHOST_STATE_KEY="${RMHOST_STATE_KEY:-RMHOST_STATE}"

###############################################################################
# ENV helpers (same style as mkhost)
###############################################################################
env_store_exec() {
  command -v env-store >/dev/null 2>&1 || die "Missing command: env-store"
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

rmhost_sync_state() {
  local ts php_del node_del apache_del domains_json state_json
  ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || true)"
  php_del="$(env_get "DELETE_PHP_PROFILE")"
  node_del="$(env_get "DELETE_NODE_PROFILE")"
  apache_del="$(env_get "APACHE_DELETE")"
  domains_json='[]'

  local d
  for d in "${REMOVED_DOMAINS[@]}"; do
    [[ -n "$d" ]] || continue
    domains_json="$(jq -cn --argjson arr "$domains_json" --arg v "$d" '$arr + [$v]')"
  done

  state_json="$(jq -cn \
    --arg ts "$ts" \
    --arg php_del "$php_del" \
    --arg node_del "$node_del" \
    --arg apache_del "$apache_del" \
    --argjson domains "$domains_json" \
    '{
      version: 1,
      updated_at: $ts,
      state: {
        delete_php_profile: $php_del,
        delete_node_profile: $node_del,
        apache_delete: $apache_del
      },
      deleted_domains: $domains
    }')"

  env_set_json "$RMHOST_STATE_KEY" "$state_json"
}

rmhost_get_state_json() {
  env_store_exec get-json "$RMHOST_STATE_KEY" --default-json '{}' || printf '{}\n'
}

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
  # single prompt line, default N
  read -r -p "$(printf "%b%b%s%b %b(y/%bN%b): %b" \
    "$CYAN" "$BOLD" "$prompt" "$NC" \
    "$YELLOW" "$BOLD" "$NC" \
    "$NC")" ans
  ans="$(trim "$ans")"; ans="${ans,,}"
  [[ "$ans" == "y" || "$ans" == "yes" ]]
}

###############################################################################
# Domain selection (MULTI, LIST from nginx)
###############################################################################
validate_domain() {
  local d="$1"
  local re='^([a-zA-Z0-9]([-a-zA-Z0-9]{0,61}[a-zA-Z0-9])?\.)+(localhost|local|test|loc|[a-zA-Z]{2,})$'
  [[ "$d" =~ $re ]]
}

list_nginx_domains() {
  [[ -d "$NGINX_DIR" ]] || return 0

  find "$NGINX_DIR" -maxdepth 1 -type f -name '*.conf' 2>/dev/null \
    -exec sh -c 'for f; do b="${f##*/}"; echo "${b%.conf}"; done' sh {} + \
    | LC_ALL=C sort -u
}

load_domain_list() {
  DOM_LIST=()
  local line
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    validate_domain "$line" || continue
    DOM_LIST+=("$line")
  done < <(list_nginx_domains || true)
}

parse_domain_input() {
  local input="$1"
  input="$(trim "$input")"
  PICKED_DOMAINS=()
  [[ -n "$input" ]] || return 1

  # normalize: commas -> spaces, collapse spaces
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
    [[ "$ans" =~ ^[0-9,\ ]+$ ]] || { err "Only numbers, commas, spaces allowed."; continue; }

    parse_domain_input "$ans" || { err "Invalid selection."; continue; }
    DOMAINS=("${PICKED_DOMAINS[@]}")
    return 0
  done
}

###############################################################################
# PHP profile inference + reference scan
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
# Plan build + execution
###############################################################################
# Plan rows: domain<TAB>token<TAB>nginx_conf<TAB>apache_conf<TAB>node_yaml<TAB>php_ver<TAB>del_nginx<TAB>del_apache<TAB>del_node
build_plan_for_domain() {
  local domain="$1"
  validate_domain "$domain" || { warn "Skipping invalid domain: $domain"; return 3; }

  local token; token="$(slugify "$domain")"
  local nginx_conf="${NGINX_DIR}/${domain}.conf"
  local apache_conf="${APACHE_DIR}/${domain}.conf"
  local node_yaml="${NODE_DIR}/${token}.yaml"
  local -a fpm_confs=()
  local f
  shopt -s nullglob
  for f in "${FPM_DIR}"/php*/"${domain}.conf"; do
    [[ -e "$f" ]] && fpm_confs+=("$f")
  done
  shopt -u nullglob
  local fpm_conf=""
  if ((${#fpm_confs[@]})); then
    # Comma-separated for plan transport
    fpm_conf="$(IFS=,; echo "${fpm_confs[*]}")"
  fi


  local del_nginx="n" del_apache="n" del_node="n" del_fpm="n"
  [[ -e "$nginx_conf"  ]] && del_nginx="y"
  [[ -e "$apache_conf" ]] && del_apache="y"
  [[ -e "$node_yaml"   ]] && del_node="y"
  [[ -e "$fpm_conf"   ]] && del_fpm="y"

  if [[ "$del_nginx$del_apache$del_node$del_fpm" == "nnnn" ]]; then
    warn "Nothing to delete for ${domain}"
    return 2
  fi

  local php_ver=""
  [[ "$del_nginx" == "y"  ]] && php_ver="$(extract_php_version_from_file "$nginx_conf"  || true)"
  [[ -z "$php_ver" && "$del_apache" == "y" ]] && php_ver="$(extract_php_version_from_file "$apache_conf" || true)"

  printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
    "$domain" "$token" "$nginx_conf" "$apache_conf" "$node_yaml" "$fpm_conf" "$php_ver" "$del_nginx" "$del_apache" "$del_node" "$del_fpm"
}

print_plan() {
  local plan="$1"
  say "${CYAN}${BOLD}Planned deletions:${NC}"
  while IFS=$'\t' read -r domain token nginx_conf apache_conf node_yaml fpm_conf php_ver del_nginx del_apache del_node del_fpm; do
    say "${YELLOW}- ${domain}${NC} ${DIM}(token=${token})${NC}"
    [[ "$del_nginx"  == "y" ]] && say "   ${DIM}- ${nginx_conf}${NC}"
    [[ "$del_apache" == "y" ]] && say "   ${DIM}- ${apache_conf}${NC}"
    [[ "$del_node"   == "y" ]] && say "   ${DIM}- ${node_yaml}${NC}"
        if [[ "$del_fpm" == "y" ]]; then
      IFS=',' read -r -a _fpm_list <<<"$fpm_conf"
      for _f in "${_fpm_list[@]}"; do
        [[ -n "$_f" ]] && say "   ${DIM}- ${_f}${NC}"
      done
    fi
  done <"$plan"
  echo
}

execute_plan() {
  local plan="$1"
  REMOVED_DOMAINS=()

  # Clear delete envs for this run
  env_set "APACHE_DELETE" ""
  env_set "DELETE_PHP_PROFILE" ""
  env_set "DELETE_NODE_PROFILE" ""

  while IFS=$'\t' read -r domain token nginx_conf apache_conf node_yaml fpm_conf php_ver del_nginx del_apache del_node del_fpm; do
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

    if [[ "$del_fpm" == "y" ]]; then
      rm -f -- "$fpm_conf"
    fi

    if [[ -n "$php_ver" ]]; then
      local php_profile; php_profile="$(php_profile_from_version "$php_ver")"
      if [[ -n "$php_profile" ]] && ! any_vhost_references_php_version "$php_ver"; then
        env_add_csv_unique "DELETE_PHP_PROFILE" "$php_profile"
      fi
    fi
    REMOVED_DOMAINS+=("$domain")

    echo
  done <"$plan"

  # If there is no apache vhost conf left -> request removing apache profile.
  if ! apache_has_any_vhosts; then
    env_set "APACHE_DELETE" "apache"
  else
    env_set "APACHE_DELETE" ""
  fi

  rmhost_sync_state
}

###############################################################################
# CLI flags (requested)
###############################################################################
case "${1:-}" in
--RESET)
  env_set "APACHE_DELETE" ""
  env_set "DELETE_PHP_PROFILE" ""
  env_set "DELETE_NODE_PROFILE" ""
  REMOVED_DOMAINS=()
  rmhost_sync_state
  ;;
--DELETE_PHP_PROFILE)  env_get "DELETE_PHP_PROFILE" ;;
--DELETE_NODE_PROFILE) env_get "DELETE_NODE_PROFILE" ;;
--APACHE_DELETE)       env_get "APACHE_DELETE" ;;
--JSON|--STATE_JSON)   rmhost_get_state_json ;;
*)
  plan="$(mktemp)"
  DOMAINS=()

  if (($# == 0)); then
    pick_domains_interactive
  else
    # args mode still supported (domains separated by spaces/commas)
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
