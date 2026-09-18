#!/usr/bin/env bash
set -euo pipefail

CERT_DIR="${CERT_DIR:-/etc/mkcert}"
VHOST_DIR="${VHOST_DIR:-/etc/share/vhosts}"
TOOLS_CONTAINER_NAME="${TOOLS_CONTAINER_NAME:-${ADMIN_PANEL_TOOLS_CONTAINER:-SERVER_TOOLS}}"

# User-facing export. The root CA public certificate is safe to export automatically.
# User P12 export is opt-in and password-protected.
EXPORT_DIR="${EXPORT_DIR:-/etc/share/certs}"
EXPORT_P12="${EXPORT_P12:-lds-client-user.p12}"
EXPORT_P12_NAME="${EXPORT_P12_NAME:-mTLS-user.p12}"
EXPORT_ROOTCA_NAME="${EXPORT_ROOTCA_NAME:-rootCA.pem}"
LDS_USER_P12_ENABLED="${LDS_USER_P12_ENABLED:-0}"
LDS_USER_P12_PASSWORD="${LDS_USER_P12_PASSWORD:-}"

###############################################################################
# UI (mkhost/rmhost-compatible, TTY-aware)
###############################################################################
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  BOLD=$'\033[1m'
  DIM=$'\033[2m'
  RED=$'\033[1;31m'
  GREEN=$'\033[1;32m'
  CYAN=$'\033[1;36m'
  YELLOW=$'\033[1;33m'
  MAGENTA=$'\033[1;35m'
  NC=$'\033[0m'
else
  BOLD='' DIM='' RED='' GREEN='' CYAN='' YELLOW='' MAGENTA='' NC=''
fi

say()  { echo -e "$*"; }
ok()   { say "${GREEN}${BOLD}$*${NC}"; }
warn() { say "${YELLOW}${BOLD}$*${NC}"; }
err()  { say "${RED}${BOLD}$*${NC}"; }
info() { say "${CYAN}${BOLD}$*${NC}"; }
line() { say "${DIM}--------------------------------------------------------------${NC}"; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    err "Error: missing required command: $1"
    exit 1
  }
}

# Parse openssl enddate -> epoch (GNU date or BSD date)
to_epoch() {
  local s="$1"
  if date -d "$s" +%s >/dev/null 2>&1; then
    date -d "$s" +%s
    return 0
  fi
  date -j -f "%b %e %T %Y %Z" "$s" +%s 2>/dev/null
}

# Format epoch in local timezone: "YYYY-MM-DD HH:MM:SS +ZZZZ"
fmt_epoch_local() {
  local e="$1"
  if date -d "@$e" "+%Y-%m-%d %H:%M:%S %z" >/dev/null 2>&1; then
    date -d "@$e" "+%Y-%m-%d %H:%M:%S %z"
    return 0
  fi
  date -r "$e" "+%Y-%m-%d %H:%M:%S %z" 2>/dev/null
}

run_mkcert() {
  mkcert "$@" >/dev/null 2>&1
}

resolve_compose_project() {
  local project="${LDS_COMPOSE_PROJECT:-${COMPOSE_PROJECT_NAME:-}}"
  project="$(printf '%s' "$project" | xargs)"
  if [[ -n "$project" ]]; then
    printf '%s\n' "$project"
    return 0
  fi

  command -v docker >/dev/null 2>&1 || return 1
  project="$(docker inspect --format '{{ index .Config.Labels "com.docker.compose.project" }}' "$TOOLS_CONTAINER_NAME" 2>/dev/null || true)"
  project="$(printf '%s' "$project" | xargs)"
  [[ -n "$project" && "$project" != '<no value>' ]] || return 1
  printf '%s\n' "$project"
}

# Collect SAN-safe DNS tokens only from the current LocalDevStack Compose project.
# If the project cannot be determined, do not widen discovery to the whole daemon.
docker_service_domains() {
  command -v docker >/dev/null 2>&1 || return 0

  local project ids json
  project="$(resolve_compose_project || true)"
  [[ -n "$project" ]] || return 0

  ids="$(docker ps -q --filter "label=com.docker.compose.project=${project}" 2>/dev/null || true)"
  [[ -n "$ids" ]] || return 0

  json="$(docker inspect $ids 2>/dev/null || true)"
  [[ -n "$json" ]] || return 0

  if command -v python3 >/dev/null 2>&1; then
    DOCKER_INSPECT_JSON="$json" python3 - <<'PY'
import os, json, re
data = json.loads(os.environ.get("DOCKER_INSPECT_JSON", "[]") or "[]")
rx = re.compile(r"^[a-z0-9.-]+$", re.I)
out = set()

for c in data:
  name = (c.get("Name") or "").lstrip("/")
  if name and rx.match(name): out.add(name.lower())

  hn = ((c.get("Config") or {}).get("Hostname") or "")
  if hn and rx.match(hn): out.add(hn.lower())

  nets = (c.get("NetworkSettings") or {}).get("Networks") or {}
  for ncfg in nets.values():
    aliases = (ncfg or {}).get("Aliases") or []
    for a in aliases:
      if a and rx.match(a): out.add(a.lower())

for x in sorted(out):
  print(x)
PY
    return 0
  fi

  docker inspect --format '{{.Name}} {{range $k,$v := .NetworkSettings.Networks}}{{range $v.Aliases}} {{.}}{{end}}{{end}} {{.Config.Hostname}}' $ids 2>/dev/null \
    | tr ' ' '\n' \
    | sed 's|^/||' \
    | awk 'NF {print tolower($0)}' \
    | awk '$0 ~ /^[a-z0-9.-]+$/ {print}' \
    | sort -u
}

get_domains_from_files() {
  local domains=()
  local file domain

  for file in "$@"; do
    [[ -f "$file" ]] || continue
    domain="$(basename "$file" .conf)"
    [[ -n "$domain" ]] && domains+=("$domain" "*.$domain")
  done

  domains+=("localhost" "*.localhost" "127.0.0.1" "::1")

  local auto
  auto="$(docker_service_domains || true)"
  if [[ -n "$auto" ]]; then
    while IFS= read -r domain; do
      [[ -n "$domain" ]] && domains+=("$domain")
    done <<<"$auto"
  fi

  printf '%s\n' "${domains[@]}" | awk 'NF' | sort -u
}

cert_expiry_epoch() {
  local cert_file="$1" expiry expiry_epoch
  [[ -f "$cert_file" ]] || return 1
  expiry="$(openssl x509 -in "$cert_file" -noout -enddate 2>/dev/null | cut -d= -f2 || true)"
  [[ -n "$expiry" ]] || return 1
  expiry_epoch="$(to_epoch "$expiry" || true)"
  [[ -n "$expiry_epoch" ]] || return 1
  printf '%s\n' "$expiry_epoch"
}

validate_certificate() {
  local cert_file="$1"
  local needs_domains="${2:-1}"

  [[ -f "$cert_file" ]] || return 1

  local expiry_epoch now
  expiry_epoch="$(cert_expiry_epoch "$cert_file" || true)"
  [[ -n "$expiry_epoch" ]] || return 1

  now="$(date +%s)"
  [[ "$expiry_epoch" -gt "$now" ]] || return 1
  [[ "$needs_domains" -eq 1 ]] || return 0

  local san dns_entries ip_entries all_san
  san="$(openssl x509 -in "$cert_file" -noout -ext subjectAltName 2>/dev/null | tr ',' '\n' || true)"
  [[ -n "$san" ]] || return 1

  dns_entries="$(printf '%s\n' "$san" | grep -E 'DNS:' | sed 's/.*DNS://g' | xargs || true)"
  ip_entries="$(printf '%s\n' "$san" | grep -E 'IP Address:' | sed 's/.*IP Address://g' | xargs || true)"
  all_san="$dns_entries $ip_entries"

  if [[ -n "${CERT_DOMAINS:-}" ]]; then
    local domain
    while IFS= read -r domain; do
      domain="$(printf '%s' "$domain" | xargs || true)"
      [[ -n "$domain" ]] || continue

      if [[ "$domain" == "::1" ]]; then
        echo "$all_san" | grep -qw "0:0:0:0:0:0:0:1" || return 1
      else
        echo "$all_san" | grep -qw "$domain" || return 1
      fi
    done <<<"$CERT_DOMAINS"
  fi

  return 0
}

update_container_trust() {
  echo
  line
  info "[*] Updating trust store inside this container (best-effort)..."

  if command -v update-ca-certificates >/dev/null 2>&1; then
    say " - ${DIM}Running:${NC} update-ca-certificates"
    update-ca-certificates || warn " - WARN: update-ca-certificates failed (ignored)"
    say " - ${DIM}Note:${NC} \"rehash: skipping ca-certificates.crt...\" is normal (bundle)."
  else
    say " - ${DIM}INFO:${NC} update-ca-certificates not found, skipping."
  fi

  if command -v trust >/dev/null 2>&1; then
    say " - ${DIM}Running:${NC} trust extract-compat (optional)"
    trust extract-compat >/dev/null 2>&1 || warn " - WARN: trust extract-compat failed (ignored)"
  fi
}

atomic_install() {
  local mode="$1" src="$2" dst="$3"
  local dir tmp
  dir="$(dirname "$dst")"
  tmp="$dir/.tmp.$(basename "$dst").$$.$RANDOM"
  install -m "$mode" "$src" "$tmp"
  mv -f "$tmp" "$dst"
}

generate_user_p12() {
  [[ "$LDS_USER_P12_ENABLED" == "1" ]] || return 0
  [[ -n "$LDS_USER_P12_PASSWORD" ]] || {
    err "LDS_USER_P12_ENABLED=1 requires a non-empty LDS_USER_P12_PASSWORD."
    return 1
  }

  local cert="$CERT_DIR/lds-client-user.pem"
  local key="$CERT_DIR/lds-client-user-key.pem"
  local out="$CERT_DIR/$EXPORT_P12"
  [[ -f "$cert" && -f "$key" ]] || {
    err "Cannot build user P12; user client certificate/key is missing."
    return 1
  }

  local tmp="$CERT_DIR/.tmp.${EXPORT_P12}.$$.$RANDOM"
  if ! openssl pkcs12 -export \
    -in "$cert" \
    -inkey "$key" \
    -out "$tmp" \
    -name "lds-client-user Certificate" \
    -passout "pass:${LDS_USER_P12_PASSWORD}" >/dev/null 2>&1; then
    rm -f -- "$tmp"
    err "Failed to build password-protected user P12."
    return 1
  fi
  chmod 0600 "$tmp"
  mv -f -- "$tmp" "$out"
}

export_user_artifacts() {
  echo
  line
  info "[*] Exporting user-facing certificate artifacts..."

  mkdir -p "$EXPORT_DIR"
  chmod 755 "$EXPORT_DIR" 2>/dev/null || true

  local caroot root_ca
  caroot="$(mkcert -CAROOT 2>/dev/null || true)"
  root_ca=""
  [[ -n "$caroot" ]] && root_ca="$caroot/rootCA.pem"

  if [[ -f "$root_ca" ]]; then
    atomic_install 0644 "$root_ca" "$EXPORT_DIR/$EXPORT_ROOTCA_NAME"
    ok " - [OK] ${EXPORT_ROOTCA_NAME} -> $EXPORT_DIR/$EXPORT_ROOTCA_NAME"
  else
    warn " - WARN: rootCA.pem not found (mkcert -CAROOT returned: ${caroot:-<empty>})"
  fi

  local p12_src="$CERT_DIR/$EXPORT_P12"
  local p12_dst="$EXPORT_DIR/$EXPORT_P12_NAME"
  if [[ "$LDS_USER_P12_ENABLED" == "1" ]]; then
    if [[ -f "$p12_src" ]]; then
      atomic_install 0600 "$p12_src" "$p12_dst"
      ok " - [OK] Password-protected ${EXPORT_P12} -> $p12_dst"
    else
      warn " - WARN: P12 not found: $p12_src"
    fi
  else
    rm -f -- "$p12_dst"
    say " - ${DIM}User P12 export disabled (set LDS_USER_P12_ENABLED=1 explicitly).${NC}"
  fi

  say " - ${DIM}Available in:${NC} $EXPORT_DIR"
  (ls "$EXPORT_DIR" 2>/dev/null || true) | sed 's/^/   /' || true
}

generate_certificates() {
  declare -A CERT_FILES=(
    ["LDS (Server)"]="lds-server.pem lds-server-key.pem"
    ["LDS (Client Internal)"]="lds-client-internal.pem lds-client-internal-key.pem --client"
    ["LDS (Client User)"]="lds-client-user.pem lds-client-user-key.pem --client"
  )

  local labels=(
    "LDS (Server)"
    "LDS (Client Internal)"
    "LDS (Client User)"
  )

  local output=""
  local total=0 regenerated=0 valid=0
  local label cert_file key_file client_flag needs_domains full_cert_path
  local exp_epoch exp_str

  mkdir -p "$CERT_DIR"

  for label in "${labels[@]}"; do
    total=$((total + 1))
    IFS=' ' read -r cert_file key_file client_flag <<<"${CERT_FILES[$label]}"
    full_cert_path="$CERT_DIR/$cert_file"

    needs_domains=1
    [[ "${client_flag:-}" == "--client" ]] && needs_domains=0

    if validate_certificate "$full_cert_path" "$needs_domains"; then
      exp_epoch="$(cert_expiry_epoch "$full_cert_path" || true)"
      exp_str=""
      [[ -n "$exp_epoch" ]] && exp_str="$(fmt_epoch_local "$exp_epoch" || true)"
      [[ -n "$exp_str" ]] && exp_str=" ${DIM}(~$exp_str)${NC}"

      output+=" ${GREEN}${BOLD}- ${label}:${NC} Valid & up-to-date${exp_str}; ${DIM}regeneration skipped${NC}"$'\n'
      valid=$((valid + 1))
      continue
    fi

    if [[ "${client_flag:-}" == "--client" ]]; then
      run_mkcert --ecdsa --client \
        -cert-file "$CERT_DIR/$cert_file" \
        -key-file "$CERT_DIR/$key_file" \
        $CERT_DOMAINS
    else
      run_mkcert --ecdsa \
        -cert-file "$CERT_DIR/$cert_file" \
        -key-file "$CERT_DIR/$key_file" \
        $CERT_DOMAINS
    fi

    exp_epoch="$(cert_expiry_epoch "$full_cert_path" || true)"
    exp_str=""
    [[ -n "$exp_epoch" ]] && exp_str="$(fmt_epoch_local "$exp_epoch" || true)"
    [[ -n "$exp_str" ]] && exp_str=" ${DIM}(~$exp_str)${NC}"

    output+=" ${YELLOW}${BOLD}- ${label}:${NC} Generated & configured${exp_str}"$'\n'
    regenerated=$((regenerated + 1))
  done

  chmod 644 \
    "$CERT_DIR"/lds-server.pem \
    "$CERT_DIR"/lds-client-internal.pem \
    "$CERT_DIR"/lds-client-user.pem \
    2>/dev/null || true
  chmod 0600 \
    "$CERT_DIR"/lds-server-key.pem \
    "$CERT_DIR"/lds-client-internal-key.pem \
    "$CERT_DIR"/lds-client-user-key.pem \
    2>/dev/null || true

  generate_user_p12
  run_mkcert -install >/dev/null 2>&1 || true

  output+=$'\n'"${DIM}--------------------------------------------------------------${NC}"$'\n'
  if [[ $regenerated -eq 0 ]]; then
    output+="${GREEN}${BOLD}[OK]${NC} All (${total}) certificates are valid; no regeneration required."
  elif [[ $valid -eq 0 ]]; then
    output+="${GREEN}${BOLD}[OK]${NC} All (${total}) certificates were regenerated."
  else
    output+="${GREEN}${BOLD}[OK]${NC} Certificate validation complete; Regenerated: ${regenerated}, Valid: ${valid}."
  fi

  echo -e "$output"
}

main() {
  need_cmd openssl
  need_cmd mkcert

  case "$LDS_USER_P12_ENABLED" in
    0|1) ;;
    *) err "LDS_USER_P12_ENABLED must be 0 or 1."; exit 1 ;;
  esac

  mkdir -p "$CERT_DIR"

  mapfile -t CONF_FILES < <(find "$VHOST_DIR" -type f -name '*.conf' 2>/dev/null || true)
  CERT_DOMAINS="$(get_domains_from_files "${CONF_FILES[@]}")"

  say "${MAGENTA}${BOLD}==============================================================${NC}"
  echo
  info "[~] List of domains (SAN):"
  echo
  echo "$CERT_DOMAINS" | awk '{print " - "$0}'
  echo
  line
  info "[*] Generating Certificates..."
  echo

  generate_certificates
  update_container_trust
  export_user_artifacts

  echo
  say "${MAGENTA}${BOLD}==============================================================${NC}"
}

main "$@"
