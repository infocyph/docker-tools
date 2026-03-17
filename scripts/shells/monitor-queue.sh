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

_num_or_default() {
  local v="${1:-}" d="${2:-0}"
  if [[ "$v" =~ ^-?[0-9]+$ ]]; then
    printf '%s' "$v"
  else
    printf '%s' "$d"
  fi
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

_docker_exec_pref_shell() {
  local container="${1:-}" script="${2:-}"
  [[ -n "$container" ]] || return 0
  docker exec "$container" bash -c "$script" 2>/dev/null || docker exec "$container" sh -c "$script" 2>/dev/null || true
}

_find_redis_container() {
  local raw name service image state
  raw="$(docker ps -a --format '{{.Names}}|{{.Label "com.docker.compose.service"}}|{{.Image}}|{{.State}}' 2>/dev/null || true)"
  while IFS='|' read -r name service image state; do
    [[ -n "$name" ]] || continue
    if [[ "${name,,} ${service,,} ${image,,}" == *redis* ]]; then
      printf '%s|%s\n' "$name" "$state"
      return 0
    fi
  done <<<"$raw"
}

_find_runner_container() {
  local raw name service image state hay
  raw="$(docker ps -a --format '{{.Names}}|{{.Label "com.docker.compose.service"}}|{{.Image}}|{{.State}}' 2>/dev/null || true)"
  while IFS='|' read -r name service image state; do
    [[ -n "$name" ]] || continue
    hay="${name,,} ${service,,} ${image,,}"
    if [[ "${service,,}" == "runner" || "${name,,}" == "runner" || "$hay" == *"infocyph/runner"* ]]; then
      printf '%s|%s\n' "$name" "$state"
      return 0
    fi
  done <<<"$raw"
}

_scan_laravel_failed_jobs() {
  local container="${1:-}"
  [[ -n "$container" ]] || {
    printf '%s' '-1'
    return 0
  }
  local out n
  out="$(_docker_exec_pref_shell "$container" '[ -f /app/artisan ] && php /app/artisan queue:failed --json 2>/dev/null || true')"
  if [[ -n "$out" && "$out" == \[*\] ]]; then
    n="$(printf '%s' "$out" | grep -o '{' | wc -l | awk '{print $1}')"
    printf '%s' "$(_num_or_default "$n" -1)"
    return 0
  fi
  out="$(_docker_exec_pref_shell "$container" '[ -f /app/artisan ] && php /app/artisan queue:failed 2>/dev/null || true')"
  if [[ -n "$out" ]]; then
    n="$(printf '%s\n' "$out" | sed -n '/^+[-+]\+$/,$p' | grep -E '^[|]' | wc -l | awk '{print $1}')"
    if [[ "$n" =~ ^[0-9]+$ && "$n" -gt 0 ]]; then
      printf '%s' "$n"
      return 0
    fi
  fi
  printf '%s' '-1'
}

_runner_defaults() {
  RUNNER_LEVEL="warn"
  RUNNER_NOTE="runner_not_detected"
  RUNNER_CONTAINER="-"
  RUNNER_STATE="-"
  RUNNER_SUPERVISOR="unknown"
  RUNNER_CRON="missing"
  RUNNER_LOGROTATE="missing"
  RUNNER_PROGRAMS_TOTAL=0
  RUNNER_PROGRAMS_NOT_RUNNING=0
}

_probe_runner_supervisor() {
  local container="${1:-}" state="${2:-}"
  _runner_defaults

  if [[ -z "$container" ]]; then
    return 0
  fi

  RUNNER_CONTAINER="$container"
  RUNNER_STATE="${state:--}"
  RUNNER_NOTE="ok"

  if [[ "$state" != "running" ]]; then
    RUNNER_LEVEL="fail"
    RUNNER_NOTE="runner_not_running"
    return 0
  fi

  local out line program pstate
  out="$(_docker_exec_pref_shell "$container" 'supervisorctl -c /etc/supervisor/supervisord.conf status 2>/dev/null || true')"
  if [[ -z "$out" ]]; then
    RUNNER_LEVEL="fail"
    RUNNER_NOTE="supervisorctl_failed"
    return 0
  fi

  RUNNER_SUPERVISOR="up"
  RUNNER_LEVEL="pass"
  RUNNER_NOTE="ok"

  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    program="$(printf '%s\n' "$line" | awk '{print $1}')"
    pstate="$(printf '%s\n' "$line" | awk '{print $2}')"
    [[ -n "$program" && -n "$pstate" ]] || continue
    ((++RUNNER_PROGRAMS_TOTAL))

    if [[ "$program" == "cron" ]]; then
      RUNNER_CRON="$pstate"
    elif [[ "$program" == "logrotate" ]]; then
      RUNNER_LOGROTATE="$pstate"
    fi

    if [[ "$pstate" != "RUNNING" ]]; then
      ((++RUNNER_PROGRAMS_NOT_RUNNING))
    fi
  done <<<"$out"

  if [[ "$RUNNER_CRON" != "RUNNING" ]]; then
    RUNNER_LEVEL="fail"
    RUNNER_NOTE="runner_cron_not_running"
    return 0
  fi
  if [[ "$RUNNER_LOGROTATE" != "RUNNING" ]]; then
    RUNNER_LEVEL="fail"
    RUNNER_NOTE="runner_logrotate_not_running"
    return 0
  fi
  if ((RUNNER_PROGRAMS_NOT_RUNNING > 0)); then
    RUNNER_LEVEL="warn"
    RUNNER_NOTE="runner_programs_not_running"
  fi
}

usage() {
  cat <<'EOF'
Usage:
  monitor-queue [--json] [--since <dur>] [--pending-threshold <n>] [--heartbeat-stale-sec <n>]

Examples:
  monitor-queue --json
  monitor-queue --json --since 2h --pending-threshold 400 --heartbeat-stale-sec 900
EOF
}

main() {
  local json=0 since="60m" pending_threshold=500 stale_sec=900
  while [[ "${1:-}" ]]; do
    case "$1" in
      --json) json=1; shift ;;
      --since) since="${2:-60m}"; shift 2 ;;
      --pending-threshold) pending_threshold="${2:-500}"; shift 2 ;;
      --heartbeat-stale-sec) stale_sec="${2:-900}"; shift 2 ;;
      -h|--help) usage; return 0 ;;
      *) echo "Unknown arg: $1" >&2; usage; return 1 ;;
    esac
  done

  [[ "$pending_threshold" =~ ^[0-9]+$ ]] || pending_threshold=500
  [[ "$stale_sec" =~ ^[0-9]+$ ]] || stale_sec=900
  ((pending_threshold < 1)) && pending_threshold=1
  ((stale_sec < 60)) && stale_sec=60

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

  local project now_epoch
  project="$(_infer_project)"
  now_epoch="$(date -u +%s)"

  local -a names=()
  if [[ "$project" != "unknown" && -n "$project" ]]; then
    mapfile -t names < <(docker ps -a --filter "label=com.docker.compose.project=${project}" --format '{{.Names}}' 2>/dev/null | sed '/^[[:space:]]*$/d')
  fi
  if ((${#names[@]} == 0)); then
    mapfile -t names < <(docker ps -a --format '{{.Names}}' 2>/dev/null | sed '/^[[:space:]]*$/d')
  fi

  local raw=""
  if ((${#names[@]})); then
    raw="$(docker inspect -f '{{.Name}}|{{index .Config.Labels "com.docker.compose.service"}}|{{.Config.Image}}|{{.State.Status}}' "${names[@]}" 2>/dev/null | sed 's#^/##')"
  fi

  local queue_pending=0 queue_delayed=0 queue_reserved=0 oldest_pending_age=-1
  local redis_container="" redis_state="" redis_note="not_detected"
  local redis_entry
  redis_entry="$(_find_redis_container || true)"
  if [[ -n "$redis_entry" ]]; then
    IFS='|' read -r redis_container redis_state <<<"$redis_entry"
    redis_note="ok"
    if [[ "$redis_state" == "running" ]]; then
      local keys key llen zc zline zscore zepoch zage max_age
      mapfile -t keys < <(_docker_exec_pref_shell "$redis_container" "redis-cli --scan --pattern 'queues:*' 2>/dev/null || true" | sed '/^[[:space:]]*$/d')
      max_age=-1
      for key in "${keys[@]}"; do
        if [[ "$key" == *":delayed" ]]; then
          zc="$(_docker_exec_pref_shell "$redis_container" "redis-cli ZCARD \"$key\" 2>/dev/null || true")"
          zc="$(_num_or_default "$zc" 0)"
          queue_delayed=$((queue_delayed + zc))
          zline="$(_docker_exec_pref_shell "$redis_container" "redis-cli ZRANGE \"$key\" 0 0 WITHSCORES 2>/dev/null || true" | tail -n1)"
          zscore="$(_num_or_default "$zline" 0)"
          if ((zscore > 0)); then
            zepoch="$zscore"
            if ((${#zepoch} > 11)); then
              zepoch=$((zepoch / 1000))
            fi
            zage=$((now_epoch - zepoch))
            if ((zage > max_age)); then
              max_age="$zage"
            fi
          fi
        elif [[ "$key" == *":reserved" ]]; then
          zc="$(_docker_exec_pref_shell "$redis_container" "redis-cli ZCARD \"$key\" 2>/dev/null || true")"
          zc="$(_num_or_default "$zc" 0)"
          queue_reserved=$((queue_reserved + zc))
        elif [[ "$key" == *":notify" ]]; then
          :
        else
          llen="$(_docker_exec_pref_shell "$redis_container" "redis-cli LLEN \"$key\" 2>/dev/null || true")"
          llen="$(_num_or_default "$llen" 0)"
          queue_pending=$((queue_pending + llen))
        fi
      done
      oldest_pending_age="$max_age"
    else
      redis_note="container_not_running"
    fi
  fi

  local runner_container="" runner_state="" runner_entry
  runner_entry="$(_find_runner_container || true)"
  if [[ -n "$runner_entry" ]]; then
    IFS='|' read -r runner_container runner_state <<<"$runner_entry"
  fi
  _probe_runner_supervisor "$runner_container" "$runner_state"

  local total_workers=0 pass=0 warn=0 fail=0 stale_workers=0 failed_jobs_total=0
  local -a items=()
  local row name service image state
  while IFS='|' read -r name service image state; do
    [[ -n "$name" ]] || continue
    local hay="${name,,} ${service,,} ${image,,}"
    # Keep worker matching explicit to avoid pulling generic runtime containers (e.g. php_8.5).
    if [[ "$hay" != *queue* && "$hay" != *worker* && "$hay" != *cron* && "$hay" != *scheduler* && "$hay" != *schedule* && "$hay" != *horizon* && "$hay" != *node* ]]; then
      continue
    fi
    ((++total_workers))

    local level="pass" note="ok" processed=0 failed=0 failed_rate=0 hb_epoch=0 hb_age=-1 failed_jobs=-1
    if [[ "$state" != "running" ]]; then
      level="fail"
      note="container_not_running"
    else
      local logs line ts msg
      logs="$(docker logs --since "$since" --timestamps "$name" 2>/dev/null | tail -n 1500 || true)"
      while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        ts="${line%% *}"
        msg="${line#* }"
        if [[ "${msg,,}" =~ (processed|completed|done[[:space:]]+job|job[[:space:]]+done|success) ]]; then
          ((++processed))
        fi
        if [[ "${msg,,}" =~ (failed|exception|fatal|unhandled|error) ]]; then
          ((++failed))
        fi
        if [[ "${msg,,}" =~ (schedule|scheduler|cron|heartbeat|tick) ]]; then
          local e
          e="$(_to_epoch "$ts")"
          if ((e > hb_epoch)); then
            hb_epoch="$e"
          fi
        fi
      done <<<"$logs"

      if ((processed + failed > 0)); then
        failed_rate=$((failed * 100 / (processed + failed)))
      fi
      failed_jobs="$(_scan_laravel_failed_jobs "$name")"
      if [[ "$failed_jobs" =~ ^[0-9]+$ && "$failed_jobs" -gt 0 ]]; then
        failed_jobs_total=$((failed_jobs_total + failed_jobs))
      fi

      if ((hb_epoch > 0)); then
        hb_age=$((now_epoch - hb_epoch))
        if ((hb_age > stale_sec)); then
          level="warn"
          note="heartbeat_stale"
          ((++stale_workers))
        fi
      fi
      if ((failed_rate >= 20)); then
        level="fail"
        note="high_failed_rate"
      elif ((failed_rate >= 5 && level != "fail")); then
        level="warn"
        note="failed_rate_elevated"
      fi
      if ((failed_jobs >= 20)); then
        level="fail"
        note="failed_jobs_high"
      elif ((failed_jobs > 0 && level == "pass")); then
        level="warn"
        note="failed_jobs_present"
      fi
    fi

    case "$level" in
      pass) ((++pass)) ;;
      warn) ((++warn)) ;;
      *) ((++fail)); level="fail" ;;
    esac
    items+=("$name|$service|$state|$processed|$failed|$failed_rate|$hb_epoch|$hb_age|$failed_jobs|$level|$note")
  done <<<"$raw"

  local queue_level="pass" queue_note="ok"
  if [[ -n "$redis_container" && "$redis_state" != "running" ]]; then
    queue_level="fail"
    queue_note="redis_not_running"
  elif ((queue_pending > pending_threshold * 2)); then
    queue_level="fail"
    queue_note="pending_backlog_critical"
  elif ((queue_pending > pending_threshold)); then
    queue_level="warn"
    queue_note="pending_backlog_high"
  fi
  if ((oldest_pending_age > stale_sec * 2)); then
    queue_level="fail"
    queue_note="oldest_pending_too_old"
  elif ((oldest_pending_age > stale_sec && queue_level != "fail")); then
    queue_level="warn"
    queue_note="oldest_pending_old"
  fi

  local overall_fail=$fail overall_warn=$warn runner_issues=0
  if [[ "$queue_level" == "fail" ]]; then
    ((++overall_fail))
  elif [[ "$queue_level" == "warn" ]]; then
    ((++overall_warn))
  fi
  if [[ "$RUNNER_LEVEL" == "fail" ]]; then
    ((++overall_fail))
    ((++runner_issues))
  elif [[ "$RUNNER_LEVEL" == "warn" ]]; then
    ((++overall_warn))
    ((++runner_issues))
  fi

  if ((json == 0)); then
    printf 'Queue/Cron Health | project=%s workers=%d pass=%d warn=%d fail=%d pending=%d oldest_age=%ds runner=%s/%s\n' \
      "$project" "$total_workers" "$pass" "$overall_warn" "$overall_fail" "$queue_pending" "$oldest_pending_age" "$RUNNER_CONTAINER" "$RUNNER_NOTE"
    return 0
  fi

  printf '{'
  printf '"ok":true,'
  printf '"generated_at":"%s",' "$(_json_escape "$(date -u +%Y-%m-%dT%H:%M:%SZ)")"
  printf '"project":"%s",' "$(_json_escape "$project")"
  printf '"filters":{"since":"%s","pending_threshold":%d,"heartbeat_stale_sec":%d},' \
    "$(_json_escape "$since")" "$pending_threshold" "$stale_sec"
  printf '"summary":{"workers":%d,"pass":%d,"warn":%d,"fail":%d,"stale_workers":%d,"failed_jobs_total":%d,"runner_issues":%d},' \
    "$total_workers" "$pass" "$overall_warn" "$overall_fail" "$stale_workers" "$failed_jobs_total" "$runner_issues"
  printf '"queue_backend":{'
  printf '"type":"redis",'
  printf '"container":"%s",' "$(_json_escape "${redis_container:--}")"
  printf '"state":"%s",' "$(_json_escape "${redis_state:--}")"
  printf '"pending":%d,' "$queue_pending"
  printf '"delayed":%d,' "$queue_delayed"
  printf '"reserved":%d,' "$queue_reserved"
  printf '"oldest_pending_age_s":%d,' "$oldest_pending_age"
  printf '"level":"%s",' "$(_json_escape "$queue_level")"
  printf '"note":"%s",' "$(_json_escape "$queue_note")"
  printf '"runner":{'
  printf '"container":"%s",' "$(_json_escape "$RUNNER_CONTAINER")"
  printf '"state":"%s",' "$(_json_escape "$RUNNER_STATE")"
  printf '"supervisor":"%s",' "$(_json_escape "$RUNNER_SUPERVISOR")"
  printf '"cron":"%s",' "$(_json_escape "$RUNNER_CRON")"
  printf '"logrotate":"%s",' "$(_json_escape "$RUNNER_LOGROTATE")"
  printf '"programs_total":%d,' "$RUNNER_PROGRAMS_TOTAL"
  printf '"programs_not_running":%d,' "$RUNNER_PROGRAMS_NOT_RUNNING"
  printf '"level":"%s",' "$(_json_escape "$RUNNER_LEVEL")"
  printf '"note":"%s"' "$(_json_escape "$RUNNER_NOTE")"
  printf '}'
  printf '},'
  printf '"items":['
  local f=1 it
  for it in "${items[@]}"; do
    IFS='|' read -r name service state processed failed failed_rate hb_epoch hb_age failed_jobs level note <<<"$it"
    ((f)) || printf ','
    f=0
    printf '{'
    printf '"container":"%s",' "$(_json_escape "$name")"
    printf '"service":"%s",' "$(_json_escape "${service:--}")"
    printf '"state":"%s",' "$(_json_escape "${state:--}")"
    printf '"processed":%s,' "$(_num_or_default "$processed" 0)"
    printf '"failed":%s,' "$(_num_or_default "$failed" 0)"
    printf '"failed_rate_pct":%s,' "$(_num_or_default "$failed_rate" 0)"
    printf '"heartbeat_epoch":%s,' "$(_num_or_default "$hb_epoch" 0)"
    printf '"heartbeat_age_s":%s,' "$(_num_or_default "$hb_age" -1)"
    printf '"failed_jobs":%s,' "$(_num_or_default "$failed_jobs" -1)"
    printf '"level":"%s",' "$(_json_escape "$level")"
    printf '"note":"%s"' "$(_json_escape "$note")"
    printf '}'
  done
  printf ']'
  printf '}\n'
}

main "$@"
