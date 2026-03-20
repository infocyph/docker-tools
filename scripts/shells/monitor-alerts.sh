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

_cmp() {
  local op="${1:-}" a="${2:-0}" b="${3:-0}"
  a="$(_num_or_default "$a" 0)"
  b="$(_num_or_default "$b" 0)"
  case "$op" in
    '>') ((a > b)) ;;
    '>=') ((a >= b)) ;;
    '<') ((a < b)) ;;
    '<=') ((a <= b)) ;;
    '==') ((a == b)) ;;
    '!=') ((a != b)) ;;
    *) return 1 ;;
  esac
}

_quiet_hours_active() {
  local enabled="${1:-false}" start="${2:-23:00}" end="${3:-07:00}"
  [[ "${enabled,,}" == "true" ]] || return 1
  local now hm s e
  now="$(date +%H:%M)"
  hm="$(date +%H%M)"
  s="$(printf '%s' "$start" | tr -d ':')"
  e="$(printf '%s' "$end" | tr -d ':')"
  if [[ -z "$s" || -z "$e" ]]; then
    return 1
  fi
  hm=$((10#$hm))
  s=$((10#$s))
  e=$((10#$e))
  if ((s < e)); then
    ((hm >= s && hm < e))
  else
    ((hm >= s || hm < e))
  fi
}

_tsv_get() {
  local file="${1:-}" r="${2:-}" f="${3:-}"
  [[ -f "$file" ]] || return 0
  awk -F'|' -v r="$r" -v f="$f" '$1==r && $2==f{print $3; exit}' "$file" 2>/dev/null || true
}

_tsv_upsert() {
  local file="${1:-}" r="${2:-}" f="${3:-}" v="${4:-}"
  touch "$file" >/dev/null 2>&1 || true
  awk -F'|' -v r="$r" -v f="$f" -v v="$v" '
    BEGIN{done=0}
    {
      if ($1==r && $2==f) {
        print r "|" f "|" v
        done=1
      } else {
        print $0
      }
    }
    END{
      if (!done) print r "|" f "|" v
    }' "$file" >"${file}.tmp" 2>/dev/null || true
  if [[ -s "${file}.tmp" ]]; then
    mv -f "${file}.tmp" "$file"
  else
    rm -f "${file}.tmp" >/dev/null 2>&1 || true
  fi
}

_metric_from_json() {
  local cmd="${1:-}" jq_expr="${2:-}"
  local out
  out="$($cmd 2>/dev/null || true)"
  if [[ -z "$out" ]]; then
    printf '0'
    return 0
  fi
  printf '%s' "$out" | jq -r "$jq_expr // 0" 2>/dev/null | awk '{print int($1)}' 2>/dev/null || printf '0'
}

usage() {
  cat <<'EOF'
Usage:
  monitor-alerts [--json] [--run] [--ack <rule_id>] [--fingerprint <fp>]

Examples:
  monitor-alerts --json
  monitor-alerts --run
  monitor-alerts --ack runtime_fail
EOF
}

main() {
  local json=0 run_mode=0 ack_rule="" ack_fp=""
  while [[ "${1:-}" ]]; do
    case "$1" in
      --json) json=1; shift ;;
      --run) run_mode=1; shift ;;
      --ack) ack_rule="${2:-}"; shift 2 ;;
      --fingerprint) ack_fp="${2:-}"; shift 2 ;;
      -h|--help) usage; return 0 ;;
      *) echo "Unknown arg: $1" >&2; usage; return 1 ;;
    esac
  done

  if ! _has jq; then
    printf '{"ok":false,"error":"jq_missing","message":"jq is required.","generated_at":"%s"}\n' \
      "$(_json_escape "$(date -u +%Y-%m-%dT%H:%M:%SZ)")"
    return 1
  fi

  local state_dir rules_file sent_file ack_file
  state_dir="/etc/share/state"
  rules_file="${state_dir}/alerts-rules.json"
  sent_file="${state_dir}/alerts-sent.tsv"
  ack_file="${state_dir}/alerts-acks.tsv"
  mkdir -p "$state_dir" >/dev/null 2>&1 || true
  touch "$sent_file" "$ack_file" >/dev/null 2>&1 || true

  if [[ ! -f "$rules_file" ]]; then
    cat >"$rules_file" <<'JSON'
{
  "quiet_hours": { "enabled": false, "start": "23:00", "end": "07:00" },
  "channels": { "desktop": true, "webhook_url": "" },
  "rules": [
    { "id": "runtime_fail", "metric": "runtime.fail", "op": ">", "threshold": 0, "severity": "high", "cooldown_sec": 300, "message": "Runtime failures detected" },
    { "id": "tls_fail", "metric": "tls.fail", "op": ">", "threshold": 0, "severity": "high", "cooldown_sec": 300, "message": "TLS/mTLS failures detected" },
    { "id": "db_fail", "metric": "db.fail", "op": ">", "threshold": 0, "severity": "high", "cooldown_sec": 300, "message": "DB/Redis health failures detected" },
    { "id": "queue_fail", "metric": "queue.fail", "op": ">", "threshold": 0, "severity": "high", "cooldown_sec": 300, "message": "Queue/Cron health failures detected" },
    { "id": "volume_fail", "metric": "volume.fail", "op": ">", "threshold": 0, "severity": "high", "cooldown_sec": 300, "message": "Volume/Inode failures detected" },
    { "id": "drift_fail", "metric": "drift.fail", "op": ">", "threshold": 0, "severity": "medium", "cooldown_sec": 600, "message": "Config drift detected" },
    { "id": "slo_error_rate", "metric": "slo.error_rate_1h_x100", "op": ">=", "threshold": 500, "severity": "medium", "cooldown_sec": 600, "message": "SLO error rate >= 5% (1h)" },
    { "id": "log_errors", "metric": "logs.errors_1h", "op": ">", "threshold": 100, "severity": "low", "cooldown_sec": 900, "message": "High error log volume in last 1h" }
  ]
}
JSON
  fi

  declare -A metrics=()
  metrics["runtime.fail"]="$(_metric_from_json 'monitor-runtime --json --since 60m --event-limit 120' '.summary.fail')"
  metrics["tls.fail"]="$(_metric_from_json 'monitor-tls --json' '.summary.fail')"
  metrics["db.fail"]="$(_metric_from_json 'monitor-db --json' '.summary.fail')"
  metrics["queue.fail"]="$(_metric_from_json 'monitor-queue --json --since 60m' '.summary.fail')"
  metrics["volume.fail"]="$(_metric_from_json 'monitor-volumes --json --top 20 --inode-top 8' '.summary.fail')"
  metrics["drift.fail"]="$(_metric_from_json 'monitor-drift --json' '.summary.fail')"
  metrics["logs.errors_1h"]="$(_metric_from_json 'monitor-log-heatmap --json --since 1h --bucket-min 15 --top 5 --line-limit 600' '.summary.errors')"
  metrics["slo.error_rate_1h_x100"]="$(
    monitor-slo --json 2>/dev/null |
      jq -r '.summary.windows[]? | select(.window=="1h") | (.error_rate_pct_x100 // 0)' 2>/dev/null |
      awk 'NR==1{print int($1)}' 2>/dev/null || printf '0'
  )"

  local q_enabled q_start q_end ch_desktop ch_webhook
  q_enabled="$(jq -r '.quiet_hours.enabled // false' "$rules_file" 2>/dev/null || printf 'false')"
  q_start="$(jq -r '.quiet_hours.start // "23:00"' "$rules_file" 2>/dev/null || printf '23:00')"
  q_end="$(jq -r '.quiet_hours.end // "07:00"' "$rules_file" 2>/dev/null || printf '07:00')"
  ch_desktop="$(jq -r '.channels.desktop // true' "$rules_file" 2>/dev/null || printf 'true')"
  ch_webhook="$(jq -r '.channels.webhook_url // ""' "$rules_file" 2>/dev/null || printf '')"

  local quiet_active=0
  if _quiet_hours_active "$q_enabled" "$q_start" "$q_end"; then
    quiet_active=1
  fi

  local now_epoch
  now_epoch="$(date -u +%s)"

  local -a incidents=()
  local sent_count=0 suppressed_count=0 firing_count=0 acked_count=0
  local rid metric op threshold sev cooldown msg value firing fp last_sent acked suppressed reason should_send sent_now
  while IFS=$'\t' read -r rid metric op threshold sev cooldown msg; do
    [[ -n "$rid" ]] || continue
    value="${metrics[$metric]:-0}"
    value="$(_num_or_default "$value" 0)"
    threshold="$(_num_or_default "$threshold" 0)"
    cooldown="$(_num_or_default "$cooldown" 300)"

    if _cmp "$op" "$value" "$threshold"; then
      firing=1
      ((++firing_count))
    else
      firing=0
    fi

    fp="$(printf '%s|%s|%s|%s|%s\n' "$rid" "$metric" "$op" "$threshold" "$value" | sha1sum | awk '{print $1}')"
    last_sent="$(_tsv_get "$sent_file" "$rid" "$fp")"
    last_sent="$(_num_or_default "$last_sent" 0)"
    acked="$(_tsv_get "$ack_file" "$rid" "$fp")"
    acked="$(_num_or_default "$acked" 0)"
    suppressed=0
    reason=""
    should_send=0
    sent_now=0

    if ((firing)); then
      if ((acked > 0)); then
        suppressed=1
        reason="acked"
        ((++acked_count))
      elif ((quiet_active == 1)) && [[ "${sev,,}" != "critical" ]]; then
        suppressed=1
        reason="quiet_hours"
      elif ((last_sent > 0)) && ((now_epoch - last_sent < cooldown)); then
        suppressed=1
        reason="cooldown"
      fi
      if ((suppressed)); then
        ((++suppressed_count))
      else
        should_send=1
      fi
    fi

    if ((run_mode == 1 && should_send == 1)); then
      local title body payload
      title="LDS Alert: ${rid}"
      body="${msg} (metric=${metric}, value=${value}, threshold ${op} ${threshold})"
      if [[ "${ch_desktop,,}" == "true" ]] && _has notify; then
        notify "$title" "$body" >/dev/null 2>&1 || true
      fi
      if [[ -n "$ch_webhook" ]] && _has curl; then
        payload="$(printf '{"id":"%s","severity":"%s","metric":"%s","value":%s,"threshold":%s,"op":"%s","message":"%s","generated_at":"%s"}' \
          "$(_json_escape "$rid")" "$(_json_escape "$sev")" "$(_json_escape "$metric")" "$value" "$threshold" "$(_json_escape "$op")" "$(_json_escape "$msg")" "$(_json_escape "$(date -u +%Y-%m-%dT%H:%M:%SZ)")")"
        curl -fsS -m 8 -H 'Content-Type: application/json' -X POST -d "$payload" "$ch_webhook" >/dev/null 2>&1 || true
      fi
      _tsv_upsert "$sent_file" "$rid" "$fp" "$now_epoch"
      sent_now=1
      ((++sent_count))
    fi

    incidents+=("$rid|$metric|$op|$threshold|$sev|$cooldown|$msg|$value|$firing|$fp|$last_sent|$acked|$suppressed|$reason|$sent_now")
  done < <(
    jq -r '.rules[]? | [
      (.id // ""),
      (.metric // ""),
      (.op // ">"),
      ((.threshold // 0)|tostring),
      (.severity // "medium"),
      ((.cooldown_sec // 300)|tostring),
      (.message // "")
    ] | @tsv' "$rules_file" 2>/dev/null
  )

  local acked_rule_out="" acked_fp_out="" acked_ok=0
  if [[ -n "$ack_rule" ]]; then
    if [[ -z "$ack_fp" ]]; then
      local irow
      for irow in "${incidents[@]}"; do
        IFS='|' read -r rid metric op threshold sev cooldown msg value firing fp last_sent acked suppressed reason sent_now <<<"$irow"
        if [[ "$rid" == "$ack_rule" && "$firing" == "1" ]]; then
          ack_fp="$fp"
          break
        fi
      done
    fi
    if [[ -n "$ack_fp" ]]; then
      _tsv_upsert "$ack_file" "$ack_rule" "$ack_fp" "$now_epoch"
      acked_rule_out="$ack_rule"
      acked_fp_out="$ack_fp"
      acked_ok=1
    fi
  fi

  if ((json == 0 && run_mode == 0)); then
    printf 'Alerts | firing=%d sent=%d suppressed=%d quiet_hours=%d\n' "$firing_count" "$sent_count" "$suppressed_count" "$quiet_active"
    return 0
  fi

  printf '{'
  printf '"ok":true,'
  printf '"generated_at":"%s",' "$(_json_escape "$(date -u +%Y-%m-%dT%H:%M:%SZ)")"
  printf '"mode":{"json":%s,"run":%s},' "$([[ "$json" == "1" ]] && printf true || printf false)" "$([[ "$run_mode" == "1" ]] && printf true || printf false)"
  printf '"quiet_hours":{"enabled":%s,"start":"%s","end":"%s","active":%s},' \
    "$([[ "${q_enabled,,}" == "true" ]] && printf true || printf false)" \
    "$(_json_escape "$q_start")" \
    "$(_json_escape "$q_end")" \
    "$([[ "$quiet_active" == "1" ]] && printf true || printf false)"
  printf '"channels":{"desktop":%s,"webhook_configured":%s},' \
    "$([[ "${ch_desktop,,}" == "true" ]] && printf true || printf false)" \
    "$([[ -n "$ch_webhook" ]] && printf true || printf false)"

  printf '"metrics":{'
  local mf=1 mk
  for mk in "${!metrics[@]}"; do
    ((mf)) || printf ','
    mf=0
    printf '"%s":%s' "$(_json_escape "$mk")" "$(_num_or_default "${metrics[$mk]}" 0)"
  done
  printf '},'

  printf '"summary":{"rules":%d,"firing":%d,"sent":%d,"suppressed":%d,"acked":%d},' \
    "${#incidents[@]}" "$firing_count" "$sent_count" "$suppressed_count" "$acked_count"

  printf '"ack":{'
  printf '"requested_rule":"%s",' "$(_json_escape "$ack_rule")"
  printf '"requested_fingerprint":"%s",' "$(_json_escape "$ack_fp")"
  printf '"applied":%s,' "$([[ "$acked_ok" == "1" ]] && printf true || printf false)"
  printf '"rule":"%s",' "$(_json_escape "$acked_rule_out")"
  printf '"fingerprint":"%s"' "$(_json_escape "$acked_fp_out")"
  printf '},'

  printf '"incidents":['
  local f=1 row
  for row in "${incidents[@]}"; do
    IFS='|' read -r rid metric op threshold sev cooldown msg value firing fp last_sent acked suppressed reason sent_now <<<"$row"
    ((f)) || printf ','
    f=0
    printf '{'
    printf '"id":"%s",' "$(_json_escape "$rid")"
    printf '"metric":"%s",' "$(_json_escape "$metric")"
    printf '"op":"%s",' "$(_json_escape "$op")"
    printf '"threshold":%s,' "$(_num_or_default "$threshold" 0)"
    printf '"severity":"%s",' "$(_json_escape "$sev")"
    printf '"cooldown_sec":%s,' "$(_num_or_default "$cooldown" 300)"
    printf '"message":"%s",' "$(_json_escape "$msg")"
    printf '"value":%s,' "$(_num_or_default "$value" 0)"
    printf '"firing":%s,' "$([[ "$firing" == "1" ]] && printf true || printf false)"
    printf '"fingerprint":"%s",' "$(_json_escape "$fp")"
    printf '"last_sent_epoch":%s,' "$(_num_or_default "$last_sent" 0)"
    printf '"acked_epoch":%s,' "$(_num_or_default "$acked" 0)"
    printf '"suppressed":%s,' "$([[ "$suppressed" == "1" ]] && printf true || printf false)"
    printf '"suppressed_reason":"%s",' "$(_json_escape "$reason")"
    printf '"sent_now":%s' "$([[ "$sent_now" == "1" ]] && printf true || printf false)"
    printf '}'
  done
  printf ']'

  printf '}\n'
}

main "$@"
