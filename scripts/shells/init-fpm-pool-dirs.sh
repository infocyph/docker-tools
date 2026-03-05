#!/usr/bin/env bash
set -euo pipefail

# init-fpm-pool-dirs.sh
# Creates per-version PHP-FPM pool directories:
#   /etc/share/vhosts/fpm/phpXX
# based on /etc/share/runtime-versions.json (.php.all[].version)
# and enforces safe perms so other containers can read them.
#
# Usage:
#   init-fpm-pool-dirs.sh
#   FPM_ROOT=/etc/share/vhosts/fpm VERSIONS_DB=/etc/share/runtime-versions.json init-fpm-pool-dirs.sh
#
# Exit codes:
#   0 OK
#   1 fatal error

FPM_ROOT="${FPM_ROOT:-/etc/share/vhosts/fpm}"
VERSIONS_DB="${VERSIONS_DB:-/etc/share/runtime-versions.json}"

log() { printf '%s\n' "$*"; }
warn() { printf 'WARN: %s\n' "$*" >&2; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

need_cmd() { command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"; }

to_profile() {
  # "8.5" -> "php85"
  # "7.4" -> "php74"
  local v="$1"
  v="${v//./}"
  printf "php%s
" "$v"
}

main() {
  need_cmd jq

  [[ -n "$FPM_ROOT" ]] || die "FPM_ROOT is empty"
  mkdir -p "$FPM_ROOT"

  if [[ ! -r "$VERSIONS_DB" ]]; then
    warn "versions db not readable: $VERSIONS_DB (creating only root dir)"
    chmod 0755 "$FPM_ROOT" || true
    exit 0
  fi

  # Build unique list of php profiles from db
  mapfile -t profiles < <(
    jq -r '.php.all[]?.version // empty' "$VERSIONS_DB" \
      | awk 'NF' \
      | sed 's/[[:space:]]//g' \
      | sort -u \
      | while IFS= read -r v; do
      [[ "$v" =~ ^([0-9]+)\.([0-9]+)$ ]] || continue
      major="${BASH_REMATCH[1]}"
      minor="${BASH_REMATCH[2]}"
      if (( major > 5 || (major == 5 && minor >= 5) )); then
        to_profile "$v"
      fi
    done \
      | sort -u
  )

  if ((${#profiles[@]} == 0)); then
    warn "no php versions found in: $VERSIONS_DB (created root only)"
    chmod 0755 "$FPM_ROOT" || true
    exit 0
  fi

  ( umask 022
    for p in "${profiles[@]}"; do
      mkdir -p "${FPM_ROOT}/${p}"
    done
  )

  # Deterministic permissions:
  # - dirs readable + searchable by all containers (ro bind mounts)
  chmod 0755 "$FPM_ROOT" || true
  chmod 0755 "${FPM_ROOT}"/php* 2>/dev/null || true

  # Print summary (stable, useful in logs)
  log "OK: ensured FPM pool dirs under: $FPM_ROOT"
  for p in "${profiles[@]}"; do
    log " - ${FPM_ROOT}/${p}"
  done
}

main "$@"
