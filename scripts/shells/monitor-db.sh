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

_engine_from() {
  local x="${1,,}"
  if [[ "$x" == *redis* ]]; then
    printf 'redis'
    return 0
  fi
  if [[ "$x" == *mysql* || "$x" == *mariadb* ]]; then
    printf 'mysql'
    return 0
  fi
  if [[ "$x" == *postgres* ]]; then
    printf 'postgres'
    return 0
  fi
  printf ''
}

_container_env_value() {
  local name="${1:-}" key="${2:-}" line
  [[ -n "$name" && -n "$key" ]] || return 0
  while IFS= read -r line; do
    [[ "$line" == "$key="* ]] || continue
    printf '%s' "${line#*=}"
    return 0
  done < <(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$name" 2>/dev/null || true)
}

_num_or_default() {
  local v="${1:-}" d="${2:-0}"
  if [[ "$v" =~ ^-?[0-9]+$ ]]; then
    printf '%s' "$v"
  else
    printf '%s' "$d"
  fi
}

_docker_exec_pref_shell() {
  local name="${1:-}" script="${2:-}"
  [[ -n "$name" ]] || return 0
  docker exec "$name" bash -c "$script" 2>/dev/null || docker exec "$name" sh -c "$script" 2>/dev/null || true
}

_probe_defaults() {
  P_LEVEL="warn"
  P_NOTE="not_probed"
  P_CONNECTIONS=-1
  P_ACTIVE=-1
  P_MAX_CONN=-1
  P_SLOW=-1
  P_EVICTED=-1
  P_USED_MEM=-1
  P_MAX_MEM=-1
  P_MEM_PCT=-1
  P_REPLICA="-"
  P_REPL_LAG=-1
  P_OPS=-1
}

_probe_redis() {
  local name="${1:-}"
  _probe_defaults

  local info
  info="$(_docker_exec_pref_shell "$name" 'redis-cli INFO 2>/dev/null || true')"
  if [[ -z "$info" ]]; then
    P_LEVEL="fail"
    P_NOTE="redis_cli_failed"
    return 0
  fi

  local connected blocked evicted used_mem max_mem role lag ops
  connected="$(printf '%s\n' "$info" | awk -F: '$1=="connected_clients"{print $2; exit}' | tr -d '\r')"
  blocked="$(printf '%s\n' "$info" | awk -F: '$1=="blocked_clients"{print $2; exit}' | tr -d '\r')"
  evicted="$(printf '%s\n' "$info" | awk -F: '$1=="evicted_keys"{print $2; exit}' | tr -d '\r')"
  used_mem="$(printf '%s\n' "$info" | awk -F: '$1=="used_memory"{print $2; exit}' | tr -d '\r')"
  max_mem="$(printf '%s\n' "$info" | awk -F: '$1=="maxmemory"{print $2; exit}' | tr -d '\r')"
  role="$(printf '%s\n' "$info" | awk -F: '$1=="role"{print $2; exit}' | tr -d '\r')"
  lag="$(printf '%s\n' "$info" | awk -F: '$1=="master_last_io_seconds_ago"{print $2; exit}' | tr -d '\r')"
  ops="$(printf '%s\n' "$info" | awk -F: '$1=="instantaneous_ops_per_sec"{print $2; exit}' | tr -d '\r')"

  P_CONNECTIONS="$(_num_or_default "$connected" -1)"
  P_ACTIVE="$(_num_or_default "$blocked" -1)"
  P_EVICTED="$(_num_or_default "$evicted" -1)"
  P_USED_MEM="$(_num_or_default "$used_mem" -1)"
  P_MAX_MEM="$(_num_or_default "$max_mem" -1)"
  P_REPLICA="${role:--}"
  P_REPL_LAG="$(_num_or_default "$lag" -1)"
  P_OPS="$(_num_or_default "$ops" -1)"
  P_NOTE="ok"
  P_LEVEL="pass"

  if ((P_MAX_MEM > 0 && P_USED_MEM >= 0)); then
    P_MEM_PCT=$((P_USED_MEM * 100 / P_MAX_MEM))
    if ((P_MEM_PCT >= 85)); then
      P_LEVEL="warn"
      P_NOTE="memory_pressure"
    fi
  fi
  if ((P_EVICTED > 0)); then
    P_LEVEL="warn"
    P_NOTE="key_evictions_detected"
  fi
  if [[ "$P_REPLICA" == "slave" || "$P_REPLICA" == "replica" ]]; then
    if ((P_REPL_LAG > 30)); then
      P_LEVEL="warn"
      P_NOTE="replication_lag"
    fi
  fi
}

_probe_mysql() {
  local name="${1:-}"
  _probe_defaults

  local user pass status_out
  user="$(_container_env_value "$name" MYSQL_USER)"
  [[ -n "$user" ]] || user="$(_container_env_value "$name" MARIADB_USER)"
  [[ -n "$user" ]] || user="root"

  pass="$(_container_env_value "$name" MYSQL_PASSWORD)"
  [[ -n "$pass" ]] || pass="$(_container_env_value "$name" MARIADB_PASSWORD)"
  [[ -n "$pass" ]] || pass="$(_container_env_value "$name" MYSQL_ROOT_PASSWORD)"
  [[ -n "$pass" ]] || pass="$(_container_env_value "$name" MARIADB_ROOT_PASSWORD)"

  status_out="$(
    docker exec \
      -e LDS_MYSQL_USER="$user" \
      -e LDS_MYSQL_PASS="$pass" \
      "$name" bash -c '
        MYSQL_PWD="$LDS_MYSQL_PASS" mysql -Nse "
          SHOW GLOBAL STATUS LIKE '\''Threads_connected'\'';
          SHOW GLOBAL STATUS LIKE '\''Threads_running'\'';
          SHOW GLOBAL STATUS LIKE '\''Slow_queries'\'';
          SHOW VARIABLES LIKE '\''max_connections'\'';
        " -u"$LDS_MYSQL_USER" 2>/dev/null
      ' 2>/dev/null || docker exec \
      -e LDS_MYSQL_USER="$user" \
      -e LDS_MYSQL_PASS="$pass" \
      "$name" sh -c '
        MYSQL_PWD="$LDS_MYSQL_PASS" mysql -Nse "
          SHOW GLOBAL STATUS LIKE '\''Threads_connected'\'';
          SHOW GLOBAL STATUS LIKE '\''Threads_running'\'';
          SHOW GLOBAL STATUS LIKE '\''Slow_queries'\'';
          SHOW VARIABLES LIKE '\''max_connections'\'';
        " -u"$LDS_MYSQL_USER" 2>/dev/null
      ' 2>/dev/null || true
  )"

  if [[ -z "$status_out" ]]; then
    P_LEVEL="fail"
    P_NOTE="mysql_probe_failed"
    return 0
  fi

  local connected running slow max_conn
  connected="$(printf '%s\n' "$status_out" | awk '$1=="Threads_connected"{print $2; exit}')"
  running="$(printf '%s\n' "$status_out" | awk '$1=="Threads_running"{print $2; exit}')"
  slow="$(printf '%s\n' "$status_out" | awk '$1=="Slow_queries"{print $2; exit}')"
  max_conn="$(printf '%s\n' "$status_out" | awk '$1=="max_connections"{print $2; exit}')"

  P_CONNECTIONS="$(_num_or_default "$connected" -1)"
  P_ACTIVE="$(_num_or_default "$running" -1)"
  P_SLOW="$(_num_or_default "$slow" -1)"
  P_MAX_CONN="$(_num_or_default "$max_conn" -1)"
  P_NOTE="ok"
  P_LEVEL="pass"

  if ((P_MAX_CONN > 0 && P_CONNECTIONS >= 0)); then
    P_MEM_PCT=$((P_CONNECTIONS * 100 / P_MAX_CONN))
    if ((P_MEM_PCT >= 85)); then
      P_LEVEL="warn"
      P_NOTE="connection_pressure"
    fi
  fi
  if ((P_SLOW > 0)); then
    P_LEVEL="warn"
    P_NOTE="slow_queries_detected"
  fi
}

_probe_postgres() {
  local name="${1:-}"
  _probe_defaults

  local user db pass out
  user="$(_container_env_value "$name" POSTGRES_USER)"
  [[ -n "$user" ]] || user="postgres"
  db="$(_container_env_value "$name" POSTGRES_DB)"
  [[ -n "$db" ]] || db="postgres"
  pass="$(_container_env_value "$name" POSTGRES_PASSWORD)"

  out="$(
    docker exec \
      -e LDS_PG_USER="$user" \
      -e LDS_PG_DB="$db" \
      -e PGPASSWORD="$pass" \
      "$name" bash -c '
        psql -U "$LDS_PG_USER" -d "$LDS_PG_DB" -At -F "|" -c "
          SELECT
            COALESCE((SELECT sum(numbackends) FROM pg_stat_database),0),
            COALESCE((SELECT count(*) FROM pg_stat_activity WHERE state='\''active'\''),0),
            COALESCE((SELECT setting::bigint FROM pg_settings WHERE name='\''max_connections'\''),0),
            CASE WHEN pg_is_in_recovery() THEN '\''replica'\'' ELSE '\''primary'\'' END,
            COALESCE(EXTRACT(EPOCH FROM now()-pg_last_xact_replay_timestamp())::bigint,0),
            COALESCE((SELECT sum(xact_commit+xact_rollback) FROM pg_stat_database),0)
        " 2>/dev/null
      ' 2>/dev/null || docker exec \
      -e LDS_PG_USER="$user" \
      -e LDS_PG_DB="$db" \
      -e PGPASSWORD="$pass" \
      "$name" sh -c '
        psql -U "$LDS_PG_USER" -d "$LDS_PG_DB" -At -F "|" -c "
          SELECT
            COALESCE((SELECT sum(numbackends) FROM pg_stat_database),0),
            COALESCE((SELECT count(*) FROM pg_stat_activity WHERE state='\''active'\''),0),
            COALESCE((SELECT setting::bigint FROM pg_settings WHERE name='\''max_connections'\''),0),
            CASE WHEN pg_is_in_recovery() THEN '\''replica'\'' ELSE '\''primary'\'' END,
            COALESCE(EXTRACT(EPOCH FROM now()-pg_last_xact_replay_timestamp())::bigint,0),
            COALESCE((SELECT sum(xact_commit+xact_rollback) FROM pg_stat_database),0)
        " 2>/dev/null
      ' 2>/dev/null || true
  )"

  if [[ -z "$out" ]]; then
    P_LEVEL="fail"
    P_NOTE="postgres_probe_failed"
    return 0
  fi

  local conn active max_conn replica lag ops
  IFS='|' read -r conn active max_conn replica lag ops <<<"$out"
  P_CONNECTIONS="$(_num_or_default "$conn" -1)"
  P_ACTIVE="$(_num_or_default "$active" -1)"
  P_MAX_CONN="$(_num_or_default "$max_conn" -1)"
  P_REPLICA="${replica:--}"
  P_REPL_LAG="$(_num_or_default "$lag" -1)"
  P_OPS="$(_num_or_default "$ops" -1)"
  P_NOTE="ok"
  P_LEVEL="pass"

  if ((P_MAX_CONN > 0 && P_CONNECTIONS >= 0)); then
    P_MEM_PCT=$((P_CONNECTIONS * 100 / P_MAX_CONN))
    if ((P_MEM_PCT >= 85)); then
      P_LEVEL="warn"
      P_NOTE="connection_pressure"
    fi
  fi
  if [[ "$P_REPLICA" == "replica" && "$P_REPL_LAG" =~ ^-?[0-9]+$ && "$P_REPL_LAG" -gt 30 ]]; then
    P_LEVEL="warn"
    P_NOTE="replication_lag"
  fi
}

usage() {
  cat <<'EOF'
Usage:
  monitor-db [--json] [--engine <all|mysql|postgres|redis>]

Examples:
  monitor-db --json
  monitor-db --json --engine redis
EOF
}

main() {
  local json=0 engine_filter="all"
  while [[ "${1:-}" ]]; do
    case "$1" in
      --json) json=1; shift ;;
      --engine) engine_filter="${2:-all}"; shift 2 ;;
      -h|--help) usage; return 0 ;;
      *) echo "Unknown arg: $1" >&2; usage; return 1 ;;
    esac
  done

  engine_filter="${engine_filter,,}"
  case "$engine_filter" in
    all | mysql | postgres | redis) ;;
    *) engine_filter="all" ;;
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

  local project
  project="$(_infer_project)"

  local -a names=()
  if [[ "$project" != "unknown" && -n "$project" ]]; then
    mapfile -t names < <(docker ps -a --filter "label=com.docker.compose.project=${project}" --format '{{.Names}}' 2>/dev/null | sed '/^[[:space:]]*$/d')
  fi
  if ((${#names[@]} == 0)); then
    mapfile -t names < <(docker ps -a --format '{{.Names}}' 2>/dev/null | sed '/^[[:space:]]*$/d')
  fi

  local raw=""
  if ((${#names[@]})); then
    raw="$(docker inspect -f '{{.Name}}|{{index .Config.Labels "com.docker.compose.service"}}|{{.Config.Image}}|{{.State.Status}}|{{if .State.Health}}{{.State.Health.Status}}{{else}}-{{end}}' "${names[@]}" 2>/dev/null | sed 's#^/##')"
  fi

  local total=0 pass=0 warn=0 fail=0 running=0 not_running=0
  local redis_n=0 mysql_n=0 postgres_n=0
  local -a items=()
  local row name service image state health engine level note
  while IFS='|' read -r name service image state health; do
    [[ -n "$name" ]] || continue
    engine="$(_engine_from "$name $service $image")"
    [[ -n "$engine" ]] || continue
    if [[ "$engine_filter" != "all" && "$engine_filter" != "$engine" ]]; then
      continue
    fi

    case "$engine" in
      redis) ((++redis_n)) ;;
      mysql) ((++mysql_n)) ;;
      postgres) ((++postgres_n)) ;;
    esac

    _probe_defaults
    level="pass"
    note="ok"
    if [[ "$state" != "running" ]]; then
      level="fail"
      note="container_not_running"
      ((++not_running))
    else
      ((++running))
      case "$engine" in
        redis) _probe_redis "$name" ;;
        mysql) _probe_mysql "$name" ;;
        postgres) _probe_postgres "$name" ;;
      esac
      level="$P_LEVEL"
      note="$P_NOTE"
    fi

    case "$level" in
      pass) ((++pass)) ;;
      warn) ((++warn)) ;;
      *) ((++fail)); level="fail" ;;
    esac
    ((++total))

    items+=("$name|$service|$image|$engine|$state|$health|$level|$note|$P_CONNECTIONS|$P_ACTIVE|$P_MAX_CONN|$P_SLOW|$P_EVICTED|$P_USED_MEM|$P_MAX_MEM|$P_MEM_PCT|$P_REPLICA|$P_REPL_LAG|$P_OPS")
  done <<<"$raw"

  if ((json == 0)); then
    printf 'DB/Redis Health | project=%s targets=%d pass=%d warn=%d fail=%d (redis=%d mysql=%d postgres=%d)\n' \
      "$project" "$total" "$pass" "$warn" "$fail" "$redis_n" "$mysql_n" "$postgres_n"
    return 0
  fi

  printf '{'
  printf '"ok":true,'
  printf '"generated_at":"%s",' "$(_json_escape "$(date -u +%Y-%m-%dT%H:%M:%SZ)")"
  printf '"project":"%s",' "$(_json_escape "$project")"
  printf '"filters":{"engine":"%s"},' "$(_json_escape "$engine_filter")"
  printf '"summary":{"targets":%d,"pass":%d,"warn":%d,"fail":%d,"running":%d,"not_running":%d,"redis":%d,"mysql":%d,"postgres":%d},' \
    "$total" "$pass" "$warn" "$fail" "$running" "$not_running" "$redis_n" "$mysql_n" "$postgres_n"
  printf '"items":['
  local f=1
  local connections active max_conn slow evicted used_mem max_mem mem_pct replica repl_lag ops
  for row in "${items[@]}"; do
    IFS='|' read -r name service image engine state health level note connections active max_conn slow evicted used_mem max_mem mem_pct replica repl_lag ops <<<"$row"
    ((f)) || printf ','
    f=0
    printf '{'
    printf '"container":"%s",' "$(_json_escape "$name")"
    printf '"service":"%s",' "$(_json_escape "${service:--}")"
    printf '"image":"%s",' "$(_json_escape "${image:--}")"
    printf '"engine":"%s",' "$(_json_escape "$engine")"
    printf '"state":"%s",' "$(_json_escape "${state:--}")"
    printf '"health":"%s",' "$(_json_escape "${health:--}")"
    printf '"level":"%s",' "$(_json_escape "$level")"
    printf '"note":"%s",' "$(_json_escape "$note")"
    printf '"metrics":{'
    printf '"connections":%s,' "$(_num_or_default "$connections" -1)"
    printf '"active":%s,' "$(_num_or_default "$active" -1)"
    printf '"max_connections":%s,' "$(_num_or_default "$max_conn" -1)"
    printf '"slow_queries":%s,' "$(_num_or_default "$slow" -1)"
    printf '"evicted_keys":%s,' "$(_num_or_default "$evicted" -1)"
    printf '"used_memory":%s,' "$(_num_or_default "$used_mem" -1)"
    printf '"max_memory":%s,' "$(_num_or_default "$max_mem" -1)"
    printf '"pressure_pct":%s,' "$(_num_or_default "$mem_pct" -1)"
    printf '"replica_role":"%s",' "$(_json_escape "$replica")"
    printf '"replication_lag_s":%s,' "$(_num_or_default "$repl_lag" -1)"
    printf '"ops":%s' "$(_num_or_default "$ops" -1)"
    printf '}'
    printf '}'
  done
  printf ']'
  printf '}\n'
}

main "$@"
