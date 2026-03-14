#!/usr/bin/env bash
set -euo pipefail

_has() {
  command -v "$1" >/dev/null 2>&1
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

_collect_domains() {
  local f d n
  local -a local_domains=() tool_domains=()
  local nginx_dir="/etc/share/vhosts/nginx"

  if [[ -d "$nginx_dir" ]]; then
    shopt -s nullglob
    for f in "$nginx_dir"/*.conf; do
      d="$(basename -- "$f" .conf)"
      _is_valid_domain_name "$d" || continue
      local_domains+=("$d")
    done
    shopt -u nullglob
  fi

  if _has docker; then
    for n in SERVER_TOOLS "$(docker ps -aq --filter 'label=com.docker.compose.service=server-tools' 2>/dev/null | head -n1 || true)"; do
      [[ -n "$n" ]] || continue
      while IFS= read -r d; do
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

_extract_leaf_cert() {
  local domain="${1:-}"
  local extra_args="${2:-}"
  # shellcheck disable=SC2086
  echo | openssl s_client -connect 127.0.0.1:443 -servername "$domain" -showcerts $extra_args 2>/dev/null |
    awk '/-----BEGIN CERTIFICATE-----/{f=1} f{print} /-----END CERTIFICATE-----/{exit}' || true
}

_domain_matches_san() {
  local domain="${1:-}" dns_name="${2:-}"
  [[ -n "$domain" && -n "$dns_name" ]] || return 1
  if [[ "${dns_name:0:2}" == "*." ]]; then
    local suffix="${dns_name:1}"
    [[ "$domain" == *"$suffix" ]] && return 0
    return 1
  fi
  [[ "${domain,,}" == "${dns_name,,}" ]]
}

_san_matches_any() {
  local domain="${1:-}"
  shift || true
  local dns
  for dns in "$@"; do
    _domain_matches_san "$domain" "$dns" && return 0
  done
  return 1
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

usage() {
  cat <<'EOF'
Usage:
  monitor-tls [--json] [--domain <host>] [--timeout <sec>]

Examples:
  monitor-tls --json
  monitor-tls --json --domain web.localhost
EOF
}

main() {
  local json=0 domain_filter="" timeout_sec=4
  while [[ "${1:-}" ]]; do
    case "$1" in
      --json) json=1; shift ;;
      --domain) domain_filter="${2:-}"; shift 2 ;;
      --timeout) timeout_sec="${2:-4}"; shift 2 ;;
      -h|--help) usage; return 0 ;;
      *) echo "Unknown arg: $1" >&2; usage; return 1 ;;
    esac
  done

  if ! [[ "$timeout_sec" =~ ^[0-9]+$ ]]; then
    timeout_sec=4
  fi
  ((timeout_sec < 1)) && timeout_sec=1
  ((timeout_sec > 20)) && timeout_sec=20

  local project
  project="$(_infer_project)"

  if ! _has openssl || ! _has curl; then
    printf '{"ok":false,"error":"dependency_missing","message":"openssl and curl are required.","generated_at":"%s","project":"%s"}\n' \
      "$(_json_escape "$(date -u +%Y-%m-%dT%H:%M:%SZ)")" "$(_json_escape "$project")"
    return 1
  fi

  local rootca="/etc/share/rootCA/rootCA.pem"
  local rootca_available=0
  [[ -f "$rootca" ]] && rootca_available=1

  local client_cert="/etc/mkcert/nginx-client.pem"
  local client_key="/etc/mkcert/nginx-client-key.pem"
  local has_client=0
  [[ -f "$client_cert" && -f "$client_key" ]] && has_client=1

  local -a domains=()
  mapfile -t domains < <(_collect_domains 2>/dev/null || true)
  if [[ -n "$domain_filter" ]]; then
    local -a filtered=()
    local d
    for d in "${domains[@]}"; do
      [[ "${d,,}" == "${domain_filter,,}" ]] && filtered+=("$d")
    done
    domains=("${filtered[@]}")
  fi

  local total=0 pass=0 warn=0 fail=0 mtls_required=0 mtls_broken=0 expiring=0 expired=0 chain_unverified=0
  local -a items=()

  local d cert subject_line subject expires_line expires_at expires_epoch now_epoch days_left
  local san_block verify_out verify_code chain_ok chain_checked san_ok expiry_ok expiry_warn mtls_mode
  local curl_no_rc curl_no_code curl_mtls_rc curl_mtls_code mtls_ok no_client_ok note state
  for d in "${domains[@]}"; do
    cert="$(_extract_leaf_cert "$d")"
    subject="-"
    expires_at="-"
    days_left=-1
    san_ok=0
    chain_ok=0
    chain_checked=0
    expiry_ok=0
    expiry_warn=0
    mtls_mode="unknown"
    note=""

    if [[ -z "$cert" ]]; then
      state="fail"
      note="no_server_certificate"
      verify_code="no_cert"
      mtls_mode="broken"
      ((++mtls_broken))
      ((++fail))
      ((++total))
      items+=("$d|$subject|$expires_at|$days_left|0|0|0|$verify_code|$mtls_mode|000|000|$state|$note")
      continue
    fi

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
      now_epoch="$(date -u +%s)"
      if [[ "$expires_epoch" =~ ^[0-9]+$ ]] && ((expires_epoch > 0)); then
        days_left=$(( (expires_epoch - now_epoch) / 86400 ))
      fi
    fi

    san_block="$(printf '%s\n' "$cert" | openssl x509 -noout -ext subjectAltName 2>/dev/null || true)"
    local -a sans=()
    if [[ -n "$san_block" ]]; then
      mapfile -t sans < <(printf '%s\n' "$san_block" | grep -o 'DNS:[^, ]*' | sed 's/^DNS://')
    fi
    if ((${#sans[@]})); then
      if _san_matches_any "$d" "${sans[@]}"; then
        san_ok=1
      fi
    fi

    if ((rootca_available)); then
      chain_checked=1
      verify_out="$(echo | openssl s_client -connect 127.0.0.1:443 -servername "$d" -CAfile "$rootca" -verify_return_error 2>&1 || true)"
      verify_code="$(printf '%s\n' "$verify_out" | sed -n 's/.*Verify return code: \([0-9][0-9]* ([^)]*)\).*/\1/p' | tail -n1)"
      if [[ "$verify_out" == *"Verify return code: 0 (ok)"* ]]; then
        chain_ok=1
        verify_code="0 (ok)"
      elif ((has_client)); then
        verify_out="$(echo | openssl s_client -connect 127.0.0.1:443 -servername "$d" -CAfile "$rootca" -verify_return_error -cert "$client_cert" -key "$client_key" 2>&1 || true)"
        verify_code="$(printf '%s\n' "$verify_out" | sed -n 's/.*Verify return code: \([0-9][0-9]* ([^)]*)\).*/\1/p' | tail -n1)"
        if [[ "$verify_out" == *"Verify return code: 0 (ok)"* ]]; then
          chain_ok=1
          verify_code="0 (ok)"
        fi
      fi
      [[ -n "$verify_code" ]] || verify_code="verify_failed"
    else
      verify_code="rootca_missing"
      ((++chain_unverified))
    fi

    set +e
    curl_no_code="$(curl -ksS --max-time "$timeout_sec" --resolve "${d}:443:127.0.0.1" -o /dev/null -w '%{http_code}' "https://${d}/" 2>/dev/null)"
    curl_no_rc=$?
    set -e
    [[ "$curl_no_code" =~ ^[0-9]{3}$ ]] || curl_no_code="000"
    no_client_ok=0
    ((curl_no_rc == 0)) && [[ "$curl_no_code" != "000" ]] && no_client_ok=1

    curl_mtls_code="000"
    curl_mtls_rc=1
    mtls_ok=0
    if ((has_client)); then
      set +e
      curl_mtls_code="$(curl -ksS --max-time "$timeout_sec" --resolve "${d}:443:127.0.0.1" --cert "$client_cert" --key "$client_key" -o /dev/null -w '%{http_code}' "https://${d}/" 2>/dev/null)"
      curl_mtls_rc=$?
      set -e
      [[ "$curl_mtls_code" =~ ^[0-9]{3}$ ]] || curl_mtls_code="000"
      ((curl_mtls_rc == 0)) && [[ "$curl_mtls_code" != "000" ]] && mtls_ok=1
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

    state="pass"
    note="ok"
    if ((chain_checked == 1 && chain_ok == 0)); then
      state="fail"
      note="chain_invalid"
    fi
    if ((san_ok == 0)); then
      state="fail"
      note="san_mismatch"
    fi
    if ((expiry_ok == 0)); then
      state="fail"
      note="certificate_expired"
    fi
    if [[ "$mtls_mode" == "broken" || "$mtls_mode" == "broken_client" ]]; then
      state="fail"
      note="mtls_handshake_failed"
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

    case "$state" in
      pass) ((++pass)) ;;
      warn) ((++warn)) ;;
      fail) ((++fail)) ;;
    esac
    ((++total))

    items+=("$d|$subject|$expires_at|$days_left|$san_ok|$chain_ok|$chain_checked|$verify_code|$mtls_mode|$curl_no_code|$curl_mtls_code|$state|$note")
  done

  if ((json == 0)); then
    printf 'TLS Monitor | project=%s hosts=%d pass=%d warn=%d fail=%d mtls_required=%d expiring=%d expired=%d\n' \
      "$project" "$total" "$pass" "$warn" "$fail" "$mtls_required" "$expiring" "$expired"
    return 0
  fi

  printf '{'
  printf '"ok":true,'
  printf '"generated_at":"%s",' "$(_json_escape "$(date -u +%Y-%m-%dT%H:%M:%SZ)")"
  printf '"project":"%s",' "$(_json_escape "$project")"
  printf '"filters":{"domain":"%s","timeout":%s},' "$(_json_escape "$domain_filter")" "$timeout_sec"
  printf '"summary":{"hosts":%d,"pass":%d,"warn":%d,"fail":%d,"mtls_required":%d,"mtls_broken":%d,"expiring_14d":%d,"expired":%d,"chain_unverified":%d},' \
    "$total" "$pass" "$warn" "$fail" "$mtls_required" "$mtls_broken" "$expiring" "$expired" "$chain_unverified"
  printf '"items":['
  local f=1 row
  local host subject exp_at dleft san chain chain_checked verify mtls no_code mtls_code state note
  for row in "${items[@]}"; do
    IFS='|' read -r host subject exp_at dleft san chain chain_checked verify mtls no_code mtls_code state note <<<"$row"
    ((f)) || printf ','
    f=0
    printf '{'
    printf '"domain":"%s",' "$(_json_escape "$host")"
    printf '"subject":"%s",' "$(_json_escape "$subject")"
    printf '"expires_at":"%s",' "$(_json_escape "$exp_at")"
    printf '"days_left":%s,' "${dleft:--1}"
    printf '"san_match":%s,' "$([[ "$san" == "1" ]] && printf true || printf false)"
    printf '"chain_ok":%s,' "$([[ "$chain" == "1" ]] && printf true || printf false)"
    printf '"chain_checked":%s,' "$([[ "$chain_checked" == "1" ]] && printf true || printf false)"
    printf '"verify_code":"%s",' "$(_json_escape "$verify")"
    printf '"mtls_mode":"%s",' "$(_json_escape "$mtls")"
    printf '"http_no_client":"%s",' "$(_json_escape "$no_code")"
    printf '"http_with_client":"%s",' "$(_json_escape "$mtls_code")"
    printf '"state":"%s",' "$(_json_escape "$state")"
    printf '"note":"%s"' "$(_json_escape "$note")"
    printf '}'
  done
  printf ']'
  printf '}\n'
}

main "$@"
