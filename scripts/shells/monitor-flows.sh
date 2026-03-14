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

_collect_urls() {
  local f d n
  local -a urls_local=() urls_tools=()
  local nginx_dir="/etc/share/vhosts/nginx"

  if [[ -d "$nginx_dir" ]]; then
    shopt -s nullglob
    for f in "$nginx_dir"/*.conf; do
      d="$(basename -- "$f" .conf)"
      _is_valid_domain_name "$d" || continue
      urls_local+=("https://$d")
    done
    shopt -u nullglob
  fi

  if _has docker; then
    for n in SERVER_TOOLS "$(docker ps -aq --filter 'label=com.docker.compose.service=server-tools' 2>/dev/null | head -n1 || true)"; do
      [[ -n "$n" ]] || continue
      while IFS= read -r d; do
        _is_valid_domain_name "$d" || continue
        urls_tools+=("https://$d")
      done < <(docker exec "$n" domain-which --list-domains 2>/dev/null | sed '/^[[:space:]]*$/d' || true)
      ((${#urls_tools[@]})) && break
    done
  fi

  if ((${#urls_tools[@]} > ${#urls_local[@]})); then
    printf '%s\n' "${urls_tools[@]}" | awk '!seen[$0]++'
  elif ((${#urls_local[@]})); then
    printf '%s\n' "${urls_local[@]}" | awk '!seen[$0]++'
  elif ((${#urls_tools[@]})); then
    printf '%s\n' "${urls_tools[@]}" | awk '!seen[$0]++'
  fi
}

_normalize_path_specs() {
  local raw="${1:-}"
  if [[ -z "$raw" ]]; then
    raw="${MONITOR_FLOW_PATHS:-/,/login,/api/health,?/api/ping,?/health/db}"
  fi

  local -a out=()
  local token p req key
  local IFS=','
  for token in $raw; do
    token="$(printf '%s' "$token" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [[ -n "$token" ]] || continue

    req=1
    if [[ "$token" == \?* ]]; then
      req=0
      token="${token#\?}"
    elif [[ "$token" == req:* ]]; then
      req=1
      token="${token#req:}"
    elif [[ "$token" == opt:* ]]; then
      req=0
      token="${token#opt:}"
    fi

    p="$token"
    [[ "$p" == /* ]] || p="/$p"
    key="${p}|${req}"
    out+=("$key")
  done

  if ((${#out[@]} == 0)); then
    out=("/|1")
  fi
  printf '%s\n' "${out[@]}" | awk '!seen[$0]++'
}

_code_allowed_for_path() {
  local path="${1:-/}" code="${2:-0}"
  [[ "$code" =~ ^[0-9]+$ ]] || {
    return 1
  }
  if ((code >= 200 && code < 400)); then
    return 0
  fi
  case "$path" in
    /login | /login/*)
      ((code == 401 || code == 403)) && return 0
      ;;
    /api/*)
      ((code == 401 || code == 403)) && return 0
      ;;
  esac
  return 1
}

_path_to_flow() {
  local p="${1:-/}"
  if [[ "$p" == "/" ]]; then
    printf 'root'
    return 0
  fi
  local s="${p#/}"
  s="${s//\//_}"
  s="${s//[^a-zA-Z0-9_]/_}"
  while [[ "$s" == *__* ]]; do
    s="${s//__/_}"
  done
  s="${s##_}"
  s="${s%%_}"
  [[ -n "$s" ]] || s="path"
  printf '%s' "${s,,}"
}

_state_from_result() {
  local required="${1:-0}" path="${2:-/}" code="${3:-0}" curl_rc="${4:-1}"
  if ((required)); then
    if ((curl_rc == 0)) && _code_allowed_for_path "$path" "$code"; then
      printf 'pass'
    else
      printf 'fail'
    fi
    return 0
  fi

  if ((curl_rc == 0)) && _code_allowed_for_path "$path" "$code"; then
    printf 'pass'
    return 0
  fi
  if ((code == 404)); then
    printf 'skip'
    return 0
  fi
  if ((curl_rc != 0)); then
    printf 'warn'
    return 0
  fi
  if ((code >= 500)); then
    printf 'warn'
    return 0
  fi
  printf 'warn'
}

_note_from_result() {
  local state="${1:-warn}" code="${2:-0}" curl_rc="${3:-1}"
  if ((curl_rc != 0)); then
    printf 'curl_error'
    return 0
  fi
  case "$state" in
    pass) printf 'ok' ;;
    skip) printf 'optional_not_present' ;;
    fail)
      if ((code == 000 || code == 0)); then
        printf 'unreachable'
      else
        printf 'required_failed'
      fi
      ;;
    *) printf 'degraded' ;;
  esac
}

usage() {
  cat <<'EOF'
Usage:
  monitor-flows [--json] [--domain <host>] [--paths <csv>] [--timeout <sec>]

Examples:
  monitor-flows --json
  monitor-flows --json --domain web.localhost --paths "/,/login,/api/health,?/api/ping,?/health/db"
EOF
}

main() {
  local json=0 domain_filter="" paths_csv="" timeout_sec=4
  while [[ "${1:-}" ]]; do
    case "$1" in
      --json) json=1; shift ;;
      --domain) domain_filter="${2:-}"; shift 2 ;;
      --paths) paths_csv="${2:-}"; shift 2 ;;
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

  if ! _has curl; then
    printf '{"ok":false,"error":"curl_missing","message":"curl command is required.","generated_at":"%s","project":"%s"}\n' \
      "$(_json_escape "$(date -u +%Y-%m-%dT%H:%M:%SZ)")" "$(_json_escape "$project")"
    return 1
  fi

  local -a urls=()
  mapfile -t urls < <(_collect_urls 2>/dev/null || true)

  local -a path_specs=()
  mapfile -t path_specs < <(_normalize_path_specs "$paths_csv")

  local -a domains=()
  local u host
  for u in "${urls[@]}"; do
    host="${u#https://}"
    [[ -n "$domain_filter" && "${host,,}" != "${domain_filter,,}" ]] && continue
    domains+=("$host")
  done
  if ((${#domains[@]})); then
    mapfile -t domains < <(printf '%s\n' "${domains[@]}" | awk '!seen[$0]++')
  fi

  local pass=0 warn=0 fail=0 skip=0 total=0
  local -a items=() times=()
  local path_spec path flow required url raw code tsec tms state note curl_rc
  for host in "${domains[@]}"; do
    for path_spec in "${path_specs[@]}"; do
      IFS='|' read -r path required <<<"$path_spec"
      [[ "$required" == "0" ]] || required=1
      flow="$(_path_to_flow "$path")"

      url="https://${host}${path}"
      set +e
      raw="$(curl -ksS --max-time "$timeout_sec" --resolve "${host}:443:127.0.0.1" -o /dev/null -w '%{http_code}|%{time_total}' "$url" 2>/dev/null)"
      curl_rc=$?
      set -e

      code="${raw%%|*}"
      tsec="${raw#*|}"
      [[ "$code" =~ ^[0-9]{3}$ ]] || code="000"
      [[ "$tsec" =~ ^[0-9]+([.][0-9]+)?$ ]] || tsec="0"
      tms="$(awk -v t="$tsec" 'BEGIN{printf "%.0f", t*1000}')"
      [[ "$tms" =~ ^[0-9]+$ ]] || tms=0

      state="$(_state_from_result "$required" "$path" "$code" "$curl_rc")"
      note="$(_note_from_result "$state" "$code" "$curl_rc")"

      case "$state" in
        pass) ((++pass)) ;;
        warn) ((++warn)) ;;
        fail) ((++fail)) ;;
        skip) ((++skip)) ;;
      esac
      ((++total))
      ((tms > 0)) && times+=("$tms")

      items+=("$host|$flow|$path|$required|$state|$code|$tms|$note|$url")
    done
  done

  local avg_ms=0 p95_ms=0
  if ((${#times[@]})); then
    avg_ms="$(printf '%s\n' "${times[@]}" | awk '{s+=$1;n++} END{if(n>0) printf "%.0f", s/n; else print 0}')"
    local -a ts=()
    mapfile -t ts < <(printf '%s\n' "${times[@]}" | sort -n)
    local n="${#ts[@]}" idx
    idx=$(( (95 * n + 99) / 100 - 1 ))
    ((idx < 0)) && idx=0
    ((idx >= n)) && idx=$((n - 1))
    p95_ms="${ts[$idx]}"
  fi

  if ((json == 0)); then
    printf 'Synthetic Flows | project=%s domains=%d checks=%d pass=%d warn=%d fail=%d skip=%d avg=%sms p95=%sms\n' \
      "$project" "${#domains[@]}" "$total" "$pass" "$warn" "$fail" "$skip" "$avg_ms" "$p95_ms"
    return 0
  fi

  printf '{'
  printf '"ok":true,'
  printf '"generated_at":"%s",' "$(_json_escape "$(date -u +%Y-%m-%dT%H:%M:%SZ)")"
  printf '"project":"%s",' "$(_json_escape "$project")"
  printf '"filters":{'
  printf '"domain":"%s",' "$(_json_escape "$domain_filter")"
  printf '"timeout":%s,' "$timeout_sec"
  printf '"paths":['
  local f=1
  local path_entry req_bit
  for path_entry in "${path_specs[@]}"; do
    IFS='|' read -r path req_bit <<<"$path_entry"
    ((f)) || printf ','
    f=0
    if [[ "$req_bit" == "0" ]]; then
      printf '"%s"' "$(_json_escape "?${path}")"
    else
      printf '"%s"' "$(_json_escape "$path")"
    fi
  done
  printf ']},'
  printf '"summary":{'
  printf '"domains":%d,"checks":%d,"pass":%d,"warn":%d,"fail":%d,"skip":%d,"avg_ms":%s,"p95_ms":%s' \
    "${#domains[@]}" "$total" "$pass" "$warn" "$fail" "$skip" "${avg_ms:-0}" "${p95_ms:-0}"
  printf '},'
  printf '"items":['
  f=1
  local row req
  for row in "${items[@]}"; do
    IFS='|' read -r host flow path req state code tms note url <<<"$row"
    ((f)) || printf ','
    f=0
    printf '{'
    printf '"domain":"%s",' "$(_json_escape "$host")"
    printf '"flow":"%s",' "$(_json_escape "$flow")"
    printf '"path":"%s",' "$(_json_escape "$path")"
    printf '"required":%s,' "$([[ "$req" == "1" ]] && printf 'true' || printf 'false')"
    printf '"state":"%s",' "$(_json_escape "$state")"
    printf '"code":"%s",' "$(_json_escape "$code")"
    printf '"time_ms":%s,' "${tms:-0}"
    printf '"note":"%s",' "$(_json_escape "$note")"
    printf '"url":"%s"' "$(_json_escape "$url")"
    printf '}'
  done
  printf ']'
  printf '}\n'
}

main "$@"
