#!/usr/bin/env bash
set -euo pipefail

VHOST_NGINX_DIR="${VHOST_NGINX_DIR:-/etc/share/vhosts/nginx}"
MAX_HEADER_LINES="${MAX_HEADER_LINES:-120}"
APP_BASE_DIR="${APP_BASE_DIR:-/app}"

###############################################################################
# Colors + UI (mkhost-style, safe under set -u)
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

is_tty() { [[ -t 1 ]]; }

###############################################################################
# Helpers
###############################################################################

usage() {
  cat >&2 <<'EOF'
Usage:
  domain-which [--json] [--sock] [--pick] [--app|--container|--profile|--docroot] [--quiet] [domain|docroot]
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

print_numbered_list() {
  local title="${1:-}"
  shift || true
  local -a items=("$@")
  local i

  # Keep machine-friendly output when piped/redirected
  if ! is_tty; then
    printf "%s\n" "${items[@]}"
    return 0
  fi

  [[ -n "$title" ]] && say "${BOLD}${title}${NC}"
  for ((i = 0; i < ${#items[@]}; i++)); do
    printf "  %b%2d)%b %s\n" "${CYAN}" $((i + 1)) "${NC}" "${items[$i]}"
  done
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

resolve_docroot_path() {
  local raw norm base candidate
  raw="${1:-}"
  norm="$(normalize_docroot "$raw")"
  [[ -n "$norm" ]] || {
    echo ""
    return 0
  }

  if [[ -d "$norm" || -f "$norm" ]]; then
    echo "$norm"
    return 0
  fi

  base="$(normalize_docroot "$APP_BASE_DIR")"
  [[ -n "$base" ]] || {
    echo "$norm"
    return 0
  }

  if [[ "$norm" == "$base" || "$norm" == "$base/"* ]]; then
    echo "$norm"
    return 0
  fi

  candidate="$base$norm"
  if [[ -d "$candidate" || -f "$candidate" ]]; then
    echo "$candidate"
    return 0
  fi

  echo "$norm"
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
  mapfile -t ds < <(list_vhost_domains)
  if ((${#ds[@]} == 1)); then
    echo "${ds[0]}"
    return 0
  fi
  if ((${#ds[@]} == 0)); then
    die "No nginx vhosts found in: $VHOST_NGINX_DIR"
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
    [[ -z "$line" ]] && continue
    [[ "$line" =~ ^[[:space:]]*# ]] || break
    if [[ "$line" =~ ^[[:space:]]*#[[:space:]]*LDS-META:[[:space:]]*([a-zA-Z0-9_]+)=(.*)$ ]]; then
      printf '%s=%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
    fi
  done <"$conf"
}

kv_get() { awk -F= -v k="$1" '$1==k{ sub(/^([^=]*=)/,""); print; exit }'; }

emit_single_from_domain() {
  local domain="$1"
  local meta app docroot_raw docroot container profile sock_web sock_fpm

  meta="$(read_meta_from_conf "$domain" || true)"
  [[ -n "$meta" ]] || die "Missing or unreadable LDS-META header for: $domain"

  if ((want_meta)); then
    emit_meta_block_from_domain "$domain"
    return 0
  fi

  app="$(printf '%s\n' "$meta" | kv_get app)"
  docroot_raw="$(printf '%s\n' "$meta" | kv_get docroot)"
  docroot="$(resolve_docroot_path "$docroot_raw")"
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
    printf '"domain":"%s","app":"%s","docroot":"%s","docroot_raw":"%s","container":"%s","profile":"%s"' \
      "$domain" "$app" "${docroot:-}" "${docroot_raw:-}" "${container:-}" "${profile:-}"
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

domains_matching_docroot() {
  local want want_resolved
  want="$(normalize_docroot "$1")"
  [[ -n "$want" ]] || return 0
  want_resolved="$(resolve_docroot_path "$want")"
  local d meta dr_raw dr_resolved
  while IFS= read -r d; do
    meta="$(read_meta_from_conf "$d" 2>/dev/null || true)"
    [[ -n "$meta" ]] || continue
    dr_raw="$(normalize_docroot "$(printf '%s\n' "$meta" | kv_get docroot)")"
    dr_resolved="$(resolve_docroot_path "$dr_raw")"
    if [[ "$dr_raw" == "$want" || "$dr_resolved" == "$want" || "$dr_raw" == "$want_resolved" || "$dr_resolved" == "$want_resolved" ]]; then
      printf '%s\n' "$d"
    fi
  done < <(list_vhost_domains)
}

pick_one_domain() {
  local prompt="$1"
  shift
  local -a arr=("$@")
  local i
  echo "Multiple matches:"
  for ((i = 0; i < ${#arr[@]}; i++)); do
    printf "  %d) %s\n" $((i + 1)) "${arr[$i]}"
  done
  local ans=""
  while true; do
    read -e -r -p "${prompt} (1-${#arr[@]}): " ans
    ans="$(trim "$ans")"
    [[ "$ans" =~ ^[0-9]+$ ]] || {
      echo "Enter a number." >&2
      continue
    }
    ((ans >= 1 && ans <= ${#arr[@]})) || {
      echo "Out of range." >&2
      continue
    }
    echo "${arr[$((ans - 1))]}"
    return 0
  done
}

emit_list_domains() {
  local -a ds=()
  mapfile -t ds < <(list_vhost_domains | LC_ALL=C sort)

  if ((${#ds[@]} == 0)); then
    is_tty && warn "No valid domains found." || true
    return 0
  fi

  print_numbered_list "Domains:" "${ds[@]}"
}

emit_list_directories() {
  local -a dirs=()
  local d meta dir seen="|"
  while IFS= read -r d; do
    meta="$(read_meta_from_conf "$d" 2>/dev/null || true)"
    [[ -n "$meta" ]] || continue
    dir="$(resolve_docroot_path "$(printf '%s\n' "$meta" | kv_get docroot)")"
    [[ -n "$dir" ]] || continue
    if [[ "$seen" != *"|$dir|"* ]]; then
      seen="${seen}${dir}|"
      dirs+=("$dir")
    fi
  done < <(list_vhost_domains)

  if ((${#dirs[@]} == 0)); then
    is_tty && warn "No directories found." || true
    return 0
  fi

  mapfile -t dirs < <(printf "%s\n" "${dirs[@]}" | LC_ALL=C sort)
  print_numbered_list "Directories:" "${dirs[@]}"
}

emit_list_table() {
  # domain<TAB>app<TAB>container<TAB>profile<TAB>docroot<TAB>fpm_mode
  local d meta app container profile docroot fpm_mode
  while IFS= read -r d; do
    meta="$(read_meta_from_conf "$d" 2>/dev/null || true)"
    [[ -n "$meta" ]] || continue
    app="$(printf '%s\n' "$meta" | kv_get app)"
    docroot="$(resolve_docroot_path "$(printf '%s\n' "$meta" | kv_get docroot)")"
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

emit_list_containers() {
  local -a xs=()
  mapfile -t xs < <(emit_list_unique_field php_container node_container | LC_ALL=C sort)
  ((${#xs[@]})) || {
    is_tty && warn "No containers found." || true
    return 0
  }
  print_numbered_list "Containers:" "${xs[@]}"
}
emit_list_profiles() {
  local -a xs=()
  mapfile -t xs < <(emit_list_unique_field php_profile node_profile | LC_ALL=C sort)
  ((${#xs[@]})) || {
    is_tty && warn "No profiles found." || true
    return 0
  }
  print_numbered_list "Profiles:" "${xs[@]}"
}

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
    ds=()
    mapfile -t ds < <(list_vhost_domains | LC_ALL=C sort)
    if ((${#ds[@]} == 1)); then
      emit_single_from_domain "${ds[0]}"
      exit 0
    fi
    if ((${#ds[@]} == 0)); then
      die "No valid nginx vhosts found in: $VHOST_NGINX_DIR"
    fi
    die "Domain required (found ${#ds[@]} domains). Use --list-domains."
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

    # default: print a table for matches
    for d in "${matches[@]}"; do
      emit_single_from_domain "$d" | sed "s/^/${d}\t/" >/dev/null 2>&1 || true
    done
    # Better: show a simple list unless user requested list/table elsewhere
    printf "%s\n" "${matches[@]}"
    exit 0
  fi

  emit_single_from_domain "$arg"
  ;;
*)
  usage
  ;;
esac
