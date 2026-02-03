#!/usr/bin/env bash
set -euo pipefail

CERT_DIR="/etc/mkcert"
VHOST_DIR="/etc/share/vhosts"

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Error: missing required command: $1" >&2
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

run_mkcert() {
  mkcert "$@" >/dev/null 2>&1
}

# Collect SAN-safe DNS tokens from running containers:
# - container name
# - network aliases (what Docker DNS actually resolves)
# - hostname (harmless to include if valid)
docker_service_domains() {
  command -v docker >/dev/null 2>&1 || return 0

  local ids json
  ids="$(docker ps -q 2>/dev/null || true)"
  [[ -n "$ids" ]] || return 0

  json="$(docker inspect $ids 2>/dev/null || true)"
  [[ -n "$json" ]] || return 0

  if command -v python3 >/dev/null 2>&1; then
    DOCKER_INSPECT_JSON="$json" python3 - <<'PY'
import os, json, re
data = json.loads(os.environ.get("DOCKER_INSPECT_JSON","[]") or "[]")
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

  # Fallback without python (best-effort)
  docker inspect --format '{{.Name}} {{range $k,$v := .NetworkSettings.Networks}}{{range $v.Aliases}} {{.}}{{end}}{{end}} {{.Config.Hostname}}' $ids 2>/dev/null |
    tr ' ' '\n' |
    sed 's|^/||' |
    awk 'NF {print tolower($0)}' |
    awk '$0 ~ /^[a-z0-9.-]+$/ {print}' |
    sort -u
}

get_domains_from_files() {
  local domains=()
  local file domain

  for file in "$@"; do
    [[ -f "$file" ]] || continue
    domain="$(basename "$file" .conf)"
    [[ -n "$domain" ]] && domains+=("$domain" "*.$domain")
  done

  # Always include localhost & loopbacks
  domains+=("localhost" "*.localhost" "127.0.0.1" "::1")

  # Auto-add docker DNS names (service aliases/container names/hostnames)
  local auto
  auto="$(docker_service_domains || true)"
  if [[ -n "$auto" ]]; then
    while IFS= read -r d; do
      [[ -n "$d" ]] && domains+=("$d")
    done <<<"$auto"
  fi

  # unique + stable ordering
  printf '%s\n' "${domains[@]}" | awk 'NF' | sort -u
}

# validate_certificate <cert_path> <needs_domains:0|1>
validate_certificate() {
  local cert_file="$1"
  local needs_domains="${2:-1}"

  [[ -f "$cert_file" ]] || return 1

  # Expiration
  local expiry expiry_epoch now
  expiry="$(openssl x509 -in "$cert_file" -noout -enddate 2>/dev/null | cut -d= -f2 || true)"
  [[ -n "$expiry" ]] || return 1

  expiry_epoch="$(to_epoch "$expiry" || true)"
  [[ -n "$expiry_epoch" ]] || return 1

  now="$(date +%s)"
  [[ "$expiry_epoch" -gt "$now" ]] || return 1

  # Client certs: expiry check is enough
  [[ "$needs_domains" -eq 1 ]] || return 0

  # SAN check for server certs
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
  echo ""
  echo "--------------------------------------------------------------"
  echo "[*] Updating trust store inside this container (best-effort)..."

  if command -v update-ca-certificates >/dev/null 2>&1; then
    echo " - Running: update-ca-certificates"
    update-ca-certificates || echo " - WARN: update-ca-certificates failed (ignored)" >&2
    echo ' - Note: "rehash: skipping ca-certificates.crt..." is normal (bundle).'
  else
    echo " - INFO: update-ca-certificates not found, skipping."
  fi

  if command -v trust >/dev/null 2>&1; then
    echo " - Running: trust extract-compat (optional)"
    trust extract-compat >/dev/null 2>&1 || echo " - WARN: trust extract-compat failed (ignored)" >&2
  fi
}

generate_certificates() {
  # label -> "cert key [--client] [p12]"
  declare -A CERT_FILES=(
    ["Local Common (Server)"]="local.pem local-key.pem"
    ["Nginx (Server)"]="nginx-server.pem nginx-server-key.pem"
    ["Nginx (Proxy)"]="nginx-proxy.pem nginx-proxy-key.pem"
    ["Nginx (Client)"]="nginx-client.pem nginx-client-key.pem --client p12"
    ["Apache (Server)"]="apache-server.pem apache-server-key.pem"
    ["Apache (Client)"]="apache-client.pem apache-client-key.pem --client"
  )

  # stable order (avoid hash-map iteration randomness)
  local labels=(
    "Local Common (Server)"
    "Nginx (Server)"
    "Nginx (Proxy)"
    "Nginx (Client)"
    "Apache (Server)"
    "Apache (Client)"
  )

  local output=""
  local total=0 regenerated=0 valid=0
  local label cert_file key_file client_flag p12 needs_domains full_cert_path p12_name

  mkdir -p "$CERT_DIR"

  for label in "${labels[@]}"; do
    total=$((total + 1))
    IFS=' ' read -r cert_file key_file client_flag p12 <<<"${CERT_FILES[$label]}"
    full_cert_path="$CERT_DIR/$cert_file"

    needs_domains=1
    [[ "${client_flag:-}" == "--client" ]] && needs_domains=0

    if validate_certificate "$full_cert_path" "$needs_domains"; then
      output+=" - $label: Valid & up-to-date; regeneration skipped"$'\n'
      valid=$((valid + 1))
      continue
    fi

    if [[ "${client_flag:-}" == "--client" ]]; then
      run_mkcert --ecdsa --client \
        -cert-file "$CERT_DIR/$cert_file" \
        -key-file "$CERT_DIR/$key_file" \
        $CERT_DOMAINS

      if [[ "${p12:-}" == "p12" ]]; then
        p12_name="${cert_file%.pem}.p12"
        openssl pkcs12 -export \
          -in "$CERT_DIR/$cert_file" \
          -inkey "$CERT_DIR/$key_file" \
          -out "$CERT_DIR/$p12_name" \
          -name "${cert_file%.pem} Certificate" \
          -passout pass:"" >/dev/null 2>&1 || true
      fi
    else
      run_mkcert --ecdsa \
        -cert-file "$CERT_DIR/$cert_file" \
        -key-file "$CERT_DIR/$key_file" \
        $CERT_DOMAINS
    fi

    output+=" - $label: Generated & configured"$'\n'
    regenerated=$((regenerated + 1))
  done

  chmod 644 "$CERT_DIR"/apache-*.pem 2>/dev/null || true

  # Install mkcert root CA into this container user store (best-effort)
  run_mkcert -install || true

  output+=$'\n'"--------------------------------------------------------------"$'\n'
  if [[ $regenerated -eq 0 ]]; then
    output+="[OK] All ($total) certificates are valid; no regeneration required."
  elif [[ $valid -eq 0 ]]; then
    output+="[OK] All ($total) certificates were regenerated."
  else
    output+="[OK] Certificate validation complete; Regenerated: $regenerated, Valid: $valid."
  fi

  echo "$output"
}

main() {
  need_cmd openssl
  need_cmd mkcert
  mkdir -p "$CERT_DIR"

  mapfile -t CONF_FILES < <(find "$VHOST_DIR" -type f -name '*.conf' 2>/dev/null || true)
  CERT_DOMAINS="$(get_domains_from_files "${CONF_FILES[@]}")"

  echo "=============================================================="
  echo ""
  echo "[~] List of domains (SAN):"
  echo ""
  echo "$CERT_DOMAINS" | awk '{print " - "$0}'
  echo ""
  echo "--------------------------------------------------------------"
  echo "[*] Generating Certificates..."
  echo ""

  generate_certificates

  update_container_trust

  echo ""
  echo "=============================================================="
}

main "$@"
