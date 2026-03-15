#!/usr/bin/env bash
set -euo pipefail

_has() {
  command -v "$1" >/dev/null 2>&1
}

_trim() {
  local s="${1-}"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

_json_escape() {
  local s="${1-}"
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}
  s=${s//$'\r'/\\r}
  s=${s//$'\t'/\\t}
  printf '%s' "$s"
}

_json_bool() {
  if [[ "${1:-0}" == "1" ]]; then
    printf 'true'
  else
    printf 'false'
  fi
}

_num_or_default() {
  local v="${1:-}" d="${2:-0}"
  if [[ "$v" =~ ^-?[0-9]+$ ]]; then
    printf '%s' "$v"
  else
    printf '%s' "$d"
  fi
}

_state_dir() {
  local -a candidates=()
  if [[ -n "${MONITOR_STATE_DIR:-}" ]]; then
    candidates+=("$MONITOR_STATE_DIR")
  fi
  candidates+=("/etc/share/state" "/tmp/monitor-state" "/tmp")

  local dir probe
  for dir in "${candidates[@]}"; do
    [[ -n "$dir" ]] || continue
    mkdir -p "$dir" >/dev/null 2>&1 || true
    probe="${dir%/}/.monitor-tls-write.$$"
    if touch "$probe" >/dev/null 2>&1; then
      rm -f "$probe" >/dev/null 2>&1 || true
      printf '%s' "$dir"
      return 0
    fi
  done

  printf '/tmp'
}

_is_valid_domain_name() {
  local d="${1:-}"
  [[ -n "$d" ]] || return 1
  local re='^([a-zA-Z0-9]([-a-zA-Z0-9]{0,61}[a-zA-Z0-9])?\.)+(localhost|local|test|loc|[a-zA-Z]{2,})$'
  [[ "$d" =~ $re ]]
}

_infer_project() {
  if [[ -n "${STATUS_PROJECT:-}" ]]; then
    printf '%s' "$STATUS_PROJECT"
    return 0
  fi
  if ! _has docker; then
    printf 'unknown'
    return 0
  fi

  local p
  p="$(
    docker ps --format '{{.Label "com.docker.compose.project"}}' 2>/dev/null |
      sed '/^[[:space:]]*$/d' |
      sort |
      uniq -c |
      sort -nr |
      awk 'NR==1{print $2}'
  )"
  if [[ -z "$p" ]]; then
    printf 'unknown'
  else
    printf '%s' "$p"
  fi
}

_tcp_reachable() {
  local host="${1:-}" port="${2:-443}"
  [[ -n "$host" ]] || return 1
  if _has timeout; then
    timeout 2 bash -c "cat < /dev/null > /dev/tcp/${host}/${port}" >/dev/null 2>&1
    return $?
  fi
  bash -c "cat < /dev/null > /dev/tcp/${host}/${port}" >/dev/null 2>&1
}

_detect_tls_target() {
  local project="${1:-}"
  if [[ -n "${TLS_MONITOR_TARGET:-}" ]]; then
    printf '%s' "$TLS_MONITOR_TARGET"
    return 0
  fi

  local -a candidates=()
  local n
  if _has docker; then
    if [[ -n "$project" && "$project" != "unknown" ]]; then
      while IFS= read -r n; do
        [[ -n "$n" ]] || continue
        candidates+=("$n")
      done < <(
        docker ps --filter "label=com.docker.compose.project=${project}" --filter 'label=com.docker.compose.service=nginx' --format '{{.Names}}' 2>/dev/null |
          sed '/^[[:space:]]*$/d'
      )
    fi
    if ((${#candidates[@]} == 0)); then
      while IFS= read -r n; do
        [[ -n "$n" ]] || continue
        candidates+=("$n")
      done < <(
        docker ps --filter 'label=com.docker.compose.service=nginx' --format '{{.Names}}' 2>/dev/null |
          sed '/^[[:space:]]*$/d'
      )
    fi
  fi

  candidates+=("NGINX" "nginx" "127.0.0.1")
  mapfile -t candidates < <(printf '%s\n' "${candidates[@]}" | awk '!seen[$0]++')

  local c
  for c in "${candidates[@]}"; do
    [[ -n "$c" ]] || continue
    if [[ "$c" == "127.0.0.1" ]]; then
      printf '%s' "$c"
      return 0
    fi
    if _tcp_reachable "$c" 443; then
      printf '%s' "$c"
      return 0
    fi
  done

  printf '127.0.0.1'
}

_collect_domains() {
  local nginx_dir="${1:-/etc/share/vhosts/nginx}"
  local f d n
  local -a local_domains=() tool_domains=()

  if [[ -d "$nginx_dir" ]]; then
    shopt -s nullglob
    for f in "$nginx_dir"/*.conf; do
      d="$(basename -- "$f" .conf)"
      d="${d,,}"
      _is_valid_domain_name "$d" || continue
      local_domains+=("$d")
    done
    shopt -u nullglob
  fi

  if _has docker; then
    for n in SERVER_TOOLS "$(docker ps -aq --filter 'label=com.docker.compose.service=server-tools' 2>/dev/null | head -n1 || true)"; do
      [[ -n "$n" ]] || continue
      while IFS= read -r d; do
        d="${d,,}"
        _is_valid_domain_name "$d" || continue
        tool_domains+=("$d")
      done < <(docker exec "$n" domain-which --list-domains 2>/dev/null | sed '/^[[:space:]]*$/d' || true)
      ((${#tool_domains[@]})) && break
    done
  fi

  if ((${#tool_domains[@]} > ${#local_domains[@]})); then
    printf '%s\n' "${tool_domains[@]}" | awk '!seen[$0]++'
  elif ((${#local_domains[@]})); then
    printf '%s\n' "${local_domains[@]}" | awk '!seen[$0]++'
  elif ((${#tool_domains[@]})); then
    printf '%s\n' "${tool_domains[@]}" | awk '!seen[$0]++'
  fi
}

_matches_domain_filter() {
  local domain="${1,,}"
  local filter="${2,,}"
  [[ -z "$filter" ]] && return 0
  if [[ "$filter" == *"*"* || "$filter" == *"?"* ]]; then
    [[ "$domain" == $filter ]]
  else
    [[ "$domain" == *"$filter"* ]]
  fi
}

_to_epoch() {
  local t="${1:-}"
  [[ -n "$t" ]] || {
    printf '0'
    return 0
  }
  if [[ "$t" =~ ^[0-9]+$ ]]; then
    printf '%s' "$t"
    return 0
  fi
  if date -u -d "$t" +%s >/dev/null 2>&1; then
    date -u -d "$t" +%s
    return 0
  fi
  printf '0'
}

_normalize_expected_mtls() {
  local raw="${1:-}"
  local fallback="${2:-any}"
  raw="$(_trim "${raw,,}")"
  case "$raw" in
    required|on) printf 'required' ;;
    optional|optional_no_ca) printf 'optional' ;;
    any|off|none|disabled) printf 'any' ;;
    "") printf '%s' "$fallback" ;;
    *) printf '%s' "$fallback" ;;
  esac
}

_parse_bool_default() {
  local raw="${1:-}" def="${2:-1}"
  raw="$(_trim "${raw,,}")"
  case "$raw" in
    1|true|yes|on|strict|required) printf '1' ;;
    0|false|no|off|soft|relaxed) printf '0' ;;
    "") printf '%s' "$def" ;;
    *) printf '%s' "$def" ;;
  esac
}

_policy_from_conf() {
  local domain="${1:-}"
  local conf_file="${2:-}"
  local def_exp="${3:-any}"
  local def_min="${4:-14}"
  local def_san="${5:-1}"

  local exp="$def_exp" min_days="$def_min" san_strict="$def_san" source="default"
  [[ -n "$domain" ]] || {
    printf '%s|%s|%s|%s' "$exp" "$min_days" "$san_strict" "$source"
    return 0
  }

  if [[ -f "$conf_file" ]]; then
    source="conf"
    local line v
    while IFS= read -r line; do
      case "${line,,}" in
        *ssl_verify_client*on*";"*) exp="required" ;;
        *ssl_verify_client*optional_no_ca*";"*) exp="optional" ;;
        *ssl_verify_client*optional*";"*) exp="optional" ;;
        *ssl_verify_client*off*";"*) exp="any" ;;
      esac

      if [[ "$line" =~ ap_tls_expected_mtls[[:space:]:=]+([a-zA-Z_]+) ]]; then
        v="${BASH_REMATCH[1]:-}"
        exp="$(_normalize_expected_mtls "$v" "$exp")"
      fi
      if [[ "$line" =~ ap_tls_min_days[[:space:]:=]+(-?[0-9]+) ]]; then
        v="${BASH_REMATCH[1]:-}"
        if [[ "$v" =~ ^-?[0-9]+$ ]]; then
          min_days="$v"
        fi
      fi
      if [[ "$line" =~ ap_tls_san_strict[[:space:]:=]+([a-zA-Z0-9_]+) ]]; then
        v="${BASH_REMATCH[1]:-}"
        san_strict="$(_parse_bool_default "$v" "$san_strict")"
      fi
    done <"$conf_file"
  fi

  printf '%s|%s|%s|%s' "$exp" "$min_days" "$san_strict" "$source"
}

_policy_from_file() {
  local domain="${1:-}"
  local policy_file="${2:-}"
  local cur_exp="${3:-any}"
  local cur_min="${4:-14}"
  local cur_san="${5:-1}"
  local cur_source="${6:-default}"

  [[ -f "$policy_file" ]] || {
    printf '%s|%s|%s|%s' "$cur_exp" "$cur_min" "$cur_san" "$cur_source"
    return 0
  }

  local line pattern p_exp p_min p_san matched
  while IFS= read -r line; do
    line="$(_trim "$line")"
    [[ -n "$line" ]] || continue
    [[ "${line:0:1}" == "#" ]] && continue

    IFS='|' read -r pattern p_exp p_min p_san _ <<<"$line"
    pattern="$(_trim "${pattern,,}")"
    p_exp="$(_trim "${p_exp:-}")"
    p_min="$(_trim "${p_min:-}")"
    p_san="$(_trim "${p_san:-}")"
    [[ -n "$pattern" ]] || continue

    matched=0
    if [[ "$pattern" == *"*"* || "$pattern" == *"?"* ]]; then
      [[ "${domain,,}" == $pattern ]] && matched=1
    else
      [[ "${domain,,}" == "$pattern" ]] && matched=1
    fi
    ((matched == 1)) || continue

    [[ -n "$p_exp" ]] && cur_exp="$(_normalize_expected_mtls "$p_exp" "$cur_exp")"
    if [[ "$p_min" =~ ^-?[0-9]+$ ]]; then
      cur_min="$p_min"
    fi
    [[ -n "$p_san" ]] && cur_san="$(_parse_bool_default "$p_san" "$cur_san")"
    cur_source="policy_file"
    break
  done <"$policy_file"

  printf '%s|%s|%s|%s' "$cur_exp" "$cur_min" "$cur_san" "$cur_source"
}

_policy_for_domain() {
  local domain="${1:-}"
  local nginx_dir="${2:-/etc/share/vhosts/nginx}"
  local policy_file="${3:-/etc/share/state/tls-monitor-policy.tsv}"
  local def_exp="${4:-any}"
  local def_min="${5:-14}"
  local def_san="${6:-1}"

  local conf_file="${nginx_dir%/}/${domain}.conf"
  local policy
  policy="$(_policy_from_conf "$domain" "$conf_file" "$def_exp" "$def_min" "$def_san")"
  IFS='|' read -r def_exp def_min def_san _ <<<"$policy"
  _policy_from_file "$domain" "$policy_file" "$def_exp" "$def_min" "$def_san" "conf"
}

_openssl_sclient() {
  local timeout_sec="${1:-4}" retries="${2:-2}" target="${3:-127.0.0.1}" domain="${4:-}"
  shift 4 || true
  local -a extra=("$@")

  local attempt rc out
  out=""
  for ((attempt = 1; attempt <= retries; attempt++)); do
    set +e
    if _has timeout; then
      out="$(timeout "$timeout_sec" openssl s_client -connect "${target}:443" -servername "$domain" "${extra[@]}" < /dev/null 2>&1)"
      rc=$?
    else
      out="$(openssl s_client -connect "${target}:443" -servername "$domain" "${extra[@]}" < /dev/null 2>&1)"
      rc=$?
    fi
    set -e
    if ((rc == 0)); then
      printf '%s' "$out"
      return 0
    fi
    if [[ "$out" == *"BEGIN CERTIFICATE"* || "$out" == *"Verify return code:"* || "$out" == *"Protocol"* ]]; then
      printf '%s' "$out"
      return 0
    fi
  done
  printf '%s' "$out"
  return 1
}

_leaf_cert_from_output() {
  local txt="${1:-}"
  printf '%s\n' "$txt" | awk '/-----BEGIN CERTIFICATE-----/{f=1} f{print} /-----END CERTIFICATE-----/{exit}' || true
}

_extract_tls_protocol() {
  local txt="${1:-}" v
  v="$(printf '%s\n' "$txt" | sed -n 's/^[[:space:]]*Protocol[[:space:]]*:[[:space:]]*//p' | head -n1)"
  if [[ -z "$v" ]]; then
    v="$(printf '%s\n' "$txt" | sed -n 's/^New, \(TLSv[^,]*\),.*/\1/p' | head -n1)"
  fi
  [[ -n "$v" ]] || v="-"
  printf '%s' "$v"
}

_extract_tls_cipher() {
  local txt="${1:-}" v
  v="$(printf '%s\n' "$txt" | sed -n 's/^[[:space:]]*Cipher[[:space:]]*:[[:space:]]*//p' | head -n1)"
  if [[ -z "$v" ]]; then
    v="$(printf '%s\n' "$txt" | sed -n 's/.*Cipher is \(.*\)$/\1/p' | head -n1)"
  fi
  [[ -n "$v" ]] || v="-"
  printf '%s' "$v"
}

_extract_verify_code() {
  local txt="${1:-}" code
  code="$(printf '%s\n' "$txt" | sed -n 's/.*Verify return code: \([0-9][0-9]* ([^)]*)\).*/\1/p' | tail -n1)"
  [[ -n "$code" ]] || code="verify_failed"
  printf '%s' "$code"
}

_extract_ocsp_status() {
  local txt="${1:-}"
  if [[ "$txt" == *"OCSP Response Status: successful"* ]]; then
    printf 'stapled'
    return 0
  fi
  if [[ "$txt" == *"OCSP response: no response sent"* ]]; then
    printf 'none'
    return 0
  fi
  if [[ "$txt" == *"OCSP response:"* || "$txt" == *"OCSP Response Data:"* ]]; then
    printf 'present'
    return 0
  fi
  printf 'unknown'
}

_tls_version_rank() {
  local v="${1^^}"
  case "$v" in
    TLSV1.3*) printf '13' ;;
    TLSV1.2*) printf '12' ;;
    TLSV1.1*) printf '11' ;;
    TLSV1.0*|TLSV1*) printf '10' ;;
    *) printf '0' ;;
  esac
}

_state_rank() {
  case "${1:-warn}" in
    pass) printf '0' ;;
    warn) printf '1' ;;
    fail) printf '2' ;;
    *) printf '1' ;;
  esac
}

_trend_state() {
  local prev="${1:-}" now="${2:-warn}" prev_rank now_rank
  [[ -n "$prev" ]] || {
    printf 'new'
    return 0
  }
  if [[ "$prev" == "$now" ]]; then
    printf 'stable'
    return 0
  fi
  prev_rank="$(_state_rank "$prev")"
  now_rank="$(_state_rank "$now")"
  if ((now_rank > prev_rank)); then
    printf 'regressed'
  elif ((now_rank < prev_rank)); then
    printf 'improved'
  else
    printf 'changed'
  fi
}

usage() {
  cat <<'EOF'
Usage:
  monitor-tls [--json] [--domain <pattern>] [--timeout <sec>] [--retries <n>]

Examples:
  monitor-tls --json
  monitor-tls --json --domain "*.localhost"
  monitor-tls --json --domain sslcommerz --timeout 6 --retries 3
EOF
}

main() {
  local json=0 domain_filter="" timeout_sec=4 retries=2
  while [[ "${1:-}" ]]; do
    case "$1" in
      --json) json=1; shift ;;
      --domain) domain_filter="${2:-}"; shift 2 ;;
      --timeout) timeout_sec="${2:-4}"; shift 2 ;;
      --retries) retries="${2:-2}"; shift 2 ;;
      -h|--help) usage; return 0 ;;
      *) echo "Unknown arg: $1" >&2; usage; return 1 ;;
    esac
  done

  [[ "$timeout_sec" =~ ^[0-9]+$ ]] || timeout_sec=4
  ((timeout_sec < 1)) && timeout_sec=1
  ((timeout_sec > 20)) && timeout_sec=20

  [[ "$retries" =~ ^[0-9]+$ ]] || retries=2
  ((retries < 1)) && retries=1
  ((retries > 5)) && retries=5

  local project
  project="$(_infer_project)"
  local tls_target
  tls_target="$(_detect_tls_target "$project")"

  if ! _has openssl || ! _has curl; then
    printf '{"ok":false,"error":"dependency_missing","message":"openssl and curl are required.","generated_at":"%s","project":"%s"}\n' \
      "$(_json_escape "$(date -u +%Y-%m-%dT%H:%M:%SZ)")" "$(_json_escape "$project")"
    return 1
  fi

  local nginx_dir="${TLS_MONITOR_NGINX_DIR:-/etc/share/vhosts/nginx}"
  local rootca="${TLS_MONITOR_ROOTCA_FILE:-/etc/share/rootCA/rootCA.pem}"
  local client_cert="${TLS_MONITOR_CLIENT_CERT:-/etc/mkcert/nginx-client.pem}"
  local client_key="${TLS_MONITOR_CLIENT_KEY:-/etc/mkcert/nginx-client-key.pem}"
  local policy_file="${TLS_MONITOR_POLICY_FILE:-/etc/share/state/tls-monitor-policy.tsv}"

  local policy_default_mtls policy_default_min_days policy_default_san_strict
  policy_default_mtls="$(_normalize_expected_mtls "${TLS_POLICY_DEFAULT_MTLS:-any}" "any")"
  policy_default_min_days="$(_num_or_default "${TLS_POLICY_DEFAULT_MIN_DAYS:-14}" 14)"
  policy_default_san_strict="$(_parse_bool_default "${TLS_POLICY_DEFAULT_SAN_STRICT:-1}" 1)"
  local expiring_threshold
  expiring_threshold="$(_num_or_default "${TLS_EXPIRING_THRESHOLD_DAYS:-14}" 14)"
  ((expiring_threshold < 0)) && expiring_threshold=14

  local rootca_available=0
  [[ -f "$rootca" ]] && rootca_available=1
  local has_client=0
  [[ -f "$client_cert" && -f "$client_key" ]] && has_client=1

  local state_dir history_file
  state_dir="$(_state_dir)"
  history_file="${state_dir%/}/monitor-tls-history.tsv"
  touch "$history_file" >/dev/null 2>&1 || true

  declare -A prev_state=() prev_days=() prev_mtls=() prev_policy_ok=() prev_ts=()
  if [[ -s "$history_file" ]]; then
    local hts hdom hst hdays hmtls hpol
    while IFS='|' read -r hts hdom hst hdays hmtls hpol _; do
      [[ "$hts" =~ ^[0-9]+$ ]] || continue
      [[ -n "$hdom" ]] || continue
      if [[ -z "${prev_ts[$hdom]:-}" || "$hts" -gt "${prev_ts[$hdom]}" ]]; then
        prev_ts["$hdom"]="$hts"
        prev_state["$hdom"]="${hst:-}"
        prev_days["$hdom"]="${hdays:--1}"
        prev_mtls["$hdom"]="${hmtls:-}"
        prev_policy_ok["$hdom"]="${hpol:-1}"
      fi
    done <"$history_file"
  fi

  local -a domains=()
  mapfile -t domains < <(_collect_domains "$nginx_dir" 2>/dev/null | sed '/^[[:space:]]*$/d' | awk '!seen[$0]++' | sort -f)
  local -a filtered_domains=()
  local d
  for d in "${domains[@]}"; do
    if _matches_domain_filter "$d" "$domain_filter"; then
      filtered_domains+=("$d")
    fi
  done

  local total=0 pass=0 warn=0 fail=0 mtls_required=0 mtls_broken=0 expiring=0 expired=0 chain_unverified=0
  local policy_checked=0 policy_drift_count=0 tls_legacy_count=0 ocsp_missing=0 no_intermediate=0
  local state_changes=0 expiring_crossed=0 mtls_broken_crossed=0
  local -a items=() alerts=() hist_lines=()

  local now_epoch
  now_epoch="$(date -u +%s)"

  local cert subject_line subject expires_line expires_at expires_epoch days_left
  local san_block verify_out verify_code chain_ok chain_checked san_ok expiry_ok expiry_warn mtls_mode
  local curl_no_rc curl_no_code curl_mtls_rc curl_mtls_code mtls_ok no_client_ok note state
  local tls_handshake tls_brief tls_version tls_cipher ocsp_out ocsp_status ocsp_stapled
  local chain_depth intermediate_count has_intermediate version_rank posture_note
  local policy_expected policy_min_days policy_san_strict policy_ok policy_drift policy_source
  local policy_mtls_ok policy_days_ok policy_san_ok
  local prev_st prev_day prev_m prev_pol trend_state state_changed
  local broken_now broken_prev

  for d in "${filtered_domains[@]}"; do
    IFS='|' read -r policy_expected policy_min_days policy_san_strict policy_source <<<"$(_policy_for_domain "$d" "$nginx_dir" "$policy_file" "$policy_default_mtls" "$policy_default_min_days" "$policy_default_san_strict")"
    ((++policy_checked))

    tls_handshake="$(_openssl_sclient "$timeout_sec" "$retries" "$tls_target" "$d" || true)"
    cert="$(_leaf_cert_from_output "$tls_handshake")"
    tls_brief="$(_openssl_sclient "$timeout_sec" "$retries" "$tls_target" "$d" -brief || true)"
    tls_version="$(_extract_tls_protocol "$tls_brief")"
    [[ "$tls_version" == "-" ]] && tls_version="$(_extract_tls_protocol "$tls_handshake")"
    tls_cipher="$(_extract_tls_cipher "$tls_brief")"
    [[ "$tls_cipher" == "-" ]] && tls_cipher="$(_extract_tls_cipher "$tls_handshake")"

    ocsp_out="$(_openssl_sclient "$timeout_sec" "$retries" "$tls_target" "$d" -status || true)"
    ocsp_status="$(_extract_ocsp_status "$ocsp_out")"
    ocsp_stapled=0
    [[ "$ocsp_status" == "stapled" || "$ocsp_status" == "present" ]] && ocsp_stapled=1

    chain_depth="$(_num_or_default "$(printf '%s\n' "$tls_handshake" | grep -c 'BEGIN CERTIFICATE' || true)" 0)"
    if [[ -n "$cert" && "$chain_depth" -lt 1 ]]; then
      chain_depth=1
    fi
    intermediate_count=0
    if ((chain_depth > 1)); then
      intermediate_count=$((chain_depth - 1))
    fi
    has_intermediate=0
    ((intermediate_count > 0)) && has_intermediate=1

    subject="-"
    expires_at="-"
    days_left=-1
    san_ok=0
    chain_ok=0
    chain_checked=0
    expiry_ok=0
    expiry_warn=0
    mtls_mode="unknown"
    verify_code="verify_failed"

    if [[ -z "$cert" ]]; then
      state="fail"
      note="no_server_certificate"
      verify_code="no_cert"
      mtls_mode="broken"
      ((++mtls_broken))
      ((++fail))
      ((++total))

      if [[ "$ocsp_status" != "stapled" && "$ocsp_status" != "present" ]]; then
        ((++ocsp_missing))
      fi
      ((has_intermediate == 0)) && ((++no_intermediate))

      policy_mtls_ok=0
      policy_days_ok=0
      policy_san_ok=0
      policy_ok=0
      policy_drift="mtls,days,san"
      ((++policy_drift_count))
      posture_note="certificate_missing"
    else
      subject_line="$(printf '%s\n' "$cert" | openssl x509 -noout -subject 2>/dev/null || true)"
      subject="${subject_line#subject=}"
      [[ -n "$subject" ]] || subject="-"

      expires_line="$(printf '%s\n' "$cert" | openssl x509 -noout -enddate 2>/dev/null || true)"
      expires_at="${expires_line#notAfter=}"
      [[ -n "$expires_at" && "$expires_at" != "$expires_line" ]] || expires_at="-"

      if printf '%s\n' "$cert" | openssl x509 -noout -checkend 0 >/dev/null 2>&1; then
        expiry_ok=1
      else
        expiry_ok=0
        ((++expired))
      fi
      if printf '%s\n' "$cert" | openssl x509 -noout -checkend 1209600 >/dev/null 2>&1; then
        expiry_warn=0
      else
        expiry_warn=1
        ((expiry_ok)) && ((++expiring))
      fi

      if [[ "$expires_at" != "-" ]]; then
        expires_epoch="$(_to_epoch "$expires_at")"
        if [[ "$expires_epoch" =~ ^[0-9]+$ ]] && ((expires_epoch > 0)); then
          days_left=$(((expires_epoch - now_epoch) / 86400))
        fi
      fi

      san_block="$(printf '%s\n' "$cert" | openssl x509 -noout -ext subjectAltName 2>/dev/null || true)"
      local -a sans=()
      if [[ -n "$san_block" ]]; then
        mapfile -t sans < <(printf '%s\n' "$san_block" | grep -o 'DNS:[^, ]*' | sed 's/^DNS://')
      fi
      if ((${#sans[@]})); then
        local dns
        for dns in "${sans[@]}"; do
          if [[ "${dns:0:2}" == "*." ]]; then
            if [[ "$d" == *"${dns:1}" ]]; then
              san_ok=1
              break
            fi
          elif [[ "${d,,}" == "${dns,,}" ]]; then
            san_ok=1
            break
          fi
        done
      fi

      if ((rootca_available)); then
        chain_checked=1
        verify_out="$(_openssl_sclient "$timeout_sec" "$retries" "$tls_target" "$d" -CAfile "$rootca" -verify_return_error || true)"
        verify_code="$(_extract_verify_code "$verify_out")"
        if [[ "$verify_out" == *"Verify return code: 0 (ok)"* ]]; then
          chain_ok=1
          verify_code="0 (ok)"
        elif ((has_client)); then
          verify_out="$(_openssl_sclient "$timeout_sec" "$retries" "$tls_target" "$d" -CAfile "$rootca" -verify_return_error -cert "$client_cert" -key "$client_key" || true)"
          verify_code="$(_extract_verify_code "$verify_out")"
          if [[ "$verify_out" == *"Verify return code: 0 (ok)"* ]]; then
            chain_ok=1
            verify_code="0 (ok)"
          fi
        fi
      else
        verify_code="rootca_missing"
        ((++chain_unverified))
      fi

      curl_no_code="000"
      no_client_ok=0
      local try
      for ((try = 1; try <= retries; try++)); do
        set +e
        curl_no_code="$(curl -ksS --max-time "$timeout_sec" --connect-to "${d}:443:${tls_target}:443" -o /dev/null -w '%{http_code}' "https://${d}/" 2>/dev/null)"
        curl_no_rc=$?
        set -e
        [[ "$curl_no_code" =~ ^[0-9]{3}$ ]] || curl_no_code="000"
        if ((curl_no_rc == 0)) && [[ "$curl_no_code" != "000" ]]; then
          no_client_ok=1
          break
        fi
      done

      curl_mtls_code="000"
      curl_mtls_rc=1
      mtls_ok=0
      if ((has_client)); then
        for ((try = 1; try <= retries; try++)); do
          set +e
          curl_mtls_code="$(curl -ksS --max-time "$timeout_sec" --connect-to "${d}:443:${tls_target}:443" --cert "$client_cert" --key "$client_key" -o /dev/null -w '%{http_code}' "https://${d}/" 2>/dev/null)"
          curl_mtls_rc=$?
          set -e
          [[ "$curl_mtls_code" =~ ^[0-9]{3}$ ]] || curl_mtls_code="000"
          if ((curl_mtls_rc == 0)) && [[ "$curl_mtls_code" != "000" ]]; then
            mtls_ok=1
            break
          fi
        done
      fi

      if ((has_client)); then
        if ((no_client_ok)) && ((mtls_ok)); then
          mtls_mode="optional"
        elif ((!no_client_ok)) && ((mtls_ok)); then
          mtls_mode="required"
          ((++mtls_required))
        elif ((no_client_ok)) && ((!mtls_ok)); then
          mtls_mode="broken_client"
          ((++mtls_broken))
        else
          mtls_mode="broken"
          ((++mtls_broken))
        fi
      fi

      policy_mtls_ok=1
      case "$policy_expected" in
        required) [[ "$mtls_mode" == "required" ]] || policy_mtls_ok=0 ;;
        optional) [[ "$mtls_mode" == "optional" ]] || policy_mtls_ok=0 ;;
        *) policy_mtls_ok=1 ;;
      esac

      policy_days_ok=1
      if [[ "$policy_min_days" =~ ^-?[0-9]+$ ]] && ((policy_min_days >= 0)); then
        if ! [[ "$days_left" =~ ^-?[0-9]+$ ]] || ((days_left < policy_min_days)); then
          policy_days_ok=0
        fi
      fi

      policy_san_ok=1
      if ((policy_san_strict == 1 && san_ok == 0)); then
        policy_san_ok=0
      fi

      local -a drift_parts=()
      ((policy_mtls_ok == 0)) && drift_parts+=("mtls")
      ((policy_days_ok == 0)) && drift_parts+=("days")
      ((policy_san_ok == 0)) && drift_parts+=("san")
      policy_ok=1
      policy_drift="-"
      if ((${#drift_parts[@]})); then
        policy_ok=0
        policy_drift="$(IFS=','; printf '%s' "${drift_parts[*]}")"
        ((++policy_drift_count))
      fi

      version_rank="$(_tls_version_rank "$tls_version")"
      posture_note=""
      if ((version_rank > 0 && version_rank < 12)); then
        ((++tls_legacy_count))
        posture_note="legacy_protocol"
      fi
      if [[ "$ocsp_status" != "stapled" && "$ocsp_status" != "present" ]]; then
        ((++ocsp_missing))
        if [[ -z "$posture_note" ]]; then
          posture_note="ocsp_not_stapled"
        else
          posture_note+=",ocsp_not_stapled"
        fi
      fi
      if ((has_intermediate == 0)); then
        ((++no_intermediate))
        if [[ -z "$posture_note" ]]; then
          posture_note="no_intermediate"
        else
          posture_note+=",no_intermediate"
        fi
      fi
      [[ -n "$posture_note" ]] || posture_note="ok"

      state="pass"
      note="ok"
      if ((chain_checked == 1 && chain_ok == 0)); then
        state="fail"
        note="chain_invalid"
      fi
      if ((san_ok == 0)); then
        if ((policy_san_strict == 1)); then
          state="fail"
          note="san_mismatch"
        elif [[ "$state" != "fail" ]]; then
          state="warn"
          note="san_mismatch_policy_soft"
        fi
      fi
      if ((expiry_ok == 0)); then
        state="fail"
        note="certificate_expired"
      fi
      if [[ "$mtls_mode" == "broken" || "$mtls_mode" == "broken_client" ]]; then
        state="fail"
        note="mtls_handshake_failed"
      fi
      if ((version_rank > 0 && version_rank < 12)); then
        state="fail"
        note="tls_legacy_protocol"
      fi
      if [[ "$state" != "fail" && "$verify_code" == "rootca_missing" ]]; then
        state="warn"
        note="rootca_missing_chain_unverified"
      fi
      if [[ "$state" != "fail" ]] && ((expiry_warn)); then
        state="warn"
        note="certificate_expiring_soon"
      fi
      if [[ "$state" != "fail" ]] && [[ "$mtls_mode" == "unknown" ]]; then
        state="warn"
        note="client_cert_missing_for_probe"
      fi
      if [[ "$state" != "fail" ]] && ((policy_ok == 0)); then
        state="warn"
        note="policy_drift"
      fi

      case "$state" in
        pass) ((++pass)) ;;
        warn) ((++warn)) ;;
        fail) ((++fail)) ;;
      esac
      ((++total))
    fi

    prev_st="${prev_state[$d]:-}"
    prev_day="${prev_days[$d]:-}"
    prev_m="${prev_mtls[$d]:-}"
    prev_pol="${prev_policy_ok[$d]:-1}"
    trend_state="$(_trend_state "$prev_st" "$state")"
    state_changed=0
    if [[ -n "$prev_st" && "$prev_st" != "$state" ]]; then
      state_changed=1
      ((++state_changes))
      alerts+=("$d|state_change|medium|State changed from ${prev_st} to ${state}|${prev_st}|${state}")
    fi

    if [[ "$prev_day" =~ ^-?[0-9]+$ ]] && [[ "$days_left" =~ ^-?[0-9]+$ ]]; then
      if ((prev_day > expiring_threshold && days_left >= 0 && days_left <= expiring_threshold)); then
        ((++expiring_crossed))
        alerts+=("$d|expiring_threshold|high|Certificate days left dropped to ${days_left} (threshold ${expiring_threshold})|${prev_day}|${days_left}")
      fi
    fi

    broken_now=0
    [[ "$mtls_mode" == "broken" || "$mtls_mode" == "broken_client" ]] && broken_now=1
    broken_prev=0
    [[ "$prev_m" == "broken" || "$prev_m" == "broken_client" ]] && broken_prev=1
    if [[ -n "$prev_m" ]] && ((broken_prev == 0 && broken_now == 1)); then
      ((++mtls_broken_crossed))
      alerts+=("$d|mtls_broken_transition|high|mTLS transitioned to broken mode (${mtls_mode})|${prev_m}|${mtls_mode}")
    fi

    if [[ -n "$prev_st" && "$prev_pol" == "1" && "$policy_ok" == "0" ]]; then
      alerts+=("$d|policy_drift_transition|medium|Policy drift detected (${policy_drift})|policy_ok|policy_drift")
    fi

    hist_lines+=("${now_epoch}|${d}|${state}|${days_left}|${mtls_mode}|${policy_ok}")

    items+=("${d}|${subject}|${expires_at}|${days_left}|${san_ok}|${chain_ok}|${chain_checked}|${verify_code}|${mtls_mode}|${curl_no_code:-000}|${curl_mtls_code:-000}|${state}|${note}|${policy_expected}|${policy_min_days}|${policy_san_strict}|${policy_ok}|${policy_drift}|${policy_source}|${tls_version}|${tls_cipher}|${ocsp_status}|${ocsp_stapled}|${chain_depth}|${intermediate_count}|${has_intermediate}|${trend_state}|${state_changed}|${posture_note}")
  done

  if ((${#hist_lines[@]} > 0)); then
    local hline
    for hline in "${hist_lines[@]}"; do
      printf '%s\n' "$hline" >>"$history_file" 2>/dev/null || true
    done
  fi
  if [[ -s "$history_file" ]]; then
    tail -n 50000 "$history_file" >"${history_file}.tmp" 2>/dev/null || true
    if [[ -s "${history_file}.tmp" ]]; then
      mv -f "${history_file}.tmp" "$history_file"
    else
      rm -f "${history_file}.tmp" >/dev/null 2>&1 || true
    fi
  fi

  local alerts_total
  alerts_total="${#alerts[@]}"

  if ((json == 0)); then
    printf 'TLS Monitor | project=%s hosts=%d pass=%d warn=%d fail=%d mtls_required=%d mtls_broken=%d policy_drift=%d alerts=%d\n' \
      "$project" "$total" "$pass" "$warn" "$fail" "$mtls_required" "$mtls_broken" "$policy_drift_count" "$alerts_total"
    return 0
  fi

  printf '{'
  printf '"ok":true,'
  printf '"generated_at":"%s",' "$(_json_escape "$(date -u +%Y-%m-%dT%H:%M:%SZ)")"
  printf '"project":"%s",' "$(_json_escape "$project")"
  printf '"filters":{"domain":"%s","timeout":%s,"retries":%s,"target":"%s","policy_file":"%s","expiring_threshold_days":%s},' \
    "$(_json_escape "$domain_filter")" "$timeout_sec" "$retries" "$(_json_escape "$tls_target")" "$(_json_escape "$policy_file")" "$expiring_threshold"
  printf '"summary":{"hosts":%d,"pass":%d,"warn":%d,"fail":%d,"mtls_required":%d,"mtls_broken":%d,"expiring_14d":%d,"expired":%d,"chain_unverified":%d,"policy_checked":%d,"policy_drift":%d,"tls_legacy":%d,"ocsp_missing":%d,"no_intermediate":%d,"alerts":%d,"state_changes":%d,"expiring_crossed":%d,"mtls_broken_crossed":%d},' \
    "$total" "$pass" "$warn" "$fail" "$mtls_required" "$mtls_broken" "$expiring" "$expired" "$chain_unverified" "$policy_checked" "$policy_drift_count" "$tls_legacy_count" "$ocsp_missing" "$no_intermediate" "$alerts_total" "$state_changes" "$expiring_crossed" "$mtls_broken_crossed"

  printf '"alerts":['
  local af=1 aline adomain atype asev amsg afrom ato
  for aline in "${alerts[@]}"; do
    IFS='|' read -r adomain atype asev amsg afrom ato <<<"$aline"
    ((af)) || printf ','
    af=0
    printf '{'
    printf '"domain":"%s",' "$(_json_escape "$adomain")"
    printf '"type":"%s",' "$(_json_escape "$atype")"
    printf '"severity":"%s",' "$(_json_escape "$asev")"
    printf '"message":"%s",' "$(_json_escape "$amsg")"
    printf '"from":"%s",' "$(_json_escape "$afrom")"
    printf '"to":"%s"' "$(_json_escape "$ato")"
    printf '}'
  done
  printf '],'

  printf '"items":['
  local f=1 row
  local host subject exp_at dleft san chain chain_chk verify mtls no_code mtls_code
  local rstate rnote pexp pmin psan pok pdrift psrc tver tciph ocsp ostap cdepth icount hint trnd schg pnote
  for row in "${items[@]}"; do
    IFS='|' read -r host subject exp_at dleft san chain chain_chk verify mtls no_code mtls_code rstate rnote pexp pmin psan pok pdrift psrc tver tciph ocsp ostap cdepth icount hint trnd schg pnote <<<"$row"
    ((f)) || printf ','
    f=0
    printf '{'
    printf '"domain":"%s",' "$(_json_escape "$host")"
    printf '"subject":"%s",' "$(_json_escape "$subject")"
    printf '"expires_at":"%s",' "$(_json_escape "$exp_at")"
    printf '"days_left":%s,' "$(_num_or_default "$dleft" -1)"
    printf '"san_match":%s,' "$(_json_bool "$san")"
    printf '"chain_ok":%s,' "$(_json_bool "$chain")"
    printf '"chain_checked":%s,' "$(_json_bool "$chain_chk")"
    printf '"verify_code":"%s",' "$(_json_escape "$verify")"
    printf '"mtls_mode":"%s",' "$(_json_escape "$mtls")"
    printf '"http_no_client":"%s",' "$(_json_escape "$no_code")"
    printf '"http_with_client":"%s",' "$(_json_escape "$mtls_code")"
    printf '"state":"%s",' "$(_json_escape "$rstate")"
    printf '"note":"%s",' "$(_json_escape "$rnote")"
    printf '"policy_expected_mtls":"%s",' "$(_json_escape "$pexp")"
    printf '"policy_min_days":%s,' "$(_num_or_default "$pmin" -1)"
    printf '"policy_san_strict":%s,' "$(_json_bool "$psan")"
    printf '"policy_ok":%s,' "$(_json_bool "$pok")"
    printf '"policy_drift":"%s",' "$(_json_escape "$pdrift")"
    printf '"policy_source":"%s",' "$(_json_escape "$psrc")"
    printf '"tls_version":"%s",' "$(_json_escape "$tver")"
    printf '"tls_cipher":"%s",' "$(_json_escape "$tciph")"
    printf '"ocsp_status":"%s",' "$(_json_escape "$ocsp")"
    printf '"ocsp_stapled":%s,' "$(_json_bool "$ostap")"
    printf '"chain_depth":%s,' "$(_num_or_default "$cdepth" 0)"
    printf '"intermediate_count":%s,' "$(_num_or_default "$icount" 0)"
    printf '"has_intermediate":%s,' "$(_json_bool "$hint")"
    printf '"trend_state":"%s",' "$(_json_escape "$trnd")"
    printf '"state_changed":%s,' "$(_json_bool "$schg")"
    printf '"posture_note":"%s"' "$(_json_escape "$pnote")"
    printf '}'
  done
  printf ']'
  printf '}\n'
}

main "$@"
