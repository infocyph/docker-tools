#!/usr/bin/env bash
set -euo pipefail

VHOST_NGINX_DIR="${VHOST_NGINX_DIR:-/etc/share/vhosts/nginx}"
MAX_HEADER_LINES="${MAX_HEADER_LINES:-120}"

###############################################################################
# Colors + UI (match mkhost.sh style)
###############################################################################
BOLD=$'\033[1m'
DIM=$'\033[2m'
RED=$'\033[1;31m'
GREEN=$'\033[1;32m'
CYAN=$'\033[1;36m'
YELLOW=$'\033[1;33m'
MAGENTA=$'\033[1;35m'
NC=$'\033[0m'

say() { echo -e "$*"; }
ok() { say "${GREEN}$*${NC}"; }
warn() { say "${YELLOW}$*${NC}"; }
err() { say "${RED}$*${NC}"; }

die() {
  err "Error: $*"
  exit 1
}

usage() {
  cat >&2 <<'EOF'
Usage:
  domain-which [--json] [--sock] [--pick] [--meta] [--app|--container|--profile|--docroot] [--quiet] [domain|docroot]
  domain-which --list
  domain-which --list-domains
  domain-which --list-directories
  domain-which --list-containers
  domain-which --list-profiles

Examples:
  domain-which web.localhost
  domain-which                 # auto-pick if only one domain exists
  domain-which /hot            # match by docroot
  domain-which --pick /hot     # pick if multiple domains share /hot
  domain-which --list
EOF
  exit 2
}

want_json=0
want_field=""
quiet=0
want_sock=0
want_pick=0
want_meta=0
mode="single" # single|list-domains|list-directories|list-containers|list-profiles|list

while [[ $# -gt 0 ]]; do
  case "$1" in
  --json)
    want_json=1
    shift
    ;;
  --sock)
    want_sock=1
    shift
    ;;
  --meta)
    want_meta=1
    shift
    ;;
  --pick)
    want_pick=1
    shift
    ;;
  --app)
    want_field="app"
    shift
    ;;
  --container)
    want_field="container"
    shift
    ;;
  --profile)
    want_field="profile"
    shift
    ;;
  --docroot | --dir)
    want_field="docroot"
    shift
    ;;
  --quiet)
    quiet=1
    shift
    ;;
  --list)
    mode="list"
    shift
    ;;
  --list-domains)
    mode="list-domains"
    shift
    ;;
  --list-directories | --list-dirs)
    mode="list-directories"
    shift
    ;;
  --list-containers)
    mode="list-containers"
    shift
    ;;
  --list-profiles)
    mode="list-profiles"
    shift
    ;;
  -h | --help) usage ;;
  --)
    shift
    break
    ;;
  -*) die "Unknown flag: $1" ;;
  *) break ;;
  esac
done

trim() { echo "${1:-}" | xargs; }

validate_domain() {
  local d="$1"
  local re='^([a-zA-Z0-9]([-a-zA-Z0-9]{0,61}[a-zA-Z0-9])?\.)+(localhost|local|test|loc|[a-zA-Z]{2,})$'
  [[ "$d" =~ $re ]]
}

is_pathish() {
  local s="${1:-}"
  [[ "$s" == /* ]] && return 0
  [[ "$s" == ./* || "$s" == ../* || "$s" == "." || "$s" == ".." ]] && return 0
  [[ "$s" == *"/"* ]] && return 0
  return 1
}

normalize_docroot() {
  local p
  p="$(trim "${1:-}")"
  [[ -n "$p" ]] || {
    echo ""
    return 0
  }
  [[ "$p" == /* ]] || p="/$p"
  while [[ "$p" == *"//"* ]]; do p="${p//\/\//\/}"; done
  [[ "$p" != "/" ]] && p="${p%/}"
  echo "$p"
}

list_vhost_domains() {
  [[ -d "$VHOST_NGINX_DIR" ]] || return 0
  local f base d
  shopt -s nullglob
  for f in "$VHOST_NGINX_DIR"/*.conf; do
    base="$(basename "$f")"
    d="${base%.conf}"
    validate_domain "$d" || continue
    echo "$d"
  done
  shopt -u nullglob
}

pick_default_domain_if_single() {
  local -a ds=()
  mapfile -t ds < <(list_vhost_domains | LC_ALL=C sort)
  if ((${#ds[@]} == 1)); then
    echo "${ds[0]}"
    return 0
  fi
  if ((${#ds[@]} == 0)); then
    die "No valid nginx vhosts found in: $VHOST_NGINX_DIR"
  fi
  die "Domain required (found ${#ds[@]} domains). Use --list-domains."
}

read_meta_from_conf() {
  local domain="$1"
  local conf="${VHOST_NGINX_DIR}/${domain}.conf"
  [[ -r "$conf" ]] || return 1

  local line i=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    i=$((i + 1))
    ((i <= MAX_HEADER_LINES)) || break
    [[ "$line" == \#* ]] || break
    if [[ "$line" =~ ^\#\ LDS-META:\ ([a-zA-Z0-9_]+)=(.*)$ ]]; then
      printf '%s=%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
    fi
  done <"$conf"
}

kv_get() { awk -F= -v k="$1" '$1==k{ sub(/^([^=]*=)/,""); print; exit }'; }

emit_meta_block_from_domain() {
  local domain="$1"
  local conf="${VHOST_NGINX_DIR}/${domain}.conf"
  [[ -r "$conf" ]] || die "Nginx vhost not found/readable: $conf"

  local line i=0 seen=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    i=$((i + 1))
    ((i <= MAX_HEADER_LINES)) || break
    [[ "$line" == \#* ]] || break

    if [[ "$line" =~ ^\#\ LDS-META:\  ]]; then
      seen=1
      printf '%s\n' "$line"
    elif ((seen)); then
      break
    fi
  done <"$conf"

  ((seen)) || die "Missing LDS-META header in: $conf"
}

emit_single_from_domain() {
  local domain="$1"
  validate_domain "$domain" || die "Invalid domain: $domain"

  local meta app docroot container profile sock_web sock_fpm
  meta="$(read_meta_from_conf "$domain" || true)"
  [[ -n "$meta" ]] || die "Missing or unreadable LDS-META header for: $domain"

  if ((want_meta)); then
    emit_meta_block_from_domain "$domain"
    return 0
  fi

  app="$(printf '%s\n' "$meta" | kv_get app)"
  docroot="$(printf '%s\n' "$meta" | kv_get docroot)"
  [[ -n "$app" ]] || die "Missing LDS-META: app= in $domain"

  case "$app" in
  php)
    container="$(printf '%s\n' "$meta" | kv_get php_container)"
    profile="$(printf '%s\n' "$meta" | kv_get php_profile)"
    ;;
  node)
    container="$(printf '%s\n' "$meta" | kv_get node_container)"
    profile="$(printf '%s\n' "$meta" | kv_get node_profile)"
    ;;
  *)
    container=""
    profile=""
    ;;
  esac

  sock_web="$(printf '%s\n' "$meta" | kv_get sock_web)"
  sock_fpm="$(printf '%s\n' "$meta" | kv_get sock_fpm)"

  if ((want_json)); then
    printf '{'
    printf '"domain":"%s","app":"%s","docroot":"%s","container":"%s","profile":"%s"' \
      "$domain" "$app" "${docroot:-}" "${container:-}" "${profile:-}"
    if ((want_sock)); then
      printf ',"sock_web":"%s","sock_fpm":"%s"' "${sock_web:-}" "${sock_fpm:-}"
    fi
    printf '}\n'
    return 0
  fi

  if ((want_sock)); then
    printf "%s\t%s\n" "${sock_web:-}" "${sock_fpm:-}"
    return 0
  fi

  if [[ -n "$want_field" ]]; then
    local v=""
    case "$want_field" in
    app) v="$app" ;;
    container) v="${container:-}" ;;
    profile) v="${profile:-}" ;;
    docroot) v="${docroot:-}" ;;
    *) die "Internal: unknown field $want_field" ;;
    esac
    printf '%s' "$v"
    ((quiet)) || printf '\n'
    return 0
  fi

  printf "%s\t%s\t%s\t%s\n" "$app" "${container:-}" "${profile:-}" "${docroot:-}"
}

domains_matching_docroot() {
  local want
  want="$(normalize_docroot "$1")"
  [[ -n "$want" ]] || return 0
  local d meta dr
  while IFS= read -r d; do
    meta="$(read_meta_from_conf "$d" 2>/dev/null || true)"
    [[ -n "$meta" ]] || continue
    dr="$(normalize_docroot "$(printf '%s\n' "$meta" | kv_get docroot)")"
    [[ "$dr" == "$want" ]] && printf '%s\n' "$d"
  done < <(list_vhost_domains)
}

pick_one_domain() {
  local prompt="$1"
  shift
  local -a arr=("$@")
  local i
  say "${YELLOW}Multiple matches:${NC}"
  for ((i = 0; i < ${#arr[@]}; i++)); do
    printf "  %d) %s\n" $((i + 1)) "${arr[$i]}"
  done
  local ans=""
  while true; do
    read -e -r -p "${prompt} (1-${#arr[@]}): " ans
    ans="$(trim "$ans")"
    [[ "$ans" =~ ^[0-9]+$ ]] || {
      err "Enter a number."
      continue
    }
    ((ans >= 1 && ans <= ${#arr[@]})) || {
      err "Out of range."
      continue
    }
    echo "${arr[$((ans - 1))]}"
    return 0
  done
}

emit_list_domains() { list_vhost_domains | LC_ALL=C sort; }

emit_list_directories() {
  local d meta dir seen="|"
  while IFS= read -r d; do
    meta="$(read_meta_from_conf "$d" 2>/dev/null || true)"
    [[ -n "$meta" ]] || continue
    dir="$(normalize_docroot "$(printf '%s\n' "$meta" | kv_get docroot)")"
    [[ -n "$dir" ]] || continue
    if [[ "$seen" != *"|$dir|"* ]]; then
      seen="${seen}${dir}|"
      printf '%s\n' "$dir"
    fi
  done < <(emit_list_domains) | LC_ALL=C sort
}

emit_list_table() {
  local d meta app container profile docroot fpm_mode
  while IFS= read -r d; do
    meta="$(read_meta_from_conf "$d" 2>/dev/null || true)"
    [[ -n "$meta" ]] || continue
    app="$(printf '%s\n' "$meta" | kv_get app)"
    docroot="$(normalize_docroot "$(printf '%s\n' "$meta" | kv_get docroot)")"
    fpm_mode="$(printf '%s\n' "$meta" | kv_get fpm_mode)"
    case "$app" in
    php)
      container="$(printf '%s\n' "$meta" | kv_get php_container)"
      profile="$(printf '%s\n' "$meta" | kv_get php_profile)"
      ;;
    node)
      container="$(printf '%s\n' "$meta" | kv_get node_container)"
      profile="$(printf '%s\n' "$meta" | kv_get node_profile)"
      fpm_mode=""
      ;;
    *)
      container=""
      profile=""
      fpm_mode=""
      ;;
    esac
    printf "%s\t%s\t%s\t%s\t%s\t%s\n" "$d" "${app:-}" "${container:-}" "${profile:-}" "${docroot:-}" "${fpm_mode:-}"
  done < <(emit_list_domains)
}

emit_list_unique_field() {
  local k1="$1" k2="${2:-}"
  local d meta v seen="|"
  while IFS= read -r d; do
    meta="$(read_meta_from_conf "$d" 2>/dev/null || true)"
    [[ -n "$meta" ]] || continue
    v="$(printf '%s\n' "$meta" | kv_get "$k1")"
    [[ -n "$v" ]] || [[ -z "$k2" ]] || v="$(printf '%s\n' "$meta" | kv_get "$k2")"
    [[ -n "$v" ]] || continue
    if [[ "$seen" != *"|$v|"* ]]; then
      seen="${seen}${v}|"
      printf '%s\n' "$v"
    fi
  done < <(emit_list_domains) | LC_ALL=C sort
}

emit_list_containers() { emit_list_unique_field php_container node_container; }
emit_list_profiles() { emit_list_unique_field php_profile node_profile; }

# ----- Main -----
case "$mode" in
list-domains) emit_list_domains ;;
list-directories) emit_list_directories ;;
list-containers) emit_list_containers ;;
list-profiles) emit_list_profiles ;;
list) emit_list_table ;;
single)
  arg="${1:-}"
  if [[ -z "$arg" ]]; then
    emit_single_from_domain "$(pick_default_domain_if_single)"
    exit 0
  fi

  if is_pathish "$arg"; then
    want_dir="$(normalize_docroot "$arg")"
    mapfile -t matches < <(domains_matching_docroot "$want_dir" | LC_ALL=C sort)

    ((${#matches[@]} > 0)) || die "No domain found with docroot=$want_dir"

    if ((${#matches[@]} == 1)); then
      emit_single_from_domain "${matches[0]}"
      exit 0
    fi

    if ((want_pick)); then
      chosen="$(pick_one_domain "Select domain" "${matches[@]}")"
      emit_single_from_domain "$chosen"
      exit 0
    fi

    printf "%s\n" "${matches[@]}"
    exit 0
  fi

  emit_single_from_domain "$arg"
  ;;
*)
  usage
  ;;
esac
