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

usage() {
  cat <<'EOF'
Usage:
  monitor-runtime [--json] [--project <name>] [--since <dur>] [--restart-threshold <n>] [--event-limit <n>]

Examples:
  monitor-runtime --json
  monitor-runtime --json --since 6h --restart-threshold 4
EOF
}

main() {
  local json=0 project="" since="60m" restart_threshold=3 event_limit=80
  while [[ "${1:-}" ]]; do
    case "$1" in
      --json) json=1; shift ;;
      --project) project="${2:-}"; shift 2 ;;
      --since) since="${2:-60m}"; shift 2 ;;
      --restart-threshold) restart_threshold="${2:-3}"; shift 2 ;;
      --event-limit) event_limit="${2:-80}"; shift 2 ;;
      -h|--help) usage; return 0 ;;
      *) echo "Unknown arg: $1" >&2; usage; return 1 ;;
    esac
  done

  [[ "$restart_threshold" =~ ^[0-9]+$ ]] || restart_threshold=3
  ((restart_threshold < 1)) && restart_threshold=1
  ((restart_threshold > 50)) && restart_threshold=50
  [[ "$event_limit" =~ ^[0-9]+$ ]] || event_limit=80
  ((event_limit < 0)) && event_limit=0
  ((event_limit > 500)) && event_limit=500

  if ! _has docker; then
    printf '{"ok":false,"error":"docker_missing","message":"docker command is required.","generated_at":"%s","project":"%s"}\n' \
      "$(_json_escape "$(date -u +%Y-%m-%dT%H:%M:%SZ)")" "$(_json_escape "${project:-unknown}")"
    return 1
  fi
  if ! docker info >/dev/null 2>&1; then
    printf '{"ok":false,"error":"docker_unreachable","message":"Docker daemon is not reachable.","generated_at":"%s","project":"%s"}\n' \
      "$(_json_escape "$(date -u +%Y-%m-%dT%H:%M:%SZ)")" "$(_json_escape "${project:-unknown}")"
    return 1
  fi

  if [[ -z "$project" ]]; then
    project="$(_infer_project)"
  fi

  local -a names=()
  mapfile -t names < <(docker ps -a --filter "label=com.docker.compose.project=${project}" --format '{{.Names}}' 2>/dev/null | sed '/^[[:space:]]*$/d')

  local total=0 running=0 exited=0 restarting=0 paused=0 dead=0 other=0
  local healthy=0 unhealthy=0 starting=0 no_health=0
  local pass=0 warn=0 fail=0 flapping=0 oom_count=0 with_issues=0
  local -a items=()

  if ((${#names[@]})); then
    local raw row name svc state health restart oom exitcode started finished
    raw="$(docker inspect -f '{{.Name}}|{{index .Config.Labels "com.docker.compose.service"}}|{{.State.Status}}|{{if .State.Health}}{{.State.Health.Status}}{{else}}-{{end}}|{{.RestartCount}}|{{.State.OOMKilled}}|{{.State.ExitCode}}|{{.State.StartedAt}}|{{.State.FinishedAt}}' "${names[@]}" 2>/dev/null | sed 's#^/##')"
    while IFS='|' read -r name svc state health restart oom exitcode started finished; do
      [[ -n "$name" ]] || continue
      [[ "$restart" =~ ^[0-9]+$ ]] || restart=0
      [[ "$exitcode" =~ ^-?[0-9]+$ ]] || exitcode=0
      state="${state:-unknown}"
      health="${health:--}"
      [[ -n "$svc" ]] || svc="-"
      [[ -n "$started" ]] || started="-"
      [[ -n "$finished" ]] || finished="-"

      ((++total))
      case "$state" in
        running) ((++running)) ;;
        exited) ((++exited)) ;;
        restarting) ((++restarting)) ;;
        paused) ((++paused)) ;;
        dead) ((++dead)) ;;
        *) ((++other)) ;;
      esac

      case "$health" in
        healthy) ((++healthy)) ;;
        unhealthy) ((++unhealthy)) ;;
        starting) ((++starting)) ;;
        *) ((++no_health)) ;;
      esac

      local issue_level="pass"
      local -a issue_list=()

      if [[ "$state" != "running" ]]; then
        issue_level="fail"
        issue_list+=("state=${state}")
      fi
      if [[ "$health" == "unhealthy" ]]; then
        issue_level="fail"
        issue_list+=("health=unhealthy")
      elif [[ "$health" == "starting" && "$issue_level" != "fail" ]]; then
        issue_level="warn"
        issue_list+=("health=starting")
      fi
      if ((restart >= restart_threshold)); then
        ((++flapping))
        if [[ "$issue_level" == "pass" ]]; then
          issue_level="warn"
        fi
        issue_list+=("restart_count=${restart}")
      fi
      if [[ "${oom,,}" == "true" ]]; then
        ((++oom_count))
        issue_level="fail"
        issue_list+=("oom_killed=true")
      fi
      if [[ "$state" != "running" && "$exitcode" != "0" ]]; then
        issue_level="fail"
        issue_list+=("exit_code=${exitcode}")
      fi

      local issue_text="none"
      if ((${#issue_list[@]})); then
        issue_text="$(IFS='; '; printf '%s' "${issue_list[*]}")"
        ((++with_issues))
      fi

      case "$issue_level" in
        pass) ((++pass)) ;;
        warn) ((++warn)) ;;
        fail) ((++fail)) ;;
      esac

      items+=("$name|$svc|$state|$health|$restart|${oom:-false}|$exitcode|$started|$finished|$issue_level|$issue_text")
    done <<<"$raw"
  fi

  local until_ts
  until_ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  local -a events=()
  if ((event_limit > 0)); then
    mapfile -t events < <(
      docker events \
        --since "$since" \
        --until "$until_ts" \
        --filter type=container \
        --filter "label=com.docker.compose.project=${project}" \
        --filter event=oom \
        --filter event=die \
        --filter event=restart \
        --filter event=start \
        --format '{{.TimeNano}}|{{.Time}}|{{.Action}}|{{.Actor.Attributes.name}}|{{.Actor.Attributes.com.docker.compose.service}}|{{.Actor.Attributes.exitCode}}' 2>/dev/null |
        sed '/^[[:space:]]*$/d' |
        tail -n "$event_limit"
    )
  fi

  local ev_oom=0 ev_die=0 ev_restart=0 ev_start=0
  local trend_bucket_sec=300
  declare -A trend_total=() trend_oom=() trend_die=() trend_restart=() trend_start=()
  local e ts_nano ts_text action ename esvc ecode ts_epoch bucket
  for e in "${events[@]}"; do
    IFS='|' read -r ts_nano ts_text action ename esvc ecode <<<"$e"
    case "$action" in
      oom) ((++ev_oom)) ;;
      die) ((++ev_die)) ;;
      restart) ((++ev_restart)) ;;
      start) ((++ev_start)) ;;
    esac

    ts_epoch="$(_to_epoch "$ts_nano")"
    if [[ "$ts_epoch" =~ ^[0-9]+$ ]] && ((ts_epoch > 0)); then
      bucket=$((ts_epoch - (ts_epoch % trend_bucket_sec)))
      trend_total["$bucket"]=$(( ${trend_total["$bucket"]:-0} + 1 ))
      case "$action" in
        oom) trend_oom["$bucket"]=$(( ${trend_oom["$bucket"]:-0} + 1 )) ;;
        die) trend_die["$bucket"]=$(( ${trend_die["$bucket"]:-0} + 1 )) ;;
        restart) trend_restart["$bucket"]=$(( ${trend_restart["$bucket"]:-0} + 1 )) ;;
        start) trend_start["$bucket"]=$(( ${trend_start["$bucket"]:-0} + 1 )) ;;
      esac
    fi
  done

  if ((json == 0)); then
    printf 'Runtime Watch | project=%s containers=%d pass=%d warn=%d fail=%d events=%d\n' \
      "$project" "$total" "$pass" "$warn" "$fail" "${#events[@]}"
    return 0
  fi

  printf '{'
  printf '"ok":true,'
  printf '"generated_at":"%s",' "$(_json_escape "$(date -u +%Y-%m-%dT%H:%M:%SZ)")"
  printf '"project":"%s",' "$(_json_escape "$project")"
  printf '"filters":{"since":"%s","restart_threshold":%s,"event_limit":%s},' \
    "$(_json_escape "$since")" "$restart_threshold" "$event_limit"
  printf '"summary":{'
  printf '"containers":%d,"running":%d,"exited":%d,"restarting":%d,"paused":%d,"dead":%d,"other":%d,' \
    "$total" "$running" "$exited" "$restarting" "$paused" "$dead" "$other"
  printf '"healthy":%d,"unhealthy":%d,"starting":%d,"no_health":%d,' \
    "$healthy" "$unhealthy" "$starting" "$no_health"
  printf '"pass":%d,"warn":%d,"fail":%d,"with_issues":%d,"flapping":%d,"oom_killed":%d,' \
    "$pass" "$warn" "$fail" "$with_issues" "$flapping" "$oom_count"
  printf '"events_total":%d,"events_oom":%d,"events_die":%d,"events_restart":%d,"events_start":%d,"trend_bucket_sec":%d' \
    "${#events[@]}" "$ev_oom" "$ev_die" "$ev_restart" "$ev_start" "$trend_bucket_sec"
  printf '},'

  printf '"items":['
  local f=1 row issues level
  for row in "${items[@]}"; do
    IFS='|' read -r name svc state health restart oom exitcode started finished level issues <<<"$row"
    ((f)) || printf ','
    f=0
    printf '{'
    printf '"name":"%s",' "$(_json_escape "$name")"
    printf '"service":"%s",' "$(_json_escape "$svc")"
    printf '"state":"%s",' "$(_json_escape "$state")"
    printf '"health":"%s",' "$(_json_escape "$health")"
    printf '"restart_count":%s,' "$restart"
    printf '"oom_killed":%s,' "$([[ "${oom,,}" == "true" ]] && printf 'true' || printf 'false')"
    printf '"exit_code":%s,' "$exitcode"
    printf '"started_at":"%s",' "$(_json_escape "$started")"
    printf '"finished_at":"%s",' "$(_json_escape "$finished")"
    printf '"level":"%s",' "$(_json_escape "$level")"
    printf '"issues":"%s"' "$(_json_escape "$issues")"
    printf '}'
  done
  printf '],'

  printf '"trend":['
  f=1
  local -a trend_keys=()
  if ((${#trend_total[@]})); then
    mapfile -t trend_keys < <(printf '%s\n' "${!trend_total[@]}" | sort -n)
  fi
  local tkey tiso
  for tkey in "${trend_keys[@]}"; do
    ((f)) || printf ','
    f=0
    tiso="$(date -u -d "@${tkey}" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || printf '%s' "$tkey")"
    printf '{'
    printf '"bucket_epoch":%s,' "$tkey"
    printf '"bucket":"%s",' "$(_json_escape "$tiso")"
    printf '"total":%s,' "${trend_total["$tkey"]:-0}"
    printf '"oom":%s,' "${trend_oom["$tkey"]:-0}"
    printf '"die":%s,' "${trend_die["$tkey"]:-0}"
    printf '"restart":%s,' "${trend_restart["$tkey"]:-0}"
    printf '"start":%s' "${trend_start["$tkey"]:-0}"
    printf '}'
  done
  printf '],'

  printf '"events":['
  f=1
  for row in "${events[@]}"; do
    IFS='|' read -r ts_nano ts_text action ename esvc ecode <<<"$row"
    ts_epoch="$(_to_epoch "$ts_nano")"
    ((f)) || printf ','
    f=0
    printf '{'
    printf '"time":"%s",' "$(_json_escape "${ts_text:--}")"
    printf '"time_epoch":%s,' "${ts_epoch:-0}"
    printf '"action":"%s",' "$(_json_escape "${action:--}")"
    printf '"name":"%s",' "$(_json_escape "${ename:--}")"
    printf '"service":"%s",' "$(_json_escape "${esvc:--}")"
    printf '"exit_code":"%s"' "$(_json_escape "${ecode:--}")"
    printf '}'
  done
  printf ']'
  printf '}\n'
}

main "$@"
