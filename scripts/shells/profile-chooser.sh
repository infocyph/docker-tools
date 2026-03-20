#!/usr/bin/env bash
set -euo pipefail

ENV_STORE_JSON="${ENV_STORE_JSON:-/etc/share/state/env-store.json}"
STATE_JSON_KEY="${PROFILE_CHOOSER_STATE_JSON_KEY:-PROFILE_CHOOSER_STATE}"
META_UPDATED_KEY="PROFILE_CHOOSER_UPDATED_AT"
META_SERVICES_KEY="PROFILE_CHOOSER_SERVICES"
META_PROFILES_KEY="PROFILE_CHOOSER_PROFILES"
META_ENVCOUNT_KEY="PROFILE_CHOOSER_ENV_COUNT"

declare -A SERVICES=(
  [POSTGRESQL]="postgresql"
  [MYSQL]="mysql"
  [MARIADB]="mariadb"
  [ELASTICSEARCH]="elasticsearch"
  [MONGODB]="mongodb"
  [REDIS]="redis"
)

declare -a SERVICE_ORDER=(POSTGRESQL MYSQL MARIADB ELASTICSEARCH MONGODB REDIS)

declare -A PROFILE_ENV=(
  [elasticsearch]="ELASTICSEARCH_VERSION=9.3.0"
  [mysql]="MYSQL_VERSION=latest MYSQL_ROOT_PASSWORD=12345 MYSQL_USER=infocyph MYSQL_PASSWORD=12345 MYSQL_DATABASE=localdb"
  [mariadb]="MARIADB_VERSION=latest MARIADB_ROOT_PASSWORD=12345 MARIADB_USER=infocyph MARIADB_PASSWORD=12345 MARIADB_DATABASE=localdb"
  [mongodb]="MONGODB_VERSION=latest MONGODB_ROOT_USERNAME=root MONGODB_ROOT_PASSWORD=12345"
  [redis]="REDIS_VERSION=latest"
  [postgresql]="POSTGRES_VERSION=latest POSTGRES_USER=postgres POSTGRES_PASSWORD=postgres POSTGRES_DATABASE=postgres"
)

declare -a STATE_SERVICES=()
declare -a STATE_PROFILES=()
declare -a STATE_ENV_KEYS=()
declare -a STATE_ENV_VALS=()
declare -A _STATE_ENV_IDX=()
declare -A _STATE_SERVICE_SEEN=()
declare -A _STATE_PROFILE_SEEN=()

BOLD=$'\033[1m'
RED=$'\033[1;31m'
GREEN=$'\033[1;32m'
CYAN=$'\033[1;36m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[1;34m'
NC=$'\033[0m'

die() {
  printf "%bError:%b %s\n" "$RED" "$NC" "$*" >&2
  exit 1
}

need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"; }

tty_readline() {
  local __var_name="$1" __prompt="$2" __line
  if [[ -t 0 ]]; then
    printf '%s' "$__prompt" >&2
    IFS= read -r __line || return 1
  elif [[ -r /dev/tty ]]; then
    printf '%s' "$__prompt" >/dev/tty
    IFS= read -r __line </dev/tty || return 1
  else
    return 1
  fi
  printf -v "$__var_name" '%s' "$__line"
}

read_default() {
  local prompt="$1" default="$2" input=""
  tty_readline input "$(printf '%b%s [default: %s]:%b ' "$CYAN" "$prompt" "$default" "$NC")" || return 1
  printf '%s' "${input:-$default}"
}

env_store_exec() {
  command -v env-store >/dev/null 2>&1 || die "Missing command: env-store"
  ENV_STORE_JSON="$ENV_STORE_JSON" env-store "$@"
}

env_set() {
  local key="$1" val="${2-}"
  env_store_exec set "$key" "$val" >/dev/null
}

env_unset() {
  local key="$1"
  env_store_exec unset "$key" >/dev/null || true
}

state_load_json() {
  local j
  j="$(ENV_STORE_JSON="$ENV_STORE_JSON" env-store get-json "$STATE_JSON_KEY" 2>/dev/null || true)"
  if [[ -n "$j" ]] && printf '%s' "$j" | jq -e . >/dev/null 2>&1; then
    printf '%s\n' "$j"
    return 0
  fi
  return 1
}

state_save_json() {
  local json="$1"
  local updated_at
  updated_at="$(printf '%s' "$json" | jq -r '.updated_at // empty')"

  ENV_STORE_JSON="$ENV_STORE_JSON" env-store set-json "$STATE_JSON_KEY" "$json" >/dev/null
  env_set "$META_UPDATED_KEY" "${updated_at:-}"
  env_set "$META_SERVICES_KEY" "$(IFS=,; echo "${STATE_SERVICES[*]}")"
  env_set "$META_PROFILES_KEY" "$(IFS=,; echo "${STATE_PROFILES[*]}")"
  env_set "$META_ENVCOUNT_KEY" "${#STATE_ENV_KEYS[@]}"
}

state_reset() {
  env_unset "$STATE_JSON_KEY"
  env_unset "$META_UPDATED_KEY"
  env_unset "$META_SERVICES_KEY"
  env_unset "$META_PROFILES_KEY"
  env_unset "$META_ENVCOUNT_KEY"
}

queue_service() {
  local service="$1"
  [[ -n "${_STATE_SERVICE_SEEN[$service]:-}" ]] && return 0
  _STATE_SERVICE_SEEN["$service"]=1
  STATE_SERVICES+=("$service")
}

queue_profile() {
  local profile="$1"
  [[ -n "${_STATE_PROFILE_SEEN[$profile]:-}" ]] && return 0
  _STATE_PROFILE_SEEN["$profile"]=1
  STATE_PROFILES+=("$profile")
}

queue_env() {
  local kv="$1"
  local key="${kv%%=*}" val="${kv#*=}" idx
  [[ -n "$key" ]] || return 0
  if [[ -n "${_STATE_ENV_IDX[$key]:-}" ]]; then
    idx="${_STATE_ENV_IDX[$key]}"
    STATE_ENV_VALS[$idx]="$val"
    return 0
  fi
  idx="${#STATE_ENV_KEYS[@]}"
  _STATE_ENV_IDX["$key"]="$idx"
  STATE_ENV_KEYS+=("$key")
  STATE_ENV_VALS+=("$val")
}

setup_menu_print() {
  {
    printf "\n%bSetup profiles%b (host will flush later):\n\n" "$CYAN" "$NC"
    local i=1 key slug
    for key in "${SERVICE_ORDER[@]}"; do
      slug="${SERVICES[$key]}"
      printf "  %2d) %-12s  (%s)\n" "$i" "$key" "$slug"
      i=$((i + 1))
    done
    printf "\n  a) ALL\n"
    printf "  n) NONE / Back\n\n"
  } >&2
}

setup_menu_parse() {
  local input="${1//[[:space:]]/}"
  [[ -n "$input" ]] || return 1
  input="${input//;/,}"

  echo "$input" | tr ',' '\n' | awk '
    BEGIN { ok=1 }
    /^[0-9]+-[0-9]+$/ {
      split($0,a,"-")
      if (a[1] > a[2]) { t=a[1]; a[1]=a[2]; a[2]=t }
      for (i=a[1]; i<=a[2]; i++) print i
      next
    }
    /^[0-9]+$/ { print $0; next }
    /^[aA]$/ { print "ALL"; next }
    /^[nN]$/ { print "NONE"; next }
    { ok=0 }
    END { if (!ok) exit 2 }
  '
}

setup_choose_services() {
  local ans parsed
  while :; do
    setup_menu_print
    tty_readline ans "Select (e.g. 1,3,5 or 2-4 or a): " || return 1

    if ! parsed="$(setup_menu_parse "$ans" 2>/dev/null)"; then
      printf "%bInvalid selection.%b Try again.\n" "$YELLOW" "$NC" >&2
      continue
    fi

    if grep -qx "NONE" <<<"$parsed"; then
      return 1
    fi
    if grep -qx "ALL" <<<"$parsed"; then
      printf "%s\n" "${SERVICE_ORDER[@]}"
      return 0
    fi

    local -A seen=()
    local -a out=()
    local idx key
    while IFS= read -r idx; do
      [[ "$idx" =~ ^[0-9]+$ ]] || continue
      ((idx >= 1 && idx <= ${#SERVICE_ORDER[@]})) || continue
      key="${SERVICE_ORDER[idx - 1]}"
      [[ -n "${seen[$key]:-}" ]] && continue
      seen["$key"]=1
      out+=("$key")
    done <<<"$parsed"

    ((${#out[@]} > 0)) || {
      printf "%bNo valid items selected.%b\n" "$YELLOW" "$NC" >&2
      continue
    }

    printf "%s\n" "${out[@]}"
    return 0
  done
}

setup_service() {
  local service="$1"
  local profile="${SERVICES[$service]:-}"
  [[ -n "$profile" ]] || die "Unknown service: $service"

  queue_service "$service"
  queue_profile "$profile"

  printf "\n%b→ %s%b\n" "$YELLOW" "$service" "$NC" >&2
  printf "%bEnter value(s) for %s:%b\n" "$BLUE" "$service" "$NC" >&2

  local pair key def val
  for pair in ${PROFILE_ENV[$profile]}; do
    IFS='=' read -r key def <<<"$pair"
    val="$(read_default "$key" "$def")"
    queue_env "$key=$val"
  done
}

build_state_json() {
  local services_json='[]' profiles_json='[]' env_json='[]'
  local updated_at svc p i

  for svc in "${STATE_SERVICES[@]}"; do
    services_json="$(jq -cn --argjson arr "$services_json" --arg v "$svc" '$arr + [$v]')"
  done
  for p in "${STATE_PROFILES[@]}"; do
    profiles_json="$(jq -cn --argjson arr "$profiles_json" --arg v "$p" '$arr + [$v]')"
  done
  for ((i = 0; i < ${#STATE_ENV_KEYS[@]}; i++)); do
    env_json="$(jq -cn \
      --argjson arr "$env_json" \
      --arg k "${STATE_ENV_KEYS[$i]}" \
      --arg v "${STATE_ENV_VALS[$i]}" \
      '$arr + [{key:$k,value:$v}]')"
  done

  updated_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || true)"
  jq -cn \
    --arg updated_at "$updated_at" \
    --argjson services "$services_json" \
    --argjson profiles "$profiles_json" \
    --argjson env "$env_json" \
    '{version:1,updated_at:$updated_at,services:$services,profiles:$profiles,env:$env}'
}

process_all() {
  local selected
  if ! selected="$(setup_choose_services)"; then
    printf "\n%bSetup cancelled.%b\n" "$YELLOW" "$NC" >&2
    return 0
  fi

  printf "\n%bWill configure:%b\n" "$CYAN" "$NC" >&2
  while IFS= read -r svc; do
    printf "  - %s (%s)\n" "$svc" "${SERVICES[$svc]}" >&2
  done <<<"$selected"
  printf "\n" >&2

  local svc
  while IFS= read -r svc; do
    setup_service "$svc"
  done <<<"$selected"

  local json
  json="$(build_state_json)"
  state_save_json "$json"
  printf "\n%bSelected services saved.%b\n" "$GREEN" "$NC" >&2
}

emit_json() {
  if ! state_load_json; then
    printf '{}\n'
  fi
}

emit_profiles() {
  local j
  j="$(state_load_json 2>/dev/null || true)"
  [[ -n "$j" ]] || return 0
  printf '%s\n' "$j" | jq -r '.profiles[]?'
}

emit_services() {
  local j
  j="$(state_load_json 2>/dev/null || true)"
  [[ -n "$j" ]] || return 0
  printf '%s\n' "$j" | jq -r '.services[]?'
}

emit_envs() {
  local j
  j="$(state_load_json 2>/dev/null || true)"
  [[ -n "$j" ]] || return 0
  printf '%s\n' "$j" | jq -r '.env[]? | "\(.key)=\(.value)"'
}

emit_summary() {
  local j
  j="$(state_load_json 2>/dev/null || true)"
  if [[ -z "$j" ]]; then
    printf "No state.\n"
    return 0
  fi
  printf "Updated: %s\n" "$(printf '%s\n' "$j" | jq -r '.updated_at // "-"')"
  printf "Services:\n"
  printf '%s\n' "$j" | jq -r '.services[]? | "  - " + .'
  printf "Profiles:\n"
  printf '%s\n' "$j" | jq -r '.profiles[]? | "  - " + .'
  printf "Env:\n"
  printf '%s\n' "$j" | jq -r '.env[]? | "  - \(.key)=\(.value)"'
}

usage() {
  cat <<'EOF'
Usage:
  profile-chooser
  profile-chooser --json
  profile-chooser --profiles
  profile-chooser --services
  profile-chooser --envs
  profile-chooser --summary
  profile-chooser --reset
  profile-chooser --has-state

Notes:
  - Interactive mode stores selected profiles + required env values in env-store.
  - env-store default file: /etc/share/state/env-store.json
  - State key (JSON): PROFILE_CHOOSER_STATE
  - Host side can consume newline-separated values via:
      profile-chooser --profiles
      profile-chooser --envs
  - Compatibility aliases:
      --RESET, --JSON, --PENDING_PROFILES, --PENDING_SERVICES, --PENDING_ENVS
EOF
}

main() {
  need_cmd jq
  need_cmd awk
  need_cmd sed
  need_cmd grep

  local mode="interactive"
  while [[ "${1:-}" ]]; do
    case "$1" in
      --json|--JSON) mode="json"; shift ;;
      --profiles|--PENDING_PROFILES) mode="profiles"; shift ;;
      --services|--PENDING_SERVICES) mode="services"; shift ;;
      --envs|--PENDING_ENVS) mode="envs"; shift ;;
      --summary) mode="summary"; shift ;;
      --reset|--RESET) mode="reset"; shift ;;
      --has-state) mode="has-state"; shift ;;
      -h|--help) usage; exit 0 ;;
      *) die "Unknown flag: $1" ;;
    esac
  done

  case "$mode" in
    interactive) process_all ;;
    json) emit_json ;;
    profiles) emit_profiles ;;
    services) emit_services ;;
    envs) emit_envs ;;
    summary) emit_summary ;;
    reset) state_reset ;;
    has-state)
      state_load_json >/dev/null 2>&1 && exit 0 || exit 1
      ;;
  esac
}

main "$@"
