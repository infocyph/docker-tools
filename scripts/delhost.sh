#!/usr/bin/env bash
# delhost - remove vhost configs for a domain (nginx/apache/node yaml only)
set -euo pipefail

RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
CYAN=$'\033[0;36m'
YELLOW=$'\033[1;33m'
NC=$'\033[0m'

die() { printf "%bError:%b %s\n" "$RED" "$NC" "$*" >&2; exit 1; }

validate_domain() {
  local domain=$1
  local regex="^([a-zA-Z0-9][-a-zA-Z0-9]{0,253}[a-zA-Z0-9]\.)+[a-zA-Z]{2,}$"
  [[ $domain =~ $regex ]]
}

slugify() {
  # must match mkhost slugify(): domain -> safe token
  echo "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/_/g; s/^_+|_+$//g'
}

confirm() {
  local prompt="$1" ans
  read -r -p "$(printf "%b%s (y/N): %b" "$YELLOW" "$prompt" "$NC")" ans
  [[ "${ans,,}" =~ ^y(es)?$ ]]
}

DOMAIN="${1:-}"
if [[ -z "$DOMAIN" ]]; then
  read -r -p "$(printf "%bEnter domain to delete (e.g., example.com): %b" "$CYAN" "$NC")" DOMAIN
  DOMAIN="$(echo "$DOMAIN" | xargs)"
fi

validate_domain "$DOMAIN" || die "Invalid domain: $DOMAIN"

TOKEN="$(slugify "$DOMAIN")"

VHOST_ROOT="/etc/share/vhosts"
NGINX_CONF="${VHOST_ROOT}/nginx/${DOMAIN}.conf"
APACHE_CONF="${VHOST_ROOT}/apache/${DOMAIN}.conf"
NODE_YAML="${VHOST_ROOT}/node/${TOKEN}.yaml"

targets=()
[[ -e "$NGINX_CONF"  ]] && targets+=("$NGINX_CONF")
[[ -e "$APACHE_CONF" ]] && targets+=("$APACHE_CONF")
[[ -e "$NODE_YAML"   ]] && targets+=("$NODE_YAML")

printf "%bDelHost:%b domain=%s  token=%s\n" "$CYAN" "$NC" "$DOMAIN" "$TOKEN"

if ((${#targets[@]} == 0)); then
  printf "%bNothing to delete:%b no vhost files found for %s\n" "$YELLOW" "$NC" "$DOMAIN" >&2
  # exit 2 helps callers distinguish "not found" vs "failed"
  exit 2
fi

printf "%bWill delete:%b\n" "$CYAN" "$NC"
for f in "${targets[@]}"; do
  printf " - %s\n" "$f"
done

confirm "Proceed to delete these files?" || {
  printf "%bCancelled.%b\n" "$YELLOW" "$NC"
  exit 0
}

removed=0
for f in "${targets[@]}"; do
  if rm -f -- "$f"; then
    printf "%bDeleted:%b %s\n" "$GREEN" "$NC" "$f"
    removed=$((removed + 1))
  fi
done

printf "%bDone.%b Removed %d file(s).\n" "$GREEN" "$NC" "$removed"
