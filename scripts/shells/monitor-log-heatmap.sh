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

_to_epoch() {
  local t="${1:-}"
  [[ -n "$t" ]] || {
    printf '0'
    return 0
  }
  if [[ "$t" =~ ^[0-9]+$ ]]; then
    if ((${#t} > 11)); then
      printf '%s' "$((t / 1000000000))"
    else
      printf '%s' "$t"
    fi
    return 0
  fi
  if date -u -d "$t" +%s >/dev/null 2>&1; then
    date -u -d "$t" +%s
    return 0
  fi
  printf '0'
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

_normalize_sig() {
  local msg="${1:-}"
  printf '%s' "$msg" |
    sed -E \
      -e 's/\x1b\[[0-9;]*m//g' \
      -e 's/^[0-9]{4}[-/][0-9]{2}[-/][0-9]{2}[[:space:]T][0-9:.+-]{8,}[[:space:]]+//' \
      -e 's/^\[[0-9]{2}\/[A-Za-z]{3}\/[0-9]{4}:[0-9]{2}:[0-9]{2}:[0-9]{2}[[:space:]][+-][0-9]{4}\][[:space:]]+//' \
      -e 's/\[([[:alpha:]]+)\][[:space:]]+[0-9]+#[0-9]+:[[:space:]]*/[\1] /g' \
      -e 's/\*[0-9]+[[:space:]]+//g' \
      -e 's/[0-9a-f]{8,}/[id]/gi' \
      -e 's/\b[0-9]{2,}\b/[num]/g' \
      -e 's#https?://[^ ]+#[url]#g' \
      -e 's#[[:space:]]+# #g' |
    tr '[:upper:]' '[:lower:]' |
    sed -E \
      -e 's/^\[num\][-/]\[num\][-/]\[num\][[:space:]]+\[num\]:\[num\]:\[num\](\.\[num\])?[[:space:]]+//' \
      -e 's/^[[:space:]]+|[[:space:]]+$//g' \
      -e 's/[|]/ /g'
}

_line_is_error() {
  local l="${1,,}"
  [[ "$l" =~ (error|fatal|exception|critical|panic|traceback|segfault|econnreset|unhandled) ]]
}

usage() {
  cat <<'EOF'
Usage:
  monitor-log-heatmap [--json] [--source <both|docker|file>] [--since <dur>] [--bucket-min <n>] [--top <n>] [--line-limit <n>]

Examples:
  monitor-log-heatmap --json
  monitor-log-heatmap --json --since 24h --bucket-min 15 --top 12 --line-limit 1000
EOF
}

main() {
  local json=0 source="both" since="24h" bucket_min=15 top_n=12 line_limit=1000
  while [[ "${1:-}" ]]; do
    case "$1" in
      --json) json=1; shift ;;
      --source) source="${2:-both}"; shift 2 ;;
      --since) since="${2:-24h}"; shift 2 ;;
      --bucket-min) bucket_min="${2:-15}"; shift 2 ;;
      --top) top_n="${2:-12}"; shift 2 ;;
      --line-limit) line_limit="${2:-1000}"; shift 2 ;;
      -h|--help) usage; return 0 ;;
      *) echo "Unknown arg: $1" >&2; usage; return 1 ;;
    esac
  done

  [[ "$bucket_min" =~ ^[0-9]+$ ]] || bucket_min=15
  [[ "$top_n" =~ ^[0-9]+$ ]] || top_n=12
  [[ "$line_limit" =~ ^[0-9]+$ ]] || line_limit=1000
  ((bucket_min < 1)) && bucket_min=1
  ((bucket_min > 120)) && bucket_min=120
  ((top_n < 1)) && top_n=1
  ((top_n > 100)) && top_n=100
  ((line_limit < 100)) && line_limit=100
  ((line_limit > 5000)) && line_limit=5000
  source="${source,,}"
  case "$source" in
    both|docker|file) ;;
    *) source="both" ;;
  esac

  if ! _has docker; then
    printf '{"ok":false,"error":"docker_missing","message":"docker command is required.","generated_at":"%s","project":"unknown"}\n' \
      "$(_json_escape "$(date -u +%Y-%m-%dT%H:%M:%SZ)")"
    return 1
  fi
  if ! docker info >/dev/null 2>&1; then
    printf '{"ok":false,"error":"docker_unreachable","message":"Docker daemon is not reachable.","generated_at":"%s","project":"unknown"}\n' \
      "$(_json_escape "$(date -u +%Y-%m-%dT%H:%M:%SZ)")"
    return 1
  fi

  local project now_epoch bucket_sec
  project="$(_infer_project)"
  now_epoch="$(date -u +%s)"
  bucket_sec=$((bucket_min * 60))

  local tmp_records
  tmp_records="$(mktemp)"
  trap 'rm -f "${tmp_records:-}"' EXIT

  # Docker logs source.
  if [[ "$source" == "both" || "$source" == "docker" ]]; then
    local -a cids=()
    if [[ "$project" != "unknown" && -n "$project" ]]; then
      mapfile -t cids < <(docker ps -aq --filter "label=com.docker.compose.project=${project}" 2>/dev/null | sed '/^[[:space:]]*$/d')
    fi
    if ((${#cids[@]} == 0)); then
      mapfile -t cids < <(docker ps -aq 2>/dev/null | sed '/^[[:space:]]*$/d')
    fi

    local inspect_raw row name service
    inspect_raw=""
    if ((${#cids[@]})); then
      inspect_raw="$(docker inspect -f '{{.Name}}|{{index .Config.Labels "com.docker.compose.service"}}' "${cids[@]}" 2>/dev/null | sed 's#^/##')"
    fi
    while IFS='|' read -r name service; do
      [[ -n "$name" ]] || continue
      [[ -n "$service" ]] || service="unknown"
      local logs line ts msg epoch bucket sig
      logs="$(docker logs --timestamps --since "$since" --tail "$line_limit" "$name" 2>/dev/null || true)"
      while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        ts="${line%% *}"
        msg="${line#* }"
        _line_is_error "$msg" || continue
        epoch="$(_to_epoch "$ts")"
        ((epoch > 0)) || epoch="$now_epoch"
        bucket=$((epoch - (epoch % bucket_sec)))
        sig="$(_normalize_sig "$msg")"
        [[ -n "$sig" ]] || sig="unknown error"
        printf '%s|%s|%s\n' "$bucket" "$service" "$sig" >>"$tmp_records"
      done <<<"$logs"
    done <<<"$inspect_raw"
  fi

  # File logs source.
  if [[ "$source" == "both" || "$source" == "file" ]]; then
    local -a roots=("/global/log" "/app/logs")
    local root f rel service_dir line ts msg epoch bucket sig
    for root in "${roots[@]}"; do
      [[ -d "$root" ]] || continue
      while IFS= read -r f; do
        [[ -f "$f" ]] || continue
        rel="${f#$root/}"
        service_dir="${rel%%/*}"
        [[ -n "$service_dir" && "$service_dir" != "$rel" ]] || service_dir="file"
        while IFS= read -r line; do
          [[ -n "$line" ]] || continue
          _line_is_error "$line" || continue

          ts=""
          if [[ "$line" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]T][0-9]{2}:[0-9]{2}:[0-9]{2}) ]]; then
            ts="${BASH_REMATCH[1]}"
          elif [[ "$line" =~ \[([0-9]{2}/[A-Za-z]{3}/[0-9]{4}:[0-9]{2}:[0-9]{2}:[0-9]{2}[[:space:]][+-][0-9]{4})\] ]]; then
            ts="${BASH_REMATCH[1]}"
          fi
          epoch="$(_to_epoch "$ts")"
          ((epoch > 0)) || epoch="$now_epoch"
          bucket=$((epoch - (epoch % bucket_sec)))
          msg="$line"
          sig="$(_normalize_sig "$msg")"
          [[ -n "$sig" ]] || sig="unknown error"
          printf '%s|%s|%s\n' "$bucket" "$service_dir" "$sig" >>"$tmp_records"
        done < <(tail -n "$line_limit" "$f" 2>/dev/null || true)
      done < <(find "$root" -type f \( -name '*.log' -o -name '*.log.*' \) 2>/dev/null)
    done
  fi

  local total_errors
  total_errors="$(wc -l <"$tmp_records" | awk '{print $1}')"
  total_errors="${total_errors:-0}"

  local -a bucket_rows=() sig_rows=() service_rows=()
  if ((total_errors > 0)); then
    mapfile -t bucket_rows < <(awk -F'|' '{c[$1]++} END{for(k in c) print k "|" c[k]}' "$tmp_records" | sort -n)
    mapfile -t sig_rows < <(awk -F'|' '{c[$3]++} END{for(k in c) print c[k] "|" k}' "$tmp_records" | sort -t'|' -k1,1nr | head -n "$top_n")
    mapfile -t service_rows < <(awk -F'|' '{c[$2]++} END{for(k in c) print c[k] "|" k}' "$tmp_records" | sort -t'|' -k1,1nr)
  fi

  if ((json == 0)); then
    printf 'Log Error Heatmap | project=%s errors=%s services=%d buckets=%d\n' \
      "$project" "$total_errors" "${#service_rows[@]}" "${#bucket_rows[@]}"
    return 0
  fi

  printf '{'
  printf '"ok":true,'
  printf '"generated_at":"%s",' "$(_json_escape "$(date -u +%Y-%m-%dT%H:%M:%SZ)")"
  printf '"project":"%s",' "$(_json_escape "$project")"
  printf '"filters":{"source":"%s","since":"%s","bucket_min":%d,"top":%d,"line_limit":%d},' \
    "$(_json_escape "$source")" "$(_json_escape "$since")" "$bucket_min" "$top_n" "$line_limit"
  printf '"summary":{"errors":%s,"services":%d,"buckets":%d,"top_signatures":%d},' \
    "$(_json_escape "$total_errors")" "${#service_rows[@]}" "${#bucket_rows[@]}" "${#sig_rows[@]}"

  printf '"buckets":['
  local f=1 r be bc biso
  for r in "${bucket_rows[@]}"; do
    IFS='|' read -r be bc <<<"$r"
    ((f)) || printf ','
    f=0
    biso="$(date -u -d "@$be" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || printf '%s' "$be")"
    printf '{"bucket_epoch":%s,"bucket":"%s","count":%s}' \
      "$(_json_escape "$be")" "$(_json_escape "$biso")" "$(_json_escape "$bc")"
  done
  printf '],'

  printf '"top_signatures":['
  f=1
  local cnt sig
  for r in "${sig_rows[@]}"; do
    IFS='|' read -r cnt sig <<<"$r"
    ((f)) || printf ','
    f=0
    printf '{"signature":"%s","count":%s}' "$(_json_escape "$sig")" "$(_json_escape "$cnt")"
  done
  printf '],'

  printf '"services":['
  f=1
  local svc
  for r in "${service_rows[@]}"; do
    IFS='|' read -r cnt svc <<<"$r"
    ((f)) || printf ','
    f=0
    printf '{'
    printf '"service":"%s",' "$(_json_escape "$svc")"
    printf '"count":%s,' "$(_json_escape "$cnt")"
    printf '"heatmap":['
    local sf=1 sr
    while IFS= read -r sr; do
      IFS='|' read -r be bc <<<"$sr"
      ((sf)) || printf ','
      sf=0
      printf '{"bucket_epoch":%s,"count":%s}' "$(_json_escape "$be")" "$(_json_escape "$bc")"
    done < <(awk -F'|' -v s="$svc" '$2==s{c[$1]++} END{for(k in c) print k "|" c[k]}' "$tmp_records" | sort -n)
    printf ']'
    printf '}'
  done
  printf ']'

  printf '}\n'
}

main "$@"
