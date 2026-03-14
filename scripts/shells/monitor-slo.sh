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

_num_or_default() {
  local v="${1:-}" d="${2:-0}"
  if [[ "$v" =~ ^-?[0-9]+$ ]]; then
    printf '%s' "$v"
  else
    printf '%s' "$d"
  fi
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

_service_for_domain() {
  local domain="${1:-}" conf app
  [[ -n "$domain" ]] || {
    printf 'unknown'
    return 0
  }
  conf="/etc/share/vhosts/nginx/${domain}.conf"
  if [[ -f "$conf" ]]; then
    app="$(grep -m1 '^# LDS-META: app=' "$conf" 2>/dev/null | sed 's/^# LDS-META: app=//')"
    if [[ -n "$app" ]]; then
      printf '%s' "${app,,}"
      return 0
    fi
  fi
  printf 'unknown'
}

_pct_x100() {
  local a="${1:-0}" b="${2:-0}"
  if ! [[ "$a" =~ ^[0-9]+$ && "$b" =~ ^[0-9]+$ ]] || ((b == 0)); then
    printf '0'
    return 0
  fi
  printf '%s' $((a * 10000 / b))
}

usage() {
  cat <<'EOF'
Usage:
  monitor-slo [--json] [--timeout <sec>] [--paths <csv>]

Examples:
  monitor-slo --json
  monitor-slo --json --timeout 4 --paths "/,/login,/api/health,?/api/ping,?/health/db"
EOF
}

main() {
  local json=0 timeout_sec=4 paths=""
  while [[ "${1:-}" ]]; do
    case "$1" in
      --json) json=1; shift ;;
      --timeout) timeout_sec="${2:-4}"; shift 2 ;;
      --paths) paths="${2:-}"; shift 2 ;;
      -h|--help) usage; return 0 ;;
      *) echo "Unknown arg: $1" >&2; usage; return 1 ;;
    esac
  done

  [[ "$timeout_sec" =~ ^[0-9]+$ ]] || timeout_sec=4
  ((timeout_sec < 1)) && timeout_sec=1
  ((timeout_sec > 20)) && timeout_sec=20
  [[ -n "$paths" ]] || paths="/,/login,/api/health,?/api/ping,?/health/db"

  if ! _has gawk; then
    printf '{"ok":false,"error":"gawk_missing","message":"gawk is required.","generated_at":"%s"}\n' \
      "$(_json_escape "$(date -u +%Y-%m-%dT%H:%M:%SZ)")"
    return 1
  fi

  local project
  project="$(_infer_project)"

  local history_file="/etc/share/state/monitor-slo-history.tsv"
  mkdir -p /etc/share/state >/dev/null 2>&1 || true
  touch "$history_file" >/dev/null 2>&1 || true

  local now_epoch
  now_epoch="$(date -u +%s)"

  local flow_json
  flow_json="$(monitor-flows --json --timeout "$timeout_sec" --paths "$paths" 2>/dev/null || true)"
  if [[ -n "$flow_json" ]]; then
    local item_line domain state code tms flow required ok
    while IFS='|' read -r domain state code tms flow required; do
      [[ -n "$domain" ]] || continue
      ok=0
      if [[ "$state" == "pass" ]]; then
        ok=1
      fi
      printf '%s|%s|%s|%s|%s|%s|%s|%s\n' \
        "$now_epoch" "$domain" "$state" "$code" "$tms" "$flow" "$required" "$ok" >>"$history_file"
    done < <(
      printf '%s' "$flow_json" |
        jq -r '.items[]? | [.domain,.state,.code,((.time_ms // 0)|tostring),.flow,((.required // false)|tostring)] | @tsv' 2>/dev/null |
        tr '\t' '|'
    )
  fi

  # Keep only last 8 days.
  awk -F'|' -v min_ts="$((now_epoch - 8 * 86400))" '($1+0)>=min_ts {print}' "$history_file" >"${history_file}.tmp" 2>/dev/null || true
  if [[ -s "${history_file}.tmp" ]]; then
    mv -f "${history_file}.tmp" "$history_file"
  else
    rm -f "${history_file}.tmp" >/dev/null 2>&1 || true
  fi

  local -a windows=("1h|3600" "24h|86400" "7d|604800")
  local -a items=()
  local -a summaries=()
  local w label sec start_ts domain_lines line domain total ok err p95 avg service uptime_x100 err_x100
  for w in "${windows[@]}"; do
    IFS='|' read -r label sec <<<"$w"
    start_ts=$((now_epoch - sec))
    mapfile -t domain_lines < <(
      gawk -F'|' -v min_ts="$start_ts" '
        ($1+0)>=min_ts {
          d=$2
          total[d]++
          if (($8+0)==1) ok[d]++
          if (($8+0)==0 && $3!="skip") err[d]++
          if (($5+0)>0) { lat[d]=lat[d] " " ($5+0) }
        }
        END{
          for (d in total) {
            n=split(lat[d],a," ")
            c=0
            delete x
            for(i=1;i<=n;i++){ if(a[i]!=""){ c++; x[c]=a[i] } }
            if(c>0){
              asort(x)
              idx=int((95*c + 99)/100)
              if(idx<1) idx=1
              if(idx>c) idx=c
              p95=x[idx]
              s=0
              for(i=1;i<=c;i++) s+=x[i]
              avg=int(s/c)
            } else {
              p95=0
              avg=0
            }
            print d "|" total[d] "|" (ok[d]+0) "|" (err[d]+0) "|" p95 "|" avg
          }
        }' "$history_file" 2>/dev/null | sort
    )

    local sum_total=0 sum_ok=0 sum_err=0
    for line in "${domain_lines[@]}"; do
      IFS='|' read -r domain total ok err p95 avg <<<"$line"
      total="$(_num_or_default "$total" 0)"
      ok="$(_num_or_default "$ok" 0)"
      err="$(_num_or_default "$err" 0)"
      p95="$(_num_or_default "$p95" 0)"
      avg="$(_num_or_default "$avg" 0)"
      service="$(_service_for_domain "$domain")"
      uptime_x100="$(_pct_x100 "$ok" "$total")"
      err_x100="$(_pct_x100 "$err" "$total")"
      items+=("$label|$domain|$service|$total|$ok|$err|$uptime_x100|$err_x100|$p95|$avg")
      sum_total=$((sum_total + total))
      sum_ok=$((sum_ok + ok))
      sum_err=$((sum_err + err))
    done
    summaries+=("$label|$sum_total|$sum_ok|$sum_err|$(_pct_x100 "$sum_ok" "$sum_total")|$(_pct_x100 "$sum_err" "$sum_total")")
  done

  if ((json == 0)); then
    local h1
    h1="$(printf '%s\n' "${summaries[@]}" | awk -F'|' '$1=="1h"{print $0; exit}')"
    if [[ -n "$h1" ]]; then
      IFS='|' read -r _ t o e up er <<<"$h1"
      printf 'SLO View | project=%s checks_1h=%s uptime_1h=%.2f%% error_1h=%.2f%%\n' \
        "$project" "$t" "$(awk -v v="$up" 'BEGIN{printf "%.2f", v/100}')" "$(awk -v v="$er" 'BEGIN{printf "%.2f", v/100}')"
    else
      printf 'SLO View | project=%s no_data\n' "$project"
    fi
    return 0
  fi

  printf '{'
  printf '"ok":true,'
  printf '"generated_at":"%s",' "$(_json_escape "$(date -u +%Y-%m-%dT%H:%M:%SZ)")"
  printf '"project":"%s",' "$(_json_escape "$project")"
  printf '"filters":{"timeout":%d,"paths":"%s"},' "$timeout_sec" "$(_json_escape "$paths")"
  printf '"summary":{"windows":['
  local f=1 s
  for s in "${summaries[@]}"; do
    IFS='|' read -r label total ok err uptime_x100 err_x100 <<<"$s"
    ((f)) || printf ','
    f=0
    printf '{'
    printf '"window":"%s",' "$(_json_escape "$label")"
    printf '"checks":%s,' "$(_num_or_default "$total" 0)"
    printf '"ok":%s,' "$(_num_or_default "$ok" 0)"
    printf '"error":%s,' "$(_num_or_default "$err" 0)"
    printf '"uptime_pct_x100":%s,' "$(_num_or_default "$uptime_x100" 0)"
    printf '"error_rate_pct_x100":%s' "$(_num_or_default "$err_x100" 0)"
    printf '}'
  done
  printf ']},'
  printf '"items":['
  f=1
  local it
  for it in "${items[@]}"; do
    IFS='|' read -r label domain service total ok err uptime_x100 err_x100 p95 avg <<<"$it"
    ((f)) || printf ','
    f=0
    printf '{'
    printf '"window":"%s",' "$(_json_escape "$label")"
    printf '"domain":"%s",' "$(_json_escape "$domain")"
    printf '"service":"%s",' "$(_json_escape "$service")"
    printf '"checks":%s,' "$(_num_or_default "$total" 0)"
    printf '"ok":%s,' "$(_num_or_default "$ok" 0)"
    printf '"error":%s,' "$(_num_or_default "$err" 0)"
    printf '"uptime_pct_x100":%s,' "$(_num_or_default "$uptime_x100" 0)"
    printf '"error_rate_pct_x100":%s,' "$(_num_or_default "$err_x100" 0)"
    printf '"p95_ms":%s,' "$(_num_or_default "$p95" 0)"
    printf '"avg_ms":%s' "$(_num_or_default "$avg" 0)"
    printf '}'
  done
  printf ']'
  printf '}\n'
}

main "$@"
