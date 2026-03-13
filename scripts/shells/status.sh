#!/usr/bin/env bash
set -euo pipefail

die() {
  printf "Error: %s\n" "$*" >&2
  exit 1
}

_has() { command -v "$1" >/dev/null 2>&1; }

need() {
  local cmd
  for cmd in "$@"; do
    _has "$cmd" || die "Missing command: $cmd"
  done
}

_init_colors() {
  local use_color=1
  if [[ "${STATUS_FORCE_COLOR:-0}" != "1" ]]; then
    if [[ -n "${NO_COLOR:-}" ]] || [[ ! -t 1 ]]; then
      use_color=0
    fi
  fi

  if ((use_color)); then
    BOLD=$'\033[1m'
    DIM=$'\033[2m'
    RED=$'\033[1;31m'
    GREEN=$'\033[1;32m'
    CYAN=$'\033[1;36m'
    YELLOW=$'\033[1;33m'
    BLUE=$'\033[1;34m'
    MAGENTA=$'\033[1;35m'
    NC=$'\033[0m'
  else
    BOLD=""
    DIM=""
    RED=""
    GREEN=""
    CYAN=""
    YELLOW=""
    BLUE=""
    MAGENTA=""
    NC=""
  fi
}

_WORKDIR_USER_SET=0
[[ -n "${WORKING_DIR:-}" || -n "${LDS_WORKDIR:-}" ]] && _WORKDIR_USER_SET=1
_ENV_DOCKER_USER_SET=0
[[ -n "${ENV_DOCKER:-}" ]] && _ENV_DOCKER_USER_SET=1
_VHOST_NGINX_USER_SET=0
[[ -n "${VHOST_NGINX_DIR:-}" ]] && _VHOST_NGINX_USER_SET=1

WORKDIR="${WORKING_DIR:-${LDS_WORKDIR:-$(pwd)}}"
ENV_DOCKER="${ENV_DOCKER:-$WORKDIR/docker/.env}"
VHOST_NGINX_DIR="${VHOST_NGINX_DIR:-}"
__STATUS_PROJECT=""
__STATUS_PROJECT_DISPLAY=""
__STATUS_CTX_INIT=0

_project_from_env_file() {
  [[ -r "$ENV_DOCKER" ]] || return 0
  grep -E '^[[:space:]]*COMPOSE_PROJECT_NAME=' "$ENV_DOCKER" | tail -n1 | cut -d= -f2- | tr -d '\r' || true
}

_normalize_label_value() {
  local v="${1:-}"
  [[ "$v" == "<no value>" ]] && v=""
  printf "%s" "$v"
}

_detect_project_from_containers() {
  local p cid

  p="$(_normalize_label_value "$(docker inspect -f '{{ index .Config.Labels "com.docker.compose.project" }}' SERVER_TOOLS 2>/dev/null || true)")"
  [[ -n "$p" ]] && {
    printf "%s" "$p"
    return 0
  }

  cid="$(docker ps -aq --filter 'label=com.docker.compose.service=server-tools' 2>/dev/null | head -n1 || true)"
  if [[ -n "$cid" ]]; then
    p="$(_normalize_label_value "$(docker inspect -f '{{ index .Config.Labels "com.docker.compose.project" }}' "$cid" 2>/dev/null || true)")"
    [[ -n "$p" ]] && {
      printf "%s" "$p"
      return 0
    }
  fi

  p="$(docker ps -a --format '{{.Label "com.docker.compose.project"}}' 2>/dev/null |
    sed '/^[[:space:]]*$/d' |
    sort |
    uniq -c |
    sort -nr |
    awk 'NR==1{print $2}')"
  printf "%s" "${p:-}"
}

_project_name_from_server_tools() {
  local cid line
  for cid in SERVER_TOOLS "$(docker ps -aq --filter 'label=com.docker.compose.service=server-tools' 2>/dev/null | head -n1 || true)"; do
    [[ -n "$cid" ]] || continue
    while IFS= read -r line; do
      [[ "$line" == "COMPOSE_PROJECT_NAME="* ]] || continue
      printf "%s" "${line#*=}"
      return 0
    done < <(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$cid" 2>/dev/null || true)
  done
}

_detect_workdir_from_containers() {
  local project="${1:-}" cid wd

  wd="$(_normalize_label_value "$(docker inspect -f '{{ index .Config.Labels "com.docker.compose.project.working_dir" }}' SERVER_TOOLS 2>/dev/null || true)")"
  if [[ -n "$wd" && -d "$wd" ]]; then
    printf "%s" "$wd"
    return 0
  fi

  if [[ -n "$project" ]]; then
    cid="$(docker ps -aq --filter "label=com.docker.compose.project=$project" 2>/dev/null | head -n1 || true)"
    if [[ -n "$cid" ]]; then
      wd="$(_normalize_label_value "$(docker inspect -f '{{ index .Config.Labels "com.docker.compose.project.working_dir" }}' "$cid" 2>/dev/null || true)")"
      if [[ -n "$wd" && -d "$wd" ]]; then
        printf "%s" "$wd"
        return 0
      fi
    fi
  fi
}

_dir_conf_count() {
  local d="${1:-}"
  local -a files=()
  [[ -d "$d" ]] || {
    printf "0"
    return 0
  }
  shopt -s nullglob
  files=("$d"/*.conf)
  shopt -u nullglob
  printf "%s" "${#files[@]}"
}

_choose_vhost_nginx_dir() {
  local -a candidates=()
  candidates+=("/etc/share/vhosts/nginx")
  candidates+=("$WORKDIR/configuration/nginx")

  local best="" best_count=-1 d cnt
  for d in "${candidates[@]}"; do
    [[ -d "$d" ]] || continue
    cnt="$(_dir_conf_count "$d")"
    if ((cnt > best_count)); then
      best="$d"
      best_count="$cnt"
    fi
  done
  printf "%s" "$best"
}

_map_host_workdir_to_container() {
  local wd="${1:-}" rel cand
  [[ -n "$wd" ]] || return 0

  if [[ -d "$wd" ]]; then
    printf "%s" "$wd"
    return 0
  fi

  # Common mapping in this stack: ${PROJECT_DIR}:/app where PROJECT_DIR ends with /application
  if [[ "$wd" == *"/application/"* ]]; then
    rel="${wd#*/application/}"
    cand="/app/${rel}"
    [[ -d "$cand" ]] && {
      printf "%s" "$cand"
      return 0
    }
  fi

  cand="/app/$(basename -- "$wd")"
  [[ -d "$cand" ]] && {
    printf "%s" "$cand"
    return 0
  }
}

_looks_like_stack_root() {
  local d="${1:-}"
  [[ -n "$d" && -d "$d" ]] || return 1
  [[ -f "$d/docker/compose/main.yaml" ]]
}

_resolve_workdir() {
  local project="${1:-}" from_labels mapped
  local -a cands=()
  local c

  cands+=("$WORKDIR")
  from_labels="$(_detect_workdir_from_containers "$project")"
  [[ -n "$from_labels" ]] && cands+=("$from_labels")
  mapped="$(_map_host_workdir_to_container "$from_labels")"
  [[ -n "$mapped" ]] && cands+=("$mapped")
  cands+=("/app/docker-tools" "/app")

  for c in "${cands[@]}"; do
    _looks_like_stack_root "$c" && {
      printf "%s" "$c"
      return 0
    }
  done

  for c in "${cands[@]}"; do
    [[ -d "$c" ]] && {
      printf "%s" "$c"
      return 0
    }
  done
}

_init_context() {
  ((__STATUS_CTX_INIT)) && return 0
  __STATUS_CTX_INIT=1

  local project="" project_display=""

  if [[ -n "${STATUS_PROJECT:-}" ]]; then
    project="$STATUS_PROJECT"
    project_display="$project"
  elif [[ -n "${COMPOSE_PROJECT_NAME:-}" ]]; then
    project="$COMPOSE_PROJECT_NAME"
    project_display="$project"
  else
    project="$(_detect_project_from_containers)"
  fi

  if [[ -z "$project" ]]; then
    project="$(_project_from_env_file)"
  fi
  if [[ -z "$project" ]]; then
    project="$(basename -- "$WORKDIR")"
  fi
  __STATUS_PROJECT="$project"

  if ((_WORKDIR_USER_SET == 0)); then
    local detected_wd
    detected_wd="$(_resolve_workdir "$project")"
    [[ -n "$detected_wd" ]] && WORKDIR="$detected_wd"
  fi

  if ((_ENV_DOCKER_USER_SET == 0)); then
    ENV_DOCKER="$WORKDIR/docker/.env"
  fi

  if [[ -z "$project_display" ]]; then
    project_display="$(_project_from_env_file)"
  fi
  if [[ -z "$project_display" ]]; then
    project_display="$(_project_name_from_server_tools)"
  fi
  [[ -n "$project_display" ]] || project_display="$__STATUS_PROJECT"
  __STATUS_PROJECT_DISPLAY="$project_display"

  if ((_VHOST_NGINX_USER_SET == 0)); then
    VHOST_NGINX_DIR="$(_choose_vhost_nginx_dir)"
  fi
}

lds_project() {
  _init_context
  printf "%s" "$__STATUS_PROJECT"
}

normalize_service() {
  local raw="${1:-}"
  local s="${raw//[[:space:]]/}"
  [[ -n "$s" ]] || {
    printf "%s" ""
    return 0
  }

  local low="${s,,}"
  local key="${low//_/}"
  key="${key//-/}"
  if [[ "$key" =~ ^php ]]; then
    local ver="${key#php}"
    ver="${ver//[^0-9]/}"
    if [[ "$ver" =~ ^([0-9])([0-9]).* ]]; then
      printf "php%s%s" "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
      return 0
    fi
    printf "php"
    return 0
  fi

  low="${low//_/-}"
  while [[ "$low" == *"--"* ]]; do
    low="${low//--/-}"
  done
  printf "%s" "$low"
}

_is_valid_domain_name() {
  local d="${1:-}"
  [[ -n "$d" ]] || return 1
  # Match the same domain policy used by other LDS shell tools.
  local re='^([a-zA-Z0-9]([-a-zA-Z0-9]{0,61}[a-zA-Z0-9])?\.)+(localhost|local|test|loc|[a-zA-Z]{2,})$'
  [[ "$d" =~ $re ]]
}

_fit_container_name() {
  local s="${1:-}" w="${2:-28}"
  ((w < 4)) && w=4
  if ((${#s} > w)); then
    printf "%s" "${s:0:w-3}..."
  else
    printf "%s" "$s"
  fi
}

_container_name_col_width() {
  local cap="${1:-28}"
  shift || true
  local w=4 n
  for n in "$@"; do
    ((${#n} > w)) && w=${#n}
  done
  ((w > cap)) && w=$cap
  printf "%s" "$w"
}

_count_glob_matches() {
  local base="${1:-}" pattern="${2:-*}"
  local -a m=()
  [[ -d "$base" ]] || {
    printf "0"
    return 0
  }
  shopt -s nullglob
  m=("$base"/$pattern)
  shopt -u nullglob
  printf "%s" "${#m[@]}"
}

_count_files_recursive() {
  local base="${1:-}" pattern="${2:-*}"
  [[ -d "$base" ]] || {
    printf "0"
    return 0
  }
  find "$base" -type f -name "$pattern" 2>/dev/null | wc -l | awk '{print $1}'
}

_count_files_depth_limited() {
  local base="${1:-}" pattern="${2:-*}" max_depth="${3:-3}"
  [[ -d "$base" ]] || {
    printf "0"
    return 0
  }

  if [[ "$max_depth" == "all" || "$max_depth" == "-1" ]]; then
    _count_files_recursive "$base" "$pattern"
    return 0
  fi

  if [[ "$max_depth" =~ ^[0-9]+$ ]]; then
    find "$base" -mindepth 1 -maxdepth "$max_depth" -type f -name "$pattern" 2>/dev/null | wc -l | awk '{print $1}'
    return 0
  fi

  _count_files_recursive "$base" "$pattern"
}

_count_dir_entries() {
  local base="${1:-}"
  [[ -d "$base" ]] || {
    printf "0"
    return 0
  }
  find "$base" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l | awk '{print $1}'
}

_count_mount_files_for_status() {
  local base="${1:-}" entry_count="${2:-0}"
  [[ -d "$base" ]] || {
    printf "0"
    return 0
  }

  # Deep recursive scans over bind mounts are very slow on some hosts
  # (notably Docker Desktop on Windows). Keep status responsive by using
  # shallow counts unless explicitly requested.
  if [[ "${STATUS_MOUNT_DEEP_COUNT:-0}" == "1" ]]; then
    _count_files_recursive "$base" "*"
    return 0
  fi

  if [[ "$entry_count" =~ ^[0-9]+$ ]]; then
    printf "%s" "$entry_count"
  else
    printf "0"
  fi
}

_status_project_mount_checks_rows() {
  local -a specs=(
    "app|/app|dir"
    "mkcert|/etc/mkcert|dir"
    "certs|/etc/share/certs|dir"
    "docker_sock|/var/run/docker.sock|socket"
    "rootCA|/etc/share/rootCA|dir_nonempty"
    "nginx_vhosts|/etc/share/vhosts/nginx|dir_nonempty"
    "apache_vhosts|/etc/share/vhosts/apache|dir_nonempty"
    "node_vhosts|/etc/share/vhosts/node|dir"
    "fpm_pools|/etc/share/vhosts/fpm|dir_nonempty"
    "sops_repo|/etc/share/vhosts/sops|dir"
    "sops_global|/etc/share/sops/global|dir"
    "sops_keys|/etc/share/sops/keys|dir"
    "sops_config|/etc/share/sops/config|dir"
  )

  local spec key path kind exists entry_count file_count state flag
  for spec in "${specs[@]}"; do
    IFS='|' read -r key path kind <<<"$spec"
    exists=0
    entry_count=0
    file_count=0
    state="WARN"
    flag="unknown"

    case "$kind" in
      socket)
        if [[ -S "$path" ]]; then
          exists=1
          state="PASS"
          flag="present"
        else
          state="FAIL"
          flag="missing"
        fi
        ;;
      dir | dir_nonempty)
        if [[ -d "$path" ]]; then
          exists=1
          entry_count="$(_count_dir_entries "$path")"
          file_count="$(_count_mount_files_for_status "$path" "$entry_count")"
          if [[ "$entry_count" =~ ^[0-9]+$ ]] && ((entry_count > 0)); then
            state="PASS"
            if [[ "${STATUS_MOUNT_DEEP_COUNT:-0}" == "1" ]]; then
              flag="files=$file_count"
            else
              flag="entries=$entry_count"
            fi
          else
            state="WARN"
            flag="empty"
          fi
        else
          state="FAIL"
          flag="missing"
        fi
        ;;
    esac

    printf "%s|%s|%s|%s|%s|%s|%s|%s\n" \
      "$key" "$path" "$kind" "$exists" "$entry_count" "$file_count" "$state" "$flag"
  done
}

_json_escape() {
  local s="${1:-}"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf "%s" "$s"
}

_status_project_cids() {
  local project
  project="$(lds_project)"
  docker ps -aq --filter "label=com.docker.compose.project=$project" 2>/dev/null | sed '/^[[:space:]]*$/d' || true
}

_status_project_names() {
  local project
  project="$(lds_project)"
  docker ps -a --filter "label=com.docker.compose.project=$project" --format '{{.Names}}' 2>/dev/null | sed '/^[[:space:]]*$/d' || true
}

_container_env_value() {
  local cid="${1:-}" key="${2:-}" line
  [[ -n "$cid" && -n "$key" ]] || return 0
  while IFS= read -r line; do
    [[ "$line" == "$key="* ]] || continue
    printf "%s" "${line#*=}"
    return 0
  done < <(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$cid" 2>/dev/null || true)
}

_profiles_from_server_tools() {
  local cid
  cid="$(docker ps -aq --filter 'name=SERVER_TOOLS' 2>/dev/null | head -n1 || true)"
  if [[ -z "$cid" ]]; then
    cid="$(docker ps -aq --filter 'label=com.docker.compose.service=server-tools' 2>/dev/null | head -n1 || true)"
  fi
  [[ -n "$cid" ]] || return 0
  _container_env_value "$cid" "COMPOSE_PROFILES"
}

_status_running_names() {
  local project
  project="$(lds_project)"
  docker ps --filter "label=com.docker.compose.project=$project" --format '{{.Names}}' 2>/dev/null | sed '/^[[:space:]]*$/d' || true
}

_status_active_port_rows() {
  local project
  project="$(lds_project)"
  docker ps \
    --filter "label=com.docker.compose.project=$project" \
    --format '{{.Names}}|{{.Ports}}' 2>/dev/null |
    sed '/^[[:space:]]*$/d' |
    sort || true
}

_status_active_port_summary() {
  local -a rows=()
  mapfile -t rows < <(_status_active_port_rows)
  ((${#rows[@]})) || return 0

  local row name ports piece p
  for row in "${rows[@]}"; do
    IFS='|' read -r name ports <<<"$row"
    [[ -n "$ports" ]] || continue
    IFS=',' read -ra pieces <<<"$ports"
    for piece in "${pieces[@]}"; do
      piece="$(printf "%s" "$piece" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
      [[ -n "$piece" ]] || continue

      # published style: 0.0.0.0:8080->80/tcp or :::443->443/tcp
      p="$(printf "%s" "$piece" | sed -nE 's#.*:([0-9]+)->.*#\1#p')"
      if [[ -n "$p" ]]; then
        printf "%s\n" "$p"
        continue
      fi

      # internal/exposed style: 3306/tcp
      p="$(printf "%s" "$piece" | sed -nE 's#^([0-9]+)/(tcp|udp)$#\1#p')"
      [[ -n "$p" ]] && printf "%s\n" "$p"
    done
  done | awk '!seen[$0]++' | sort -n
}

_status_running_names_for_service() {
  local svc="${1:-}" norm project
  project="$(lds_project)"
  norm="$(normalize_service "$svc")"

  docker ps \
    --filter "label=com.docker.compose.project=$project" \
    --filter "label=com.docker.compose.service=$svc" \
    --format '{{.Names}}' 2>/dev/null | sed '/^[[:space:]]*$/d' || true

  if [[ "$norm" != "$svc" ]]; then
    docker ps \
      --filter "label=com.docker.compose.project=$project" \
      --filter "label=com.docker.compose.service=$norm" \
      --format '{{.Names}}' 2>/dev/null | sed '/^[[:space:]]*$/d' || true
  fi
}

_status_show_stats() {
  local svc="${1:-}"
  local -a names=()
  if [[ -n "$svc" ]]; then
    mapfile -t names < <(_status_running_names_for_service "$svc" | awk '!seen[$0]++')
  else
    mapfile -t names < <(_status_running_names)
  fi

  if ((${#names[@]} == 0)); then
    printf "(no matching containers)\n"
    return 0
  fi

  local -a rows=()
  mapfile -t rows < <(
    docker stats --no-stream --format '{{.Name}}|{{.CPUPerc}}|{{.MemUsage}}|{{.NetIO}}|{{.BlockIO}}' "${names[@]}" 2>/dev/null
  )
  if ((${#rows[@]} == 0)); then
    printf "(no matching containers)\n"
    return 0
  fi

  local w_name
  w_name="$(_container_name_col_width 28 "${names[@]}")"

  printf "  %-*s  %-8s  %-22s  %-15s  %s\n" \
    "$w_name" "NAME" "CPU %" "MEM USAGE / LIMIT" "NET I/O" "BLOCK I/O"

  local row n cpu mem net block
  for row in "${rows[@]}"; do
    IFS='|' read -r n cpu mem net block <<<"$row"
    printf "  %-*s  %-8s  %-22s  %-15s  %s\n" \
      "$w_name" "$(_fit_container_name "$n" "$w_name")" \
      "${cpu:-0.00%}" "${mem:--}" "${net:--}" "${block:--}"
  done
}

_status_show_problems() {
  local -a cids=()
  mapfile -t cids < <(_status_project_cids)
  ((${#cids[@]} == 0)) && {
    printf "(none)\n"
    return 0
  }

  local raw
  raw="$(
    docker inspect -f '{{.Name}}|{{.State.Status}}|{{if .State.Health}}{{.State.Health.Status}}{{end}}|{{.RestartCount}}|{{.State.ExitCode}}|{{.State.FinishedAt}}' \
      "${cids[@]}" 2>/dev/null | sed 's#^/##'
  )"

  local -a rows=()
  local line name state health restart exitcode finished_at
  while IFS='|' read -r name state health restart exitcode finished_at; do
    [[ -n "$name" ]] || continue
    if [[ "$state" != "running" || "$health" == "unhealthy" ]]; then
      rows+=("$name|$state|${health:--}|${restart:-0}|${exitcode:-0}|${finished_at:--}")
    fi
  done <<<"$raw"

  if ((${#rows[@]} == 0)); then
    printf "(none)\n"
    return 0
  fi

  local -a problem_names=()
  for line in "${rows[@]}"; do
    IFS='|' read -r name _ _ _ _ _ <<<"$line"
    problem_names+=("$name")
  done
  local w_name
  w_name="$(_container_name_col_width 28 "${problem_names[@]}")"

  printf "  %-*s  %-10s  %-10s  %-7s  %-18s\n" "$w_name" "NAME" "STATE" "HEALTH" "RESTART" "LAST_EXIT"
  for line in "${rows[@]}"; do
    IFS='|' read -r name state health restart exitcode finished_at <<<"$line"
    local last="code=${exitcode}"
    [[ "$state" != "running" && "$finished_at" != "-" ]] && last+=" @${finished_at}"
    printf "  %-*s  %-10s  %-10s  %-7s  %-18s\n" \
      "$w_name" "$(_fit_container_name "$name" "$w_name")" "$state" "${health:-'-'}" "${restart:-0}" "$last"
  done
}

_to_bytes() {
  local v="$1"
  v="${v//,/}"
  local num unit
  num="$(printf "%s" "$v" | awk '{gsub(/[^0-9.]/,""); print}')"
  unit="$(printf "%s" "$v" | awk '{gsub(/[0-9.]/,""); print}')"
  awk -v n="$num" -v u="$unit" 'BEGIN{
    mul=1;
    if(u=="B"||u=="") mul=1;
    else if(u=="kB"||u=="KB") mul=1000;
    else if(u=="MB") mul=1000^2;
    else if(u=="GB") mul=1000^3;
    else if(u=="TB") mul=1000^4;
    else if(u=="KiB") mul=1024;
    else if(u=="MiB") mul=1024^2;
    else if(u=="GiB") mul=1024^3;
    else if(u=="TiB") mul=1024^4;
    printf "%.0f", (n+0)*mul;
  }'
}

_status_show_top_consumers() {
  local -a names=()
  mapfile -t names < <(_status_running_names)
  if ((${#names[@]} == 0)); then
    printf "(none)\n"
    return 0
  fi

  local stats
  stats="$(docker stats --no-stream --format '{{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}' "${names[@]}" 2>/dev/null || true)"
  [[ -n "$stats" ]] || {
    printf "(no stats)\n"
    return 0
  }

  local -a all_rows=()
  local n cpu mem_full mem_disp cpu_num mem_bytes
  while IFS=$'\t' read -r n cpu mem_full; do
    [[ -n "$n" ]] || continue
    mem_disp="$(printf "%s" "$mem_full" | awk -F'/' '{gsub(/^[[:space:]]+|[[:space:]]+$/,"",$1); print $1}')"
    [[ -n "$mem_disp" ]] || mem_disp="-"
    cpu_num="${cpu%\%}"
    [[ -n "$cpu_num" ]] || cpu_num="0"
    mem_bytes="$(_to_bytes "$mem_disp")"
    all_rows+=("$n|$cpu|$mem_disp|$mem_bytes|$cpu_num")
  done <<<"$stats"

  if ((${#all_rows[@]} == 0)); then
    printf "(no stats)\n"
    return 0
  fi

  local -a mem_rows=() cpu_rows=()
  mapfile -t mem_rows < <(printf "%s\n" "${all_rows[@]}" | sort -t'|' -k4,4nr | head -n 5)
  mapfile -t cpu_rows < <(printf "%s\n" "${all_rows[@]}" | sort -t'|' -k5,5nr | head -n 5)

  local w_name=16 row
  for row in "${mem_rows[@]}" "${cpu_rows[@]}"; do
    [[ -n "$row" ]] || continue
    IFS='|' read -r n _ _ _ _ <<<"$row"
    ((${#n} > w_name)) && w_name=${#n}
  done
  ((w_name > 28)) && w_name=28

  printf "  %bTop by MEM:%b\n" "$BOLD" "$NC"
  for row in "${mem_rows[@]}"; do
    IFS='|' read -r n cpu mem_disp _ _ <<<"$row"
    printf "    %-*s  CPU=%-7s  MEM=%s\n" "$w_name" "$(_fit_container_name "$n" "$w_name")" "$cpu" "$mem_disp"
  done

  printf "  %bTop by CPU:%b\n" "$BOLD" "$NC"
  for row in "${cpu_rows[@]}"; do
    IFS='|' read -r n _ _ _ cpu_num <<<"$row"
    printf "    %-*s  CPU=%s%%\n" "$w_name" "$(_fit_container_name "$n" "$w_name")" "$cpu_num"
  done
}

_status_show_disk() {
  docker system df
}

_status_show_volumes() {
  local project
  project="$(lds_project)"

  local -a vols=()
  mapfile -t vols < <(docker volume ls -q --filter "label=com.docker.compose.project=$project" 2>/dev/null | sed '/^[[:space:]]*$/d')

  local -a cids=()
  mapfile -t cids < <(_status_project_cids)
  if ((${#cids[@]} > 0)); then
    local v
    while IFS= read -r v; do
      [[ -n "$v" ]] && vols+=("$v")
    done < <(
      docker inspect -f '{{range .Mounts}}{{if eq .Type "volume"}}{{.Name}}{{"\n"}}{{end}}{{end}}' "${cids[@]}" 2>/dev/null |
        sed '/^[[:space:]]*$/d'
    )
  fi

  if ((${#vols[@]} > 0)); then
    mapfile -t vols < <(printf "%s\n" "${vols[@]}" | awk '!seen[$0]++')
  fi

  if ((${#vols[@]} == 0)); then
    printf "(none)\n"
    return 0
  fi

  declare -A vol_size=()
  local df
  df="$(docker system df -v 2>/dev/null || true)"
  if [[ -n "$df" ]]; then
    while read -r name _links size _rest; do
      [[ -n "$name" && "$name" != "VOLUME" ]] || continue
      [[ -n "$size" ]] || continue
      vol_size["$name"]="$size"
    done < <(
      printf "%s\n" "$df" |
        awk '
          /^Local Volumes space usage:/ {inside=1; next}
          inside && /^Build cache usage:/ {exit}
          inside && /^[[:space:]]*$/ {next}
          inside {print}
        ' | awk 'NR==1{next} {print $1, $2, $3}'
    )
  fi

  local -a rows=()
  mapfile -t rows < <(docker volume inspect -f '{{.Name}}|{{.Driver}}' "${vols[@]}" 2>/dev/null | sed '/^[[:space:]]*$/d')
  if ((${#rows[@]} == 0)); then
    printf "(none)\n"
    return 0
  fi

  local w_name=6 w_drv=6
  local line name drv
  for line in "${rows[@]}"; do
    IFS='|' read -r name drv <<<"$line"
    ((${#name} > w_name)) && w_name=${#name}
    ((${#drv} > w_drv)) && w_drv=${#drv}
  done
  ((w_name > 40)) && w_name=40
  ((w_drv > 12)) && w_drv=12

  printf "  %b%-*s%b  %b%-*s%b  %b%s%b\n" \
    "$BOLD" "$w_name" "NAME" "$NC" \
    "$BOLD" "$w_drv" "DRIVER" "$NC" \
    "$BOLD" "SIZE" "$NC"

  local any_size=0
  for line in "${rows[@]}"; do
    IFS='|' read -r name drv <<<"$line"
    local n_disp="$name" d_disp="$drv"
    if ((${#n_disp} > w_name)); then n_disp="${n_disp:0:w_name-3}..."; fi
    if ((${#d_disp} > w_drv)); then d_disp="${d_disp:0:w_drv-3}..."; fi
    local sz="${vol_size[$name]:--}"
    [[ "$sz" != "-" ]] && any_size=1
    printf "  %-*s  %-*s  %s\n" "$w_name" "$n_disp" "$w_drv" "${d_disp:-'-'}" "$sz"
  done

  if ((any_size == 0)); then
    printf "\n  %bNote:%b volume sizes unavailable (docker system df -v did not provide volume table)\n" "$YELLOW" "$NC"
  fi
}

_status_show_networks() {
  local project
  project="$(lds_project)"

  local -a cids=()
  mapfile -t cids < <(_status_project_cids)
  if ((${#cids[@]} == 0)); then
    printf "    (none)\n"
    return 0
  fi

  printf "  %bNetworks:%b\n" "$BOLD" "$NC"

  local nets
  nets="$(docker network ls --filter "label=com.docker.compose.project=$project" --format '{{.Name}}' 2>/dev/null | sed '/^[[:space:]]*$/d' || true)"
  if [[ -z "$nets" ]]; then
    nets="$(
      docker inspect -f '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{"\n"}}{{end}}' \
        "${cids[@]}" 2>/dev/null |
        sed '/^[[:space:]]*$/d' | sort -u
    )"
  fi

  if [[ -z "$nets" ]]; then
    printf "    (none)\n"
  else
    printf "    %-22s %-8s %-18s %-18s %-6s\n" "NAME" "DRIVER" "SUBNET" "GATEWAY" "CNTS"
    local n
    while IFS= read -r n; do
      [[ -n "$n" ]] || continue
      local driver subnet gateway cnt
      driver="$(docker network inspect -f '{{.Driver}}' "$n" 2>/dev/null || true)"
      subnet="$(docker network inspect -f '{{with index .IPAM.Config 0}}{{.Subnet}}{{end}}' "$n" 2>/dev/null || true)"
      gateway="$(docker network inspect -f '{{with index .IPAM.Config 0}}{{.Gateway}}{{end}}' "$n" 2>/dev/null || true)"
      cnt="$(docker network inspect -f '{{len .Containers}}' "$n" 2>/dev/null || true)"
      printf "    %-22s %-8s %-18s %-18s %-6s\n" "$n" "${driver:-'-'}" "${subnet:-'-'}" "${gateway:-'-'}" "${cnt:-0}"
    done <<<"$nets"
  fi

  printf "  %bContainer IPs:%b\n" "$BOLD" "$NC"
  local out
  out="$(
    docker inspect -f '{{ $n := .Name }}{{range $k,$v := .NetworkSettings.Networks}}{{$n}}{{"\t"}}{{$k}}{{"\t"}}{{$v.IPAddress}}{{"\n"}}{{end}}' \
      "${cids[@]}" 2>/dev/null | sed 's#^/##' || true
  )"
  if [[ -z "${out//$'\n'/}" ]]; then
    printf "    (none)\n"
    return 0
  fi

  # Matrix view: NAME | <network columns...>
  local -a net_cols=() row_names=()
  mapfile -t net_cols < <(printf "%s\n" "$nets" | sed '/^[[:space:]]*$/d' || true)

  declare -A seen_net=() seen_name=() ip_cell=()
  local n
  for n in "${net_cols[@]}"; do
    seen_net["$n"]=1
  done

  local nm net ip
  while IFS=$'\t' read -r nm net ip; do
    [[ -n "$nm" && -n "$net" && -n "$ip" ]] || continue
    if [[ -z "${seen_name[$nm]+x}" ]]; then
      row_names+=("$nm")
      seen_name["$nm"]=1
    fi
    if [[ -z "${seen_net[$net]+x}" ]]; then
      net_cols+=("$net")
      seen_net["$net"]=1
    fi
    ip_cell["$nm|$net"]="${ip:--}"
  done <<<"$out"

  if ((${#row_names[@]} == 0)); then
    printf "    (none)\n"
    return 0
  fi

  local w_name
  w_name="$(_container_name_col_width 28 "${row_names[@]}")"

  local -a net_w=()
  local i w ipv
  for i in "${!net_cols[@]}"; do
    n="${net_cols[$i]}"
    w=${#n}
    ((w < 7)) && w=7
    for nm in "${row_names[@]}"; do
      ipv="${ip_cell["$nm|$n"]:--}"
      ((${#ipv} > w)) && w=${#ipv}
    done
    ((w > 18)) && w=18
    net_w[$i]=$w
  done

  printf "    %-*s" "$w_name" "NAME"
  for i in "${!net_cols[@]}"; do
    printf "  %-*s" "${net_w[$i]}" "${net_cols[$i]}"
  done
  printf "\n"

  for nm in "${row_names[@]}"; do
    printf "    %-*s" "$w_name" "$(_fit_container_name "$nm" "$w_name")"
    for i in "${!net_cols[@]}"; do
      n="${net_cols[$i]}"
      ipv="${ip_cell["$nm|$n"]:--}"
      printf "  %-*s" "${net_w[$i]}" "$(_fit_container_name "$ipv" "${net_w[$i]}")"
    done
    printf "\n"
  done
}

_status_urls() {
  local f d n
  local -a urls_local=() urls_tools=()

  if [[ -d "${VHOST_NGINX_DIR:-}" ]]; then
    shopt -s nullglob
    for f in "$VHOST_NGINX_DIR"/*.conf; do
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
    printf "%s\n" "${urls_tools[@]}" | awk '!seen[$0]++'
  elif ((${#urls_local[@]})); then
    printf "%s\n" "${urls_local[@]}" | awk '!seen[$0]++'
  elif ((${#urls_tools[@]})); then
    printf "%s\n" "${urls_tools[@]}" | awk '!seen[$0]++'
  fi
}

_status_show_probes() {
  ((${STATUS_PROBE:-1})) || {
    printf "(disabled; set STATUS_PROBE=1)\n"
    return 0
  }
  if ! _has curl; then
    printf "(curl missing)\n"
    return 0
  fi

  local -a urls=()
  mapfile -t urls < <(_status_urls 2>/dev/null || true)
  if ((${#urls[@]} == 0)); then
    printf "(no urls)\n"
    return 0
  fi

  local u host code t
  for u in "${urls[@]}"; do
    host="${u#https://}"
    code="$(curl -ksS --max-time 2 --resolve "${host}:443:127.0.0.1" -o /dev/null -w '%{http_code}' "$u" 2>/dev/null || true)"
    t="$(curl -ksS --max-time 2 --resolve "${host}:443:127.0.0.1" -o /dev/null -w '%{time_total}' "$u" 2>/dev/null || true)"
    [[ -n "$code" ]] || code="000"
    [[ -n "$t" ]] || t="0"
    printf "  %-32s  %s  %ss\n" "$host" "$code" "$t"
  done
}

_status_show_recent_errors() {
  local -a cids=()
  mapfile -t cids < <(_status_project_cids)
  if ((${#cids[@]} == 0)); then
    printf "(none)\n"
    return 0
  fi

  local -a bad=()
  local cid st health
  for cid in "${cids[@]}"; do
    st="$(docker inspect -f '{{.State.Status}}' "$cid" 2>/dev/null || true)"
    health="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{end}}' "$cid" 2>/dev/null || true)"
    if [[ "$st" != "running" || "$health" == "unhealthy" || "$st" == "restarting" ]]; then
      bad+=("$cid")
    fi
  done

  if ((${#bad[@]} == 0)); then
    printf "(none)\n"
    return 0
  fi

  local name
  for cid in "${bad[@]}"; do
    name="$(docker inspect -f '{{.Name}}' "$cid" 2>/dev/null | sed 's#^/##')"
    printf "  %b%s%b\n" "$BOLD" "$(_fit_container_name "$name" 34)" "$NC"
    docker logs --tail 6 "$cid" 2>&1 | sed 's/^/    /' || true
  done
}

_status_show_drift() {
  local project
  project="$(lds_project)"

  local -a compose_names=() labeled=()
  mapfile -t compose_names < <(_status_project_names)
  mapfile -t labeled < <(
    docker ps -a \
      --filter "label=com.docker.compose.project=$project" \
      --format '{{.Names}}' 2>/dev/null | sed '/^[[:space:]]*$/d'
  )

  declare -A have=()
  local n
  for n in "${compose_names[@]}"; do
    have["$n"]=1
  done

  local -a orphans=()
  for n in "${labeled[@]}"; do
    [[ -n "${have[$n]+x}" ]] || orphans+=("$n")
  done

  if ((${#orphans[@]})); then
    printf "  %bOrphan containers:%b %s\n" "$YELLOW" "$NC" "${orphans[*]}"
  else
    printf "  %bOrphan containers:%b (none)\n" "$GREEN" "$NC"
  fi

  local -a v_lab=() v_mnt=()
  mapfile -t v_lab < <(docker volume ls -q --filter "label=com.docker.compose.project=$project" 2>/dev/null | sed '/^[[:space:]]*$/d' || true)

  local -a cids=()
  mapfile -t cids < <(_status_project_cids)
  if ((${#cids[@]})); then
    mapfile -t v_mnt < <(
      docker inspect -f '{{range .Mounts}}{{if eq .Type "volume"}}{{.Name}}{{"\n"}}{{end}}{{end}}' "${cids[@]}" 2>/dev/null |
        sed '/^[[:space:]]*$/d' | awk '!seen[$0]++'
    )
  fi
  declare -A mounted=()
  local v
  for v in "${v_mnt[@]}"; do
    mounted["$v"]=1
  done

  local -a unused=()
  for v in "${v_lab[@]}"; do
    [[ -n "${mounted[$v]+x}" ]] || unused+=("$v")
  done

  if ((${#v_lab[@]} == 0)); then
    printf "  %bLabeled volumes:%b (none)\n" "$DIM" "$NC"
  elif ((${#unused[@]})); then
    printf "  %bUnused labeled volumes:%b %s\n" "$YELLOW" "$NC" "${unused[*]}"
  else
    printf "  %bUnused labeled volumes:%b (none)\n" "$GREEN" "$NC"
  fi

  local reclaim
  reclaim="$(docker system df 2>/dev/null | awk '/Build Cache/ {print $NF}' || true)"
  if [[ -n "$reclaim" && "$reclaim" != "0B" ]]; then
    printf "  %bHint:%b docker builder prune can reclaim build cache\n" "$DIM" "$NC"
  fi
}

_status_checks() {
  local sys_pass=0 sys_warn=0 sys_fail=0
  local proj_pass=0 proj_warn=0 proj_fail=0

  _state_badge() {
    local st="${1:-WARN}"
    case "$st" in
      PASS) printf "%bPASS%b" "$GREEN" "$NC" ;;
      WARN) printf "%bWARN%b" "$YELLOW" "$NC" ;;
      FAIL) printf "%bFAIL%b" "$RED" "$NC" ;;
      *) printf "%s" "$st" ;;
    esac
  }

  _bump() {
    local st="${1:-WARN}"
    local -n p_ref="$2" w_ref="$3" f_ref="$4"
    case "$st" in
      PASS) ((++p_ref)) ;;
      WARN) ((++w_ref)) ;;
      FAIL) ((++f_ref)) ;;
    esac
  }

  _summary_state() {
    local p="${1:-0}" w="${2:-0}" f="${3:-0}"
    if ((f > 0)); then
      printf "FAIL"
    elif ((w > 0)); then
      printf "WARN"
    else
      printf "PASS"
    fi
  }

  # -------- System test --------
  local internet_st="WARN" internet_note="not tested"
  local ip_st="WARN" egress_ip="-"
  local memory_st="WARN" memory_note="unavailable"
  local docker_st="FAIL" docker_note="docker cli missing"

  # internet + global IP
  if _has curl; then
    egress_ip="$(curl -4fsS --max-time 4 https://api.ipify.org 2>/dev/null || true)"
    [[ -n "$egress_ip" ]] || egress_ip="$(curl -4fsS --max-time 4 https://ifconfig.me 2>/dev/null || true)"
    if [[ "$egress_ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
      internet_st="PASS"
      ip_st="PASS"
      internet_note="reachable"
    elif curl -fsSI --max-time 4 https://example.com >/dev/null 2>&1; then
      internet_st="PASS"
      ip_st="WARN"
      internet_note="reachable (public IP unavailable)"
      egress_ip="-"
    else
      internet_st="FAIL"
      ip_st="WARN"
      internet_note="not reachable"
      egress_ip="-"
    fi
  elif _has wget; then
    egress_ip="$(wget -qO- --timeout=4 https://api.ipify.org 2>/dev/null || true)"
    if [[ "$egress_ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
      internet_st="PASS"
      ip_st="PASS"
      internet_note="reachable"
    elif wget -q --spider --timeout=4 https://example.com 2>/dev/null; then
      internet_st="PASS"
      ip_st="WARN"
      internet_note="reachable (public IP unavailable)"
      egress_ip="-"
    else
      internet_st="FAIL"
      ip_st="WARN"
      internet_note="not reachable"
      egress_ip="-"
    fi
  else
    internet_st="WARN"
    ip_st="WARN"
    internet_note="curl/wget missing"
    egress_ip="-"
  fi
  _bump "$internet_st" sys_pass sys_warn sys_fail
  _bump "$ip_st" sys_pass sys_warn sys_fail

  local mem_total_mib=0 mem_avail_mib=0 mem_pct=0
  # memory
  if [[ -r /proc/meminfo ]]; then
    local mem_total_kb mem_avail_kb
    mem_total_kb="$(awk '/MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)"
    mem_avail_kb="$(awk '/MemAvailable:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)"
    if [[ "$mem_total_kb" =~ ^[0-9]+$ ]] && [[ "$mem_avail_kb" =~ ^[0-9]+$ ]] && ((mem_total_kb > 0)); then
      mem_total_mib=$((mem_total_kb / 1024))
      mem_avail_mib=$((mem_avail_kb / 1024))
      mem_pct=$((mem_avail_kb * 100 / mem_total_kb))
      if ((mem_pct >= 15 || mem_avail_mib >= 2048)); then
        memory_st="PASS"
      elif ((mem_pct >= 8 || mem_avail_mib >= 1024)); then
        memory_st="WARN"
      else
        memory_st="FAIL"
      fi
      memory_note="total=${mem_total_mib}MiB available=${mem_avail_mib}MiB (${mem_pct}%)"
    fi
  fi
  _bump "$memory_st" sys_pass sys_warn sys_fail

  # docker runtime
  local has_docker=0 has_compose=0 has_daemon=0
  _has docker && has_docker=1
  if ((has_docker)); then
    (docker compose version >/dev/null 2>&1 || docker-compose version >/dev/null 2>&1) && has_compose=1
    docker info >/dev/null 2>&1 && has_daemon=1
  fi
  if ((has_docker == 0)); then
    docker_st="FAIL"
    docker_note="docker cli missing"
  elif ((has_daemon == 0)); then
    docker_st="FAIL"
    docker_note="daemon unreachable"
  elif ((has_compose == 0)); then
    docker_st="WARN"
    docker_note="compose missing"
  else
    docker_st="PASS"
    docker_note="cli+daemon+compose ok"
  fi
  _bump "$docker_st" sys_pass sys_warn sys_fail

  local sys_state
  sys_state="$(_summary_state "$sys_pass" "$sys_warn" "$sys_fail")"
  printf "  %bSystem test:%b %s  (%d pass, %d warn, %d fail)\n" \
    "$CYAN" "$NC" "$(_state_badge "$sys_state")" "$sys_pass" "$sys_warn" "$sys_fail"
  printf "    - internet: %s  %s\n" "$(_state_badge "$internet_st")" "$internet_note"
  printf "    - egress_ip: %s  %s\n" "$(_state_badge "$ip_st")" "${egress_ip:-"-"}"
  printf "    - memory: %s\n" "$(_state_badge "$memory_st")"
  printf "      - total_mib: %s\n" "${mem_total_mib}"
  printf "      - available_mib: %s\n" "${mem_avail_mib}"
  printf "      - available_percent: %s\n" "${mem_pct}"
  printf "      - detail: %s\n" "$memory_note"
  printf "    - docker: %s  %s\n" "$(_state_badge "$docker_st")" "$docker_note"

  # -------- Project test --------
  local artifacts_st="PASS" artifacts_note=""
  local mounts_st="PASS" mounts_note=""
  local containers_st="WARN" containers_note=""
  local nginx_dir="/etc/share/vhosts/nginx"
  local apache_dir="/etc/share/vhosts/apache"
  local node_dir="/etc/share/vhosts/node"
  local fpm_dir="/etc/share/vhosts/fpm"
  local cert_dir="/etc/share/certs"
  local rootca_dir="/etc/share/rootCA"
  local logs_dir="/global/log"
  local logs_scan_depth="${STATUS_LOG_SCAN_MAX_DEPTH:-3}"

  local c_nginx c_apache c_node c_fpm c_certs c_rootca c_logs_log c_logs_gz c_logs_total
  c_nginx="$(_count_glob_matches "$nginx_dir" "*.conf")"
  c_apache="$(_count_glob_matches "$apache_dir" "*.conf")"
  c_node="$(_count_glob_matches "$node_dir" "*.y*ml")"
  c_fpm="$(_count_glob_matches "$fpm_dir" "*.conf")"
  c_certs="$(_count_glob_matches "$cert_dir" "*")"
  c_rootca="$(_count_glob_matches "$rootca_dir" "*")"
  c_logs_log="$(_count_files_depth_limited "$logs_dir" "*.log" "$logs_scan_depth")"
  c_logs_gz="$(_count_files_depth_limited "$logs_dir" "*.gz" "$logs_scan_depth")"
  c_logs_total=$((c_logs_log + c_logs_gz))

  local -a missing_dirs=()
  [[ -d "$nginx_dir" ]] || missing_dirs+=("nginx")
  [[ -d "$apache_dir" ]] || missing_dirs+=("apache")
  [[ -d "$node_dir" ]] || missing_dirs+=("node")
  [[ -d "$fpm_dir" ]] || missing_dirs+=("fpm")
  [[ -d "$cert_dir" ]] || missing_dirs+=("certs")
  [[ -d "$rootca_dir" ]] || missing_dirs+=("rootCA")
  [[ -d "$logs_dir" ]] || missing_dirs+=("logs")

  artifacts_note="nginx_conf=$c_nginx apache_conf=$c_apache node_yaml=$c_node fpm_conf=$c_fpm cert_files=$c_certs rootca_files=$c_rootca logs_total=$c_logs_total logs_plain=$c_logs_log logs_gz=$c_logs_gz"
  if ((${#missing_dirs[@]})); then
    artifacts_st="WARN"
    artifacts_note+=" | missing_dirs=${missing_dirs[*]}"
  elif ((c_nginx + c_apache + c_node + c_fpm == 0)); then
    artifacts_st="WARN"
    artifacts_note+=" | no vhost artifacts found"
  fi
  _bump "$artifacts_st" proj_pass proj_warn proj_fail

  local -a mount_rows=()
  mapfile -t mount_rows < <(_status_project_mount_checks_rows)
  local mount_pass=0 mount_warn=0 mount_fail=0
  local mount_row m_key m_path m_kind m_exists m_entries m_files m_state m_flag
  for mount_row in "${mount_rows[@]}"; do
    IFS='|' read -r m_key m_path m_kind m_exists m_entries m_files m_state m_flag <<<"$mount_row"
    case "$m_state" in
      PASS) ((++mount_pass)) ;;
      WARN) ((++mount_warn)) ;;
      FAIL) ((++mount_fail)) ;;
    esac
  done
  if ((mount_fail > 0)); then
    mounts_st="FAIL"
  elif ((mount_warn > 0)); then
    mounts_st="WARN"
  else
    mounts_st="PASS"
  fi
  mounts_note="pass=$mount_pass warn=$mount_warn fail=$mount_fail"
  _bump "$mounts_st" proj_pass proj_warn proj_fail

  local -a cids=() bad_lines=()
  mapfile -t cids < <(_status_project_cids)
  local total=0 running=0 healthy=0 no_health=0 starting=0 unhealthy=0 restarting=0 exited=0 other=0
  if ((${#cids[@]})); then
    local raw line name st health
    raw="$(docker inspect -f '{{.Name}}|{{.State.Status}}|{{if .State.Health}}{{.State.Health.Status}}{{else}}-{{end}}' "${cids[@]}" 2>/dev/null | sed 's#^/##' || true)"
    while IFS='|' read -r name st health; do
      [[ -n "$name" ]] || continue
      ((++total))
      case "$st" in
        running)
          ((++running))
          case "$health" in
            healthy) ((++healthy)) ;;
            starting) ((++starting)); bad_lines+=("$name|$st|$health") ;;
            unhealthy) ((++unhealthy)); bad_lines+=("$name|$st|$health") ;;
            - | "") ((++no_health)) ;;
            *) ((++no_health)) ;;
          esac
          ;;
        restarting) ((++restarting)); bad_lines+=("$name|$st|$health") ;;
        exited | dead) ((++exited)); bad_lines+=("$name|$st|$health") ;;
        *) ((++other)); bad_lines+=("$name|$st|$health") ;;
      esac
    done <<<"$raw"
  fi

  if ((total == 0)); then
    containers_st="WARN"
  elif ((unhealthy > 0 || restarting > 0 || exited > 0)); then
    containers_st="FAIL"
  elif ((starting > 0 || other > 0)); then
    containers_st="WARN"
  else
    containers_st="PASS"
  fi
  containers_note="total=$total running=$running healthy=$healthy no-health=$no_health starting=$starting unhealthy=$unhealthy restarting=$restarting exited=$exited"
  _bump "$containers_st" proj_pass proj_warn proj_fail

  local proj_state
  proj_state="$(_summary_state "$proj_pass" "$proj_warn" "$proj_fail")"
  printf "  %bProject containers:%b %s\n" "$CYAN" "$NC" "$(_state_badge "$containers_st")"
  printf "    - total: %s\n" "$total"
  printf "    - running: %s\n" "$running"
  printf "    - healthy: %s\n" "$healthy"
  printf "    - no_health: %s\n" "$no_health"
  printf "    - starting: %s\n" "$starting"
  printf "    - unhealthy: %s\n" "$unhealthy"
  printf "    - restarting: %s\n" "$restarting"
  printf "    - exited: %s\n" "$exited"
  printf "    - other: %s\n" "$other"
  if ((${#bad_lines[@]})); then
    local -a bad_names=()
    local row bn
    for row in "${bad_lines[@]}"; do
      IFS='|' read -r bn _ _ <<<"$row"
      bad_names+=("$bn")
    done
    local w_name
    w_name="$(_container_name_col_width 28 "${bad_names[@]}")"
    printf "    - issues:\n"
    for row in "${bad_lines[@]}"; do
      local bs bh
      IFS='|' read -r bn bs bh <<<"$row"
      printf "      - %-*s  state=%s health=%s\n" \
        "$w_name" "$(_fit_container_name "$bn" "$w_name")" "${bs:-"-"}" "${bh:-"-"}"
    done
  else
    printf "    - issues: (none)\n"
  fi
  printf "  %bProject artifacts:%b %s\n" "$CYAN" "$NC" "$(_state_badge "$artifacts_st")"
  printf "    - nginx_conf: %s\n" "$c_nginx"
  printf "    - apache_conf: %s\n" "$c_apache"
  printf "    - node_yaml: %s\n" "$c_node"
  printf "    - fpm_conf: %s\n" "$c_fpm"
  printf "    - cert_files: %s\n" "$c_certs"
  printf "    - rootca_files: %s\n" "$c_rootca"
  printf "    - logs_total: %s\n" "$c_logs_total"
  printf "    - logs_plain: %s\n" "$c_logs_log"
  printf "    - logs_gz: %s\n" "$c_logs_gz"
  if ((${#missing_dirs[@]})); then
    printf "    - missing_dirs: %s\n" "${missing_dirs[*]}"
  else
    printf "    - missing_dirs: (none)\n"
  fi
  printf "  %bProject mounts:%b %s  %s\n" "$CYAN" "$NC" "$(_state_badge "$mounts_st")" "$mounts_note"
  local w_mount=8
  for mount_row in "${mount_rows[@]}"; do
    IFS='|' read -r m_key _ _ _ _ _ _ _ <<<"$mount_row"
    ((${#m_key} > w_mount)) && w_mount=${#m_key}
  done
  ((w_mount > 14)) && w_mount=14
  for mount_row in "${mount_rows[@]}"; do
    IFS='|' read -r m_key m_path m_kind m_exists m_entries m_files m_state m_flag <<<"$mount_row"
    local m_msg="$m_flag"
    printf "    - %-*s  %s  %s\n" \
      "$w_mount" "$m_key" "$(_state_badge "$m_state")" "$m_msg"
  done
}

_status_json_problems() {
  local -a cids=() rows=()
  mapfile -t cids < <(_status_project_cids)

  if ((${#cids[@]})); then
    local raw line name state health restart exitcode finished_at
    raw="$(
      docker inspect -f '{{.Name}}|{{.State.Status}}|{{if .State.Health}}{{.State.Health.Status}}{{end}}|{{.RestartCount}}|{{.State.ExitCode}}|{{.State.FinishedAt}}' \
        "${cids[@]}" 2>/dev/null | sed 's#^/##'
    )"
    while IFS='|' read -r name state health restart exitcode finished_at; do
      [[ -n "$name" ]] || continue
      if [[ "$state" != "running" || "$health" == "unhealthy" ]]; then
        rows+=("$name|$state|${health:--}|${restart:-0}|${exitcode:-0}|${finished_at:--}")
      fi
    done <<<"$raw"
  fi

  printf '{"count":%d,"items":[' "${#rows[@]}"
  local first=1 row name state health restart exitcode finished_at last_exit
  for row in "${rows[@]}"; do
    IFS='|' read -r name state health restart exitcode finished_at <<<"$row"
    [[ "$restart" =~ ^[0-9]+$ ]] || restart=0
    [[ "$exitcode" =~ ^-?[0-9]+$ ]] || exitcode=0
    last_exit="code=${exitcode}"
    [[ "$state" != "running" && "$finished_at" != "-" ]] && last_exit+=" @${finished_at}"

    ((first)) || printf ","
    first=0
    printf '{'
    printf '"name":"%s",' "$(_json_escape "$name")"
    printf '"state":"%s",' "$(_json_escape "$state")"
    printf '"health":"%s",' "$(_json_escape "${health:--}")"
    printf '"restart_count":%s,' "$restart"
    printf '"exit_code":%s,' "$exitcode"
    printf '"finished_at":"%s",' "$(_json_escape "${finished_at:--}")"
    printf '"last_exit":"%s"' "$(_json_escape "$last_exit")"
    printf '}'
  done
  printf ']}'
}

_status_json_top_consumers() {
  local -a names=() all_rows=() mem_rows=() cpu_rows=()
  mapfile -t names < <(_status_running_names)

  if ((${#names[@]})); then
    local stats n cpu mem_full mem_disp cpu_num mem_bytes
    stats="$(docker stats --no-stream --format '{{.Name}}|{{.CPUPerc}}|{{.MemUsage}}' "${names[@]}" 2>/dev/null || true)"
    while IFS='|' read -r n cpu mem_full; do
      [[ -n "$n" ]] || continue
      mem_disp="$(printf "%s" "$mem_full" | awk -F'/' '{gsub(/^[[:space:]]+|[[:space:]]+$/,"",$1); print $1}')"
      [[ -n "$mem_disp" ]] || mem_disp="-"
      cpu_num="${cpu%\%}"
      [[ "$cpu_num" =~ ^-?[0-9]+([.][0-9]+)?$ ]] || cpu_num="0"
      mem_bytes="$(_to_bytes "$mem_disp")"
      all_rows+=("$n|${cpu:-0.00%}|$mem_disp|$mem_bytes|$cpu_num")
    done <<<"$stats"
  fi

  if ((${#all_rows[@]})); then
    mapfile -t mem_rows < <(printf "%s\n" "${all_rows[@]}" | sort -t'|' -k4,4nr | head -n 5)
    mapfile -t cpu_rows < <(printf "%s\n" "${all_rows[@]}" | sort -t'|' -k5,5nr | head -n 5)
  fi

  printf '{'
  printf '"all":['
  local first=1 row n cpu mem_disp mem_bytes cpu_num
  for row in "${all_rows[@]}"; do
    IFS='|' read -r n cpu mem_disp mem_bytes cpu_num <<<"$row"
    ((first)) || printf ","
    first=0
    printf '{'
    printf '"name":"%s",' "$(_json_escape "$n")"
    printf '"cpu_percent":"%s",' "$(_json_escape "$cpu")"
    printf '"cpu_value":%s,' "$cpu_num"
    printf '"mem_usage":"%s",' "$(_json_escape "$mem_disp")"
    printf '"mem_bytes":%s' "${mem_bytes:-0}"
    printf '}'
  done
  printf '],'

  printf '"by_mem":['
  first=1
  for row in "${mem_rows[@]}"; do
    IFS='|' read -r n cpu mem_disp mem_bytes cpu_num <<<"$row"
    ((first)) || printf ","
    first=0
    printf '{'
    printf '"name":"%s",' "$(_json_escape "$n")"
    printf '"cpu_percent":"%s",' "$(_json_escape "$cpu")"
    printf '"cpu_value":%s,' "$cpu_num"
    printf '"mem_usage":"%s",' "$(_json_escape "$mem_disp")"
    printf '"mem_bytes":%s' "${mem_bytes:-0}"
    printf '}'
  done
  printf '],'

  printf '"by_cpu":['
  first=1
  for row in "${cpu_rows[@]}"; do
    IFS='|' read -r n cpu mem_disp mem_bytes cpu_num <<<"$row"
    ((first)) || printf ","
    first=0
    printf '{'
    printf '"name":"%s",' "$(_json_escape "$n")"
    printf '"cpu_percent":"%s",' "$(_json_escape "$cpu")"
    printf '"cpu_value":%s,' "$cpu_num"
    printf '"mem_usage":"%s",' "$(_json_escape "$mem_disp")"
    printf '"mem_bytes":%s' "${mem_bytes:-0}"
    printf '}'
  done
  printf ']'
  printf '}'
}

_status_json_stats() {
  local svc="${1:-}"
  local -a names=()
  if [[ -n "$svc" ]]; then
    mapfile -t names < <(_status_running_names_for_service "$svc" | awk '!seen[$0]++')
  else
    mapfile -t names < <(_status_running_names)
  fi

  local -a rows=()
  if ((${#names[@]})); then
    mapfile -t rows < <(
      docker stats --no-stream --format '{{.Name}}|{{.CPUPerc}}|{{.MemUsage}}|{{.NetIO}}|{{.BlockIO}}' "${names[@]}" 2>/dev/null
    )
  fi

  printf '{"service_filter":"%s","items":[' "$(_json_escape "${svc:-}")"
  local first=1 row n cpu mem net block mem_usage mem_limit cpu_num
  for row in "${rows[@]}"; do
    IFS='|' read -r n cpu mem net block <<<"$row"
    mem_usage="$(printf "%s" "$mem" | awk -F'/' '{gsub(/^[[:space:]]+|[[:space:]]+$/,"",$1); print $1}')"
    mem_limit="$(printf "%s" "$mem" | awk -F'/' '{gsub(/^[[:space:]]+|[[:space:]]+$/,"",$2); print $2}')"
    [[ -n "$mem_usage" ]] || mem_usage="-"
    [[ -n "$mem_limit" ]] || mem_limit="-"
    cpu_num="${cpu%\%}"
    [[ "$cpu_num" =~ ^-?[0-9]+([.][0-9]+)?$ ]] || cpu_num="0"
    ((first)) || printf ","
    first=0
    printf '{'
    printf '"name":"%s",' "$(_json_escape "$n")"
    printf '"cpu_percent":"%s",' "$(_json_escape "${cpu:-0.00%}")"
    printf '"cpu_value":%s,' "$cpu_num"
    printf '"mem_usage":"%s",' "$(_json_escape "$mem_usage")"
    printf '"mem_limit":"%s",' "$(_json_escape "$mem_limit")"
    printf '"mem_raw":"%s",' "$(_json_escape "${mem:--}")"
    printf '"net_io":"%s",' "$(_json_escape "${net:--}")"
    printf '"block_io":"%s"' "$(_json_escape "${block:--}")"
    printf '}'
  done
  printf ']}'
}

_status_json_containers_core() {
  local -a cids=() ctrs=()
  mapfile -t cids < <(_status_project_cids)
  if ((${#cids[@]})); then
    mapfile -t ctrs < <(
      docker inspect -f '{{.Name}}|{{ index .Config.Labels "com.docker.compose.service" }}|{{.State.Status}}|{{if .State.Health}}{{.State.Health.Status}}{{end}}' \
        "${cids[@]}" 2>/dev/null |
        sed 's#^/##' |
        sed '/^[[:space:]]*$/d' |
        sort
    )
  fi

  local total running
  total=${#ctrs[@]}
  running=0
  if ((total)); then
    local line _n _svc st _h
    for line in "${ctrs[@]}"; do
      IFS='|' read -r _n _svc st _h <<<"$line"
      [[ "$st" == "running" ]] && ((++running))
    done
  fi

  printf '{'
  printf '"summary":{"running":%s,"total":%s},' "$running" "$total"
  printf '"items":['
  local first=1 line name svc state health health_disp
  for line in "${ctrs[@]}"; do
    IFS='|' read -r name svc state health <<<"$line"
    ((first)) || printf ","
    first=0
    health_disp="${health:-}"
    [[ -z "$health_disp" || "$health_disp" == "null" ]] && health_disp="-"
    local health_icon="!"
    if [[ "$health_disp" == "healthy" ]]; then
      health_icon="✓"
    elif [[ "$health_disp" == "unhealthy" ]]; then
      health_icon="×"
    fi
    printf '{'
    printf '"name":"%s",' "$(_json_escape "$name")"
    printf '"service":"%s",' "$(_json_escape "$svc")"
    printf '"state":"%s",' "$(_json_escape "$state")"
    printf '"health":"%s",' "$(_json_escape "$health_disp")"
    printf '"health_icon":"%s"' "$(_json_escape "$health_icon")"
    printf '}'
  done
  printf ']}'
}

_status_json_containers_merged() {
  local stats_svc="${1:-}"
  local core_json top_consumers_json stats_json

  core_json="$(_status_json_containers_core 2>/dev/null || printf '{"summary":{"running":0,"total":0},"items":[]}')"
  top_consumers_json="$(_status_json_top_consumers 2>/dev/null || printf '{"all":[],"by_mem":[],"by_cpu":[]}')"
  stats_json="$(_status_json_stats "$stats_svc" 2>/dev/null || printf '{"service_filter":"","items":[]}')"

  printf '{'
  printf '"core":%s,' "$core_json"
  printf '"top_consumers":%s,' "$top_consumers_json"
  printf '"stats":%s' "$stats_json"
  printf '}'
}

_status_json_disk() {
  local -a rows=()
  mapfile -t rows < <(
    docker system df --format '{{.Type}}|{{.TotalCount}}|{{.Active}}|{{.Size}}|{{.Reclaimable}}' 2>/dev/null |
      sed '/^[[:space:]]*$/d'
  )

  if ((${#rows[@]} == 0)); then
    mapfile -t rows < <(
      docker system df 2>/dev/null |
        awk '
          NR==1 {next}
          /^[[:space:]]*$/ {next}
          {
            if ($1=="Local" && $2=="Volumes") {
              type=$1" "$2; total=$3; active=$4; size=$5; rec=$6
              for(i=7;i<=NF;i++) rec=rec" "$i
            } else if ($1=="Build" && $2=="Cache") {
              type=$1" "$2; total=$3; active=$4; size=$5; rec=$6
              for(i=7;i<=NF;i++) rec=rec" "$i
            } else {
              type=$1; total=$2; active=$3; size=$4; rec=$5
              for(i=6;i<=NF;i++) rec=rec" "$i
            }
            print type "|" total "|" active "|" size "|" rec
          }
        '
    )
  fi

  printf '{"items":['
  local first=1 row type total active size reclaimable
  for row in "${rows[@]}"; do
    IFS='|' read -r type total active size reclaimable <<<"$row"
    [[ -n "$type" ]] || continue
    ((first)) || printf ","
    first=0
    printf '{'
    printf '"type":"%s",' "$(_json_escape "${type:-}")"
    printf '"total":"%s",' "$(_json_escape "${total:-}")"
    printf '"active":"%s",' "$(_json_escape "${active:-}")"
    printf '"size":"%s",' "$(_json_escape "${size:-}")"
    printf '"reclaimable":"%s"' "$(_json_escape "${reclaimable:-}")"
    printf '}'
  done
  printf ']}'
}

_status_json_volumes() {
  local project
  project="$(lds_project)"

  local -a vols=()
  mapfile -t vols < <(docker volume ls -q --filter "label=com.docker.compose.project=$project" 2>/dev/null | sed '/^[[:space:]]*$/d')

  local -a cids=()
  mapfile -t cids < <(_status_project_cids)
  if ((${#cids[@]})); then
    while IFS= read -r v; do
      [[ -n "$v" ]] && vols+=("$v")
    done < <(
      docker inspect -f '{{range .Mounts}}{{if eq .Type "volume"}}{{.Name}}{{"\n"}}{{end}}{{end}}' "${cids[@]}" 2>/dev/null |
        sed '/^[[:space:]]*$/d'
    )
  fi

  if ((${#vols[@]})); then
    mapfile -t vols < <(printf "%s\n" "${vols[@]}" | awk '!seen[$0]++')
  fi

  declare -A vol_size=()
  local df
  df="$(docker system df -v 2>/dev/null || true)"
  if [[ -n "$df" ]]; then
    while read -r name _links size _rest; do
      [[ -n "$name" && "$name" != "VOLUME" ]] || continue
      [[ -n "$size" ]] || continue
      vol_size["$name"]="$size"
    done < <(
      printf "%s\n" "$df" |
        awk '
          /^Local Volumes space usage:/ {inside=1; next}
          inside && /^Build cache usage:/ {exit}
          inside && /^[[:space:]]*$/ {next}
          inside {print}
        ' | awk 'NR==1{next} {print $1, $2, $3}'
    )
  fi

  local -a rows=()
  if ((${#vols[@]})); then
    mapfile -t rows < <(docker volume inspect -f '{{.Name}}|{{.Driver}}' "${vols[@]}" 2>/dev/null | sed '/^[[:space:]]*$/d')
  fi

  local any_size=0
  printf '{"items":['
  local first=1 line name drv sz
  for line in "${rows[@]}"; do
    IFS='|' read -r name drv <<<"$line"
    [[ -n "$name" ]] || continue
    sz="${vol_size[$name]:--}"
    [[ "$sz" != "-" ]] && any_size=1
    ((first)) || printf ","
    first=0
    printf '{'
    printf '"name":"%s",' "$(_json_escape "$name")"
    printf '"driver":"%s",' "$(_json_escape "${drv:--}")"
    printf '"size":"%s"' "$(_json_escape "$sz")"
    printf '}'
  done
  printf '],'
  printf '"size_table_available":'
  if ((any_size)); then
    printf "true"
  else
    printf "false"
  fi
  if ((any_size == 0 && ${#rows[@]} > 0)); then
    printf ',"note":"%s"' "$(_json_escape "volume sizes unavailable (docker system df -v did not provide volume table)")"
  fi
  printf '}'
}

_status_json_networks() {
  local project
  project="$(lds_project)"

  local -a cids=()
  mapfile -t cids < <(_status_project_cids)
  if ((${#cids[@]} == 0)); then
    printf '{"networks":[],"container_ips":[],"matrix":{"columns":[],"rows":[]}}'
    return 0
  fi

  local -a net_cols=()
  mapfile -t net_cols < <(
    docker network ls --filter "label=com.docker.compose.project=$project" --format '{{.Name}}' 2>/dev/null |
      sed '/^[[:space:]]*$/d'
  )
  if ((${#net_cols[@]} == 0)); then
    mapfile -t net_cols < <(
      docker inspect -f '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{"\n"}}{{end}}' \
        "${cids[@]}" 2>/dev/null | sed '/^[[:space:]]*$/d' | sort -u
    )
  fi

  local -a net_rows=()
  declare -A has_net_row=()
  local n driver subnet gateway cnt
  for n in "${net_cols[@]}"; do
    [[ -n "$n" ]] || continue
    driver="$(docker network inspect -f '{{.Driver}}' "$n" 2>/dev/null || true)"
    subnet="$(docker network inspect -f '{{with index .IPAM.Config 0}}{{.Subnet}}{{end}}' "$n" 2>/dev/null || true)"
    gateway="$(docker network inspect -f '{{with index .IPAM.Config 0}}{{.Gateway}}{{end}}' "$n" 2>/dev/null || true)"
    cnt="$(docker network inspect -f '{{len .Containers}}' "$n" 2>/dev/null || true)"
    net_rows+=("$n|${driver:--}|${subnet:--}|${gateway:--}|${cnt:-0}")
    has_net_row["$n"]=1
  done

  local out
  out="$(
    docker inspect -f '{{ $n := .Name }}{{range $k,$v := .NetworkSettings.Networks}}{{$n}}|{{$k}}|{{$v.IPAddress}}{{"\n"}}{{end}}' \
      "${cids[@]}" 2>/dev/null | sed 's#^/##' || true
  )"

  declare -A seen_name=() seen_net=() ip_cell=()
  local -a row_names=() ip_rows=()
  for n in "${net_cols[@]}"; do
    seen_net["$n"]=1
  done

  local nm net ip
  while IFS='|' read -r nm net ip; do
    [[ -n "$nm" && -n "$net" ]] || continue
    if [[ -z "${seen_name[$nm]+x}" ]]; then
      row_names+=("$nm")
      seen_name["$nm"]=1
    fi
    if [[ -z "${seen_net[$net]+x}" ]]; then
      net_cols+=("$net")
      seen_net["$net"]=1
    fi
    ip_cell["$nm|$net"]="${ip:-}"
    ip_rows+=("$nm|$net|${ip:-}")
  done <<<"$out"
  for n in "${net_cols[@]}"; do
    [[ -n "$n" ]] || continue
    [[ -n "${has_net_row[$n]+x}" ]] && continue
    driver="$(docker network inspect -f '{{.Driver}}' "$n" 2>/dev/null || true)"
    subnet="$(docker network inspect -f '{{with index .IPAM.Config 0}}{{.Subnet}}{{end}}' "$n" 2>/dev/null || true)"
    gateway="$(docker network inspect -f '{{with index .IPAM.Config 0}}{{.Gateway}}{{end}}' "$n" 2>/dev/null || true)"
    cnt="$(docker network inspect -f '{{len .Containers}}' "$n" 2>/dev/null || true)"
    net_rows+=("$n|${driver:--}|${subnet:--}|${gateway:--}|${cnt:-0}")
    has_net_row["$n"]=1
  done
  if ((${#row_names[@]})); then
    mapfile -t row_names < <(printf "%s\n" "${row_names[@]}" | awk '!seen[$0]++' | sort)
  fi

  printf '{'
  printf '"networks":['
  local first=1 row
  for row in "${net_rows[@]}"; do
    IFS='|' read -r n driver subnet gateway cnt <<<"$row"
    ((first)) || printf ","
    first=0
    printf '{'
    printf '"name":"%s",' "$(_json_escape "$n")"
    printf '"driver":"%s",' "$(_json_escape "${driver:--}")"
    printf '"subnet":"%s",' "$(_json_escape "${subnet:--}")"
    printf '"gateway":"%s",' "$(_json_escape "${gateway:--}")"
    if [[ "${cnt:-0}" =~ ^[0-9]+$ ]]; then
      printf '"containers":%s' "${cnt:-0}"
    else
      printf '"containers":"%s"' "$(_json_escape "${cnt:-0}")"
    fi
    printf '}'
  done
  printf '],'

  printf '"container_ips":['
  first=1
  for row in "${ip_rows[@]}"; do
    IFS='|' read -r nm net ip <<<"$row"
    ((first)) || printf ","
    first=0
    printf '{'
    printf '"name":"%s",' "$(_json_escape "$nm")"
    printf '"network":"%s",' "$(_json_escape "$net")"
    printf '"ip":"%s"' "$(_json_escape "${ip:-}")"
    printf '}'
  done
  printf '],'

  printf '"matrix":{"columns":['
  first=1
  for n in "${net_cols[@]}"; do
    ((first)) || printf ","
    first=0
    printf '"%s"' "$(_json_escape "$n")"
  done
  printf '],"rows":['
  first=1
  for nm in "${row_names[@]}"; do
    ((first)) || printf ","
    first=0
    printf '{"name":"%s","ips":{' "$(_json_escape "$nm")"
    local first_ip=1 ipv
    for n in "${net_cols[@]}"; do
      ((first_ip)) || printf ","
      first_ip=0
      printf '"%s":' "$(_json_escape "$n")"
      ipv="${ip_cell["$nm|$n"]:-}"
      if [[ -n "$ipv" ]]; then
        printf '"%s"' "$(_json_escape "$ipv")"
      else
        printf "null"
      fi
    done
    printf '}}'
  done
  printf ']}}'
}

_status_json_probes() {
  if ((${STATUS_PROBE:-1} == 0)); then
    printf '{"enabled":false,"reason":"%s","items":[]}' "$(_json_escape "disabled; set STATUS_PROBE=1")"
    return 0
  fi
  if ! _has curl; then
    printf '{"enabled":true,"reason":"%s","items":[]}' "$(_json_escape "curl missing")"
    return 0
  fi

  local -a urls=()
  mapfile -t urls < <(_status_urls 2>/dev/null || true)
  if ((${#urls[@]} == 0)); then
    printf '{"enabled":true,"reason":"%s","items":[]}' "$(_json_escape "no urls")"
    return 0
  fi

  printf '{"enabled":true,"items":['
  local first=1 u host code t
  for u in "${urls[@]}"; do
    [[ -n "$u" ]] || continue
    host="${u#https://}"
    code="$(curl -ksS --max-time 2 --resolve "${host}:443:127.0.0.1" -o /dev/null -w '%{http_code}' "$u" 2>/dev/null || true)"
    t="$(curl -ksS --max-time 2 --resolve "${host}:443:127.0.0.1" -o /dev/null -w '%{time_total}' "$u" 2>/dev/null || true)"
    [[ -n "$code" ]] || code="000"
    [[ -n "$t" ]] || t="0"
    ((first)) || printf ","
    first=0
    printf '{'
    printf '"url":"%s",' "$(_json_escape "$u")"
    printf '"host":"%s",' "$(_json_escape "$host")"
    printf '"status_code":"%s",' "$(_json_escape "$code")"
    printf '"time_seconds":"%s"' "$(_json_escape "$t")"
    printf '}'
  done
  printf ']}'
}

_status_json_recent_errors() {
  local -a cids=() bad=()
  mapfile -t cids < <(_status_project_cids)
  local cid st health
  for cid in "${cids[@]}"; do
    st="$(docker inspect -f '{{.State.Status}}' "$cid" 2>/dev/null || true)"
    health="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{end}}' "$cid" 2>/dev/null || true)"
    if [[ "$st" != "running" || "$health" == "unhealthy" || "$st" == "restarting" ]]; then
      bad+=("$cid")
    fi
  done

  printf '{"count":%d,"items":[' "${#bad[@]}"
  local first=1 name
  for cid in "${bad[@]}"; do
    name="$(docker inspect -f '{{.Name}}' "$cid" 2>/dev/null | sed 's#^/##')"
    st="$(docker inspect -f '{{.State.Status}}' "$cid" 2>/dev/null || true)"
    health="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{end}}' "$cid" 2>/dev/null || true)"
    local -a logs=()
    mapfile -t logs < <(docker logs --tail 6 "$cid" 2>&1 || true)
    ((first)) || printf ","
    first=0
    printf '{'
    printf '"name":"%s",' "$(_json_escape "$name")"
    printf '"state":"%s",' "$(_json_escape "${st:--}")"
    printf '"health":"%s",' "$(_json_escape "${health:--}")"
    printf '"logs":['
    local lf=1 ln
    for ln in "${logs[@]}"; do
      ((lf)) || printf ","
      lf=0
      printf '"%s"' "$(_json_escape "$ln")"
    done
    printf ']'
    printf '}'
  done
  printf ']}'
}

_status_json_drift() {
  local project
  project="$(lds_project)"

  local -a compose_names=() labeled=()
  mapfile -t compose_names < <(_status_project_names)
  mapfile -t labeled < <(
    docker ps -a --filter "label=com.docker.compose.project=$project" --format '{{.Names}}' 2>/dev/null |
      sed '/^[[:space:]]*$/d'
  )

  declare -A have=()
  local n
  for n in "${compose_names[@]}"; do
    have["$n"]=1
  done

  local -a orphans=()
  for n in "${labeled[@]}"; do
    [[ -n "${have[$n]+x}" ]] || orphans+=("$n")
  done

  local -a v_lab=() v_mnt=()
  mapfile -t v_lab < <(docker volume ls -q --filter "label=com.docker.compose.project=$project" 2>/dev/null | sed '/^[[:space:]]*$/d' || true)

  local -a cids=()
  mapfile -t cids < <(_status_project_cids)
  if ((${#cids[@]})); then
    mapfile -t v_mnt < <(
      docker inspect -f '{{range .Mounts}}{{if eq .Type "volume"}}{{.Name}}{{"\n"}}{{end}}{{end}}' "${cids[@]}" 2>/dev/null |
        sed '/^[[:space:]]*$/d' | awk '!seen[$0]++'
    )
  fi
  declare -A mounted=()
  local v
  for v in "${v_mnt[@]}"; do
    mounted["$v"]=1
  done

  local -a unused=()
  for v in "${v_lab[@]}"; do
    [[ -n "${mounted[$v]+x}" ]] || unused+=("$v")
  done

  local reclaim
  reclaim="$(docker system df 2>/dev/null | awk '/Build Cache/ {print $NF}' || true)"
  [[ -n "$reclaim" ]] || reclaim="-"

  printf '{'
  printf '"orphan_containers":['
  local first=1 x
  for x in "${orphans[@]}"; do
    ((first)) || printf ","
    first=0
    printf '"%s"' "$(_json_escape "$x")"
  done
  printf '],'
  printf '"labeled_volumes":['
  first=1
  for x in "${v_lab[@]}"; do
    ((first)) || printf ","
    first=0
    printf '"%s"' "$(_json_escape "$x")"
  done
  printf '],'
  printf '"unused_labeled_volumes":['
  first=1
  for x in "${unused[@]}"; do
    ((first)) || printf ","
    first=0
    printf '"%s"' "$(_json_escape "$x")"
  done
  printf '],'
  printf '"build_cache_reclaimable":"%s",' "$(_json_escape "$reclaim")"
  printf '"builder_prune_hint":'
  if [[ "$reclaim" != "0B" && "$reclaim" != "-" ]]; then
    printf "true"
  else
    printf "false"
  fi
  printf '}'
}

_status_json_checks() {
  local sys_pass=0 sys_warn=0 sys_fail=0
  local proj_pass=0 proj_warn=0 proj_fail=0

  local internet_st="WARN" internet_note="not tested"
  local ip_st="WARN" egress_ip="-"
  local memory_st="WARN" memory_note="unavailable"
  local docker_st="FAIL" docker_note="docker cli missing"

  local mem_total_mib=0 mem_avail_mib=0 mem_pct=0
  local has_docker=0 has_compose=0 has_daemon=0

  if _has curl; then
    egress_ip="$(curl -4fsS --max-time 4 https://api.ipify.org 2>/dev/null || true)"
    [[ -n "$egress_ip" ]] || egress_ip="$(curl -4fsS --max-time 4 https://ifconfig.me 2>/dev/null || true)"
    if [[ "$egress_ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
      internet_st="PASS"
      ip_st="PASS"
      internet_note="reachable"
    elif curl -fsSI --max-time 4 https://example.com >/dev/null 2>&1; then
      internet_st="PASS"
      ip_st="WARN"
      internet_note="reachable (public IP unavailable)"
      egress_ip="-"
    else
      internet_st="FAIL"
      ip_st="WARN"
      internet_note="not reachable"
      egress_ip="-"
    fi
  elif _has wget; then
    egress_ip="$(wget -qO- --timeout=4 https://api.ipify.org 2>/dev/null || true)"
    if [[ "$egress_ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
      internet_st="PASS"
      ip_st="PASS"
      internet_note="reachable"
    elif wget -q --spider --timeout=4 https://example.com 2>/dev/null; then
      internet_st="PASS"
      ip_st="WARN"
      internet_note="reachable (public IP unavailable)"
      egress_ip="-"
    else
      internet_st="FAIL"
      ip_st="WARN"
      internet_note="not reachable"
      egress_ip="-"
    fi
  else
    internet_st="WARN"
    ip_st="WARN"
    internet_note="curl/wget missing"
    egress_ip="-"
  fi
  case "$internet_st" in PASS) ((++sys_pass)) ;; WARN) ((++sys_warn)) ;; FAIL) ((++sys_fail)) ;; esac
  case "$ip_st" in PASS) ((++sys_pass)) ;; WARN) ((++sys_warn)) ;; FAIL) ((++sys_fail)) ;; esac

  if [[ -r /proc/meminfo ]]; then
    local mem_total_kb mem_avail_kb
    mem_total_kb="$(awk '/MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)"
    mem_avail_kb="$(awk '/MemAvailable:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)"
    if [[ "$mem_total_kb" =~ ^[0-9]+$ ]] && [[ "$mem_avail_kb" =~ ^[0-9]+$ ]] && ((mem_total_kb > 0)); then
      mem_total_mib=$((mem_total_kb / 1024))
      mem_avail_mib=$((mem_avail_kb / 1024))
      mem_pct=$((mem_avail_kb * 100 / mem_total_kb))
      if ((mem_pct >= 15 || mem_avail_mib >= 2048)); then
        memory_st="PASS"
      elif ((mem_pct >= 8 || mem_avail_mib >= 1024)); then
        memory_st="WARN"
      else
        memory_st="FAIL"
      fi
      memory_note="total=${mem_total_mib}MiB available=${mem_avail_mib}MiB (${mem_pct}%)"
    fi
  fi
  case "$memory_st" in PASS) ((++sys_pass)) ;; WARN) ((++sys_warn)) ;; FAIL) ((++sys_fail)) ;; esac

  _has docker && has_docker=1
  if ((has_docker)); then
    (docker compose version >/dev/null 2>&1 || docker-compose version >/dev/null 2>&1) && has_compose=1
    docker info >/dev/null 2>&1 && has_daemon=1
  fi
  if ((has_docker == 0)); then
    docker_st="FAIL"
    docker_note="docker cli missing"
  elif ((has_daemon == 0)); then
    docker_st="FAIL"
    docker_note="daemon unreachable"
  elif ((has_compose == 0)); then
    docker_st="WARN"
    docker_note="compose missing"
  else
    docker_st="PASS"
    docker_note="cli+daemon+compose ok"
  fi
  case "$docker_st" in PASS) ((++sys_pass)) ;; WARN) ((++sys_warn)) ;; FAIL) ((++sys_fail)) ;; esac

  local sys_state
  if ((sys_fail > 0)); then
    sys_state="FAIL"
  elif ((sys_warn > 0)); then
    sys_state="WARN"
  else
    sys_state="PASS"
  fi

  local artifacts_st="PASS" artifacts_note=""
  local containers_st="WARN" containers_note=""
  local nginx_dir="/etc/share/vhosts/nginx"
  local apache_dir="/etc/share/vhosts/apache"
  local node_dir="/etc/share/vhosts/node"
  local fpm_dir="/etc/share/vhosts/fpm"
  local cert_dir="/etc/share/certs"
  local rootca_dir="/etc/share/rootCA"
  local logs_dir="/global/log"
  local logs_scan_depth="${STATUS_LOG_SCAN_MAX_DEPTH:-3}"

  local c_nginx c_apache c_node c_fpm c_certs c_rootca c_logs_log c_logs_gz c_logs_total
  c_nginx="$(_count_glob_matches "$nginx_dir" "*.conf")"
  c_apache="$(_count_glob_matches "$apache_dir" "*.conf")"
  c_node="$(_count_glob_matches "$node_dir" "*.y*ml")"
  c_fpm="$(_count_glob_matches "$fpm_dir" "*.conf")"
  c_certs="$(_count_glob_matches "$cert_dir" "*")"
  c_rootca="$(_count_glob_matches "$rootca_dir" "*")"
  c_logs_log="$(_count_files_depth_limited "$logs_dir" "*.log" "$logs_scan_depth")"
  c_logs_gz="$(_count_files_depth_limited "$logs_dir" "*.gz" "$logs_scan_depth")"
  c_logs_total=$((c_logs_log + c_logs_gz))

  local -a missing_dirs=()
  [[ -d "$nginx_dir" ]] || missing_dirs+=("nginx")
  [[ -d "$apache_dir" ]] || missing_dirs+=("apache")
  [[ -d "$node_dir" ]] || missing_dirs+=("node")
  [[ -d "$fpm_dir" ]] || missing_dirs+=("fpm")
  [[ -d "$cert_dir" ]] || missing_dirs+=("certs")
  [[ -d "$rootca_dir" ]] || missing_dirs+=("rootCA")
  [[ -d "$logs_dir" ]] || missing_dirs+=("logs")

  artifacts_note="nginx_conf=$c_nginx apache_conf=$c_apache node_yaml=$c_node fpm_conf=$c_fpm cert_files=$c_certs rootca_files=$c_rootca logs_total=$c_logs_total logs_plain=$c_logs_log logs_gz=$c_logs_gz"
  if ((${#missing_dirs[@]})); then
    artifacts_st="WARN"
    artifacts_note+=" | missing_dirs=${missing_dirs[*]}"
  elif ((c_nginx + c_apache + c_node + c_fpm == 0)); then
    artifacts_st="WARN"
    artifacts_note+=" | no vhost artifacts found"
  fi
  case "$artifacts_st" in PASS) ((++proj_pass)) ;; WARN) ((++proj_warn)) ;; FAIL) ((++proj_fail)) ;; esac

  local -a mount_rows=()
  mapfile -t mount_rows < <(_status_project_mount_checks_rows)
  local mount_pass=0 mount_warn=0 mount_fail=0
  local mount_row m_key m_path m_kind m_exists m_entries m_files m_state m_flag
  for mount_row in "${mount_rows[@]}"; do
    IFS='|' read -r m_key m_path m_kind m_exists m_entries m_files m_state m_flag <<<"$mount_row"
    case "$m_state" in
      PASS) ((++mount_pass)) ;;
      WARN) ((++mount_warn)) ;;
      FAIL) ((++mount_fail)) ;;
    esac
  done
  if ((mount_fail > 0)); then
    mounts_st="FAIL"
  elif ((mount_warn > 0)); then
    mounts_st="WARN"
  else
    mounts_st="PASS"
  fi
  mounts_note="pass=$mount_pass warn=$mount_warn fail=$mount_fail"
  case "$mounts_st" in PASS) ((++proj_pass)) ;; WARN) ((++proj_warn)) ;; FAIL) ((++proj_fail)) ;; esac

  local -a cids=() bad_lines=()
  mapfile -t cids < <(_status_project_cids)
  local total=0 running=0 healthy=0 no_health=0 starting=0 unhealthy=0 restarting=0 exited=0 other=0
  if ((${#cids[@]})); then
    local raw line name st health
    raw="$(docker inspect -f '{{.Name}}|{{.State.Status}}|{{if .State.Health}}{{.State.Health.Status}}{{else}}-{{end}}' "${cids[@]}" 2>/dev/null | sed 's#^/##' || true)"
    while IFS='|' read -r name st health; do
      [[ -n "$name" ]] || continue
      ((++total))
      case "$st" in
        running)
          ((++running))
          case "$health" in
            healthy) ((++healthy)) ;;
            starting) ((++starting)); bad_lines+=("$name|$st|$health") ;;
            unhealthy) ((++unhealthy)); bad_lines+=("$name|$st|$health") ;;
            - | "") ((++no_health)) ;;
            *) ((++no_health)) ;;
          esac
          ;;
        restarting) ((++restarting)); bad_lines+=("$name|$st|$health") ;;
        exited | dead) ((++exited)); bad_lines+=("$name|$st|$health") ;;
        *) ((++other)); bad_lines+=("$name|$st|$health") ;;
      esac
    done <<<"$raw"
  fi

  if ((total == 0)); then
    containers_st="WARN"
  elif ((unhealthy > 0 || restarting > 0 || exited > 0)); then
    containers_st="FAIL"
  elif ((starting > 0 || other > 0)); then
    containers_st="WARN"
  else
    containers_st="PASS"
  fi
  containers_note="total=$total running=$running healthy=$healthy no-health=$no_health starting=$starting unhealthy=$unhealthy restarting=$restarting exited=$exited"
  case "$containers_st" in PASS) ((++proj_pass)) ;; WARN) ((++proj_warn)) ;; FAIL) ((++proj_fail)) ;; esac

  local proj_state
  if ((proj_fail > 0)); then
    proj_state="FAIL"
  elif ((proj_warn > 0)); then
    proj_state="WARN"
  else
    proj_state="PASS"
  fi

  printf '{'
  printf '"system":{'
  printf '"state":"%s",' "$(_json_escape "$sys_state")"
  printf '"summary":{"pass":%s,"warn":%s,"fail":%s},' "$sys_pass" "$sys_warn" "$sys_fail"
  printf '"tests":{'
  printf '"internet":{"state":"%s","detail":"%s"},' "$(_json_escape "$internet_st")" "$(_json_escape "$internet_note")"
  printf '"egress_ip":{"state":"%s","value":"%s"},' "$(_json_escape "$ip_st")" "$(_json_escape "${egress_ip:-"-"}")"
  printf '"memory":{"state":"%s","detail":"%s","total_mib":%s,"available_mib":%s,"available_percent":%s},' \
    "$(_json_escape "$memory_st")" "$(_json_escape "$memory_note")" "$mem_total_mib" "$mem_avail_mib" "$mem_pct"
  printf '"docker":{"state":"%s","detail":"%s","has_cli":%s,"has_compose":%s,"daemon_reachable":%s}' \
    "$(_json_escape "$docker_st")" "$(_json_escape "$docker_note")" \
    "$([[ "$has_docker" == "1" ]] && printf true || printf false)" \
    "$([[ "$has_compose" == "1" ]] && printf true || printf false)" \
    "$([[ "$has_daemon" == "1" ]] && printf true || printf false)"
  printf '}},'

  printf '"project":{'
  printf '"state":"%s",' "$(_json_escape "$proj_state")"
  printf '"summary":{"pass":%s,"warn":%s,"fail":%s},' "$proj_pass" "$proj_warn" "$proj_fail"
  printf '"tests":{'
  printf '"containers":{'
  printf '"state":"%s",' "$(_json_escape "$containers_st")"
  printf '"detail":"%s",' "$(_json_escape "$containers_note")"
  printf '"counts":{"total":%s,"running":%s,"healthy":%s,"no_health":%s,"starting":%s,"unhealthy":%s,"restarting":%s,"exited":%s,"other":%s},' \
    "$total" "$running" "$healthy" "$no_health" "$starting" "$unhealthy" "$restarting" "$exited" "$other"
  printf '"issues":['
  local first=1 row bn bs bh
  for row in "${bad_lines[@]}"; do
    IFS='|' read -r bn bs bh <<<"$row"
    ((first)) || printf ","
    first=0
    printf '{"name":"%s","state":"%s","health":"%s"}' \
      "$(_json_escape "$bn")" "$(_json_escape "${bs:--}")" "$(_json_escape "${bh:--}")"
  done
  printf ']},'
  printf '"artifacts":{'
  printf '"state":"%s",' "$(_json_escape "$artifacts_st")"
  printf '"detail":"%s",' "$(_json_escape "$artifacts_note")"
  printf '"counts":{"nginx_conf":%s,"apache_conf":%s,"node_yaml":%s,"fpm_conf":%s,"cert_files":%s,"rootca_files":%s,"logs_total":%s,"logs_plain":%s,"logs_gz":%s},' \
    "$c_nginx" "$c_apache" "$c_node" "$c_fpm" "$c_certs" "$c_rootca" "$c_logs_total" "$c_logs_log" "$c_logs_gz"
  printf '"missing_dirs":['
  first=1
  local md
  for md in "${missing_dirs[@]}"; do
    ((first)) || printf ","
    first=0
    printf '"%s"' "$(_json_escape "$md")"
  done
  printf ']},'
  printf '"mounts":{'
  printf '"state":"%s",' "$(_json_escape "$mounts_st")"
  printf '"detail":"%s",' "$(_json_escape "$mounts_note")"
  printf '"summary":{"pass":%s,"warn":%s,"fail":%s},' "$mount_pass" "$mount_warn" "$mount_fail"
  printf '"items":['
  first=1
  for mount_row in "${mount_rows[@]}"; do
    IFS='|' read -r m_key m_path m_kind m_exists m_entries m_files m_state m_flag <<<"$mount_row"
    local m_path_json="$m_path"
    [[ "$m_key" == "node_vhosts" ]] && m_path_json=""
    ((first)) || printf ","
    first=0
    printf '{'
    printf '"key":"%s",' "$(_json_escape "$m_key")"
    printf '"path":"%s",' "$(_json_escape "$m_path_json")"
    printf '"kind":"%s",' "$(_json_escape "$m_kind")"
    printf '"state":"%s",' "$(_json_escape "$m_state")"
    printf '"exists":%s,' "$([[ "$m_exists" == "1" ]] && printf true || printf false)"
    printf '"entry_count":%s,' "${m_entries:-0}"
    printf '"file_count":%s,' "${m_files:-0}"
    printf '"flag":"%s",' "$(_json_escape "$m_flag")"
    printf '"empty":%s' "$([[ "${m_entries:-0}" =~ ^[0-9]+$ && "${m_entries:-0}" -eq 0 && "$m_kind" != "socket" ]] && printf true || printf false)"
    printf '}'
  done
  printf ']}}}'
  printf '}'
}

_status_full_json() {
  local stats_svc="${1:-}"
  local generated_at core_json
  local problems_json containers_json disk_json volumes_json
  local networks_json probes_json recent_errors_json drift_json checks_json

  generated_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || true)"
  core_json="$(_status_core 1 0 2>/dev/null || printf '{}')"
  problems_json="$(_status_json_problems 2>/dev/null || printf '{"count":0,"items":[]}')"
  containers_json="$(_status_json_containers_merged "$stats_svc" 2>/dev/null || printf '{"core":{"summary":{"running":0,"total":0},"items":[]},"top_consumers":{"all":[],"by_mem":[],"by_cpu":[]},"stats":{"service_filter":"","items":[]}}')"
  disk_json="$(_status_json_disk 2>/dev/null || printf '{"items":[]}')"
  volumes_json="$(_status_json_volumes 2>/dev/null || printf '{"size_table_available":false,"items":[]}')"
  networks_json="$(_status_json_networks 2>/dev/null || printf '{"networks":[],"container_ips":[],"matrix":{"columns":[],"rows":[]}}')"
  probes_json="$(_status_json_probes 2>/dev/null || printf '{"enabled":false,"items":[]}')"
  recent_errors_json="$(_status_json_recent_errors 2>/dev/null || printf '{"count":0,"items":[]}')"
  drift_json="$(_status_json_drift 2>/dev/null || printf '{"orphan_containers":[],"labeled_volumes":[],"unused_labeled_volumes":[],"build_cache_reclaimable":"-","builder_prune_hint":false}')"
  checks_json="$(_status_json_checks 2>/dev/null || printf '{"system":{"state":"WARN","summary":{"pass":0,"warn":0,"fail":0},"tests":{}},"project":{"state":"WARN","summary":{"pass":0,"warn":0,"fail":0},"tests":{}}}')"

  printf '{'
  printf '"generated_at":"%s",' "$(_json_escape "$generated_at")"
  printf '"full":true,'
  printf '"core":%s,' "${core_json}"
  printf '"sections":{'
  printf '"problems":%s,' "${problems_json}"
  printf '"containers":%s,' "${containers_json}"
  printf '"disk":%s,' "${disk_json}"
  printf '"volumes":%s,' "${volumes_json}"
  printf '"networks":%s,' "${networks_json}"
  printf '"probes":%s,' "${probes_json}"
  printf '"recent_errors":%s,' "${recent_errors_json}"
  printf '"drift":%s,' "${drift_json}"
  printf '"checks":%s' "${checks_json}"
  printf '}'
  printf '}\n'
}

_status_core() {
  local json="$1" quiet="$2"
  local project project_display
  project="$(lds_project)"
  project_display="${__STATUS_PROJECT_DISPLAY:-$project}"

  local profiles=""
  if [[ -r "$ENV_DOCKER" ]]; then
    profiles="$(grep -E '^[[:space:]]*COMPOSE_PROFILES=' "$ENV_DOCKER" | tail -n1 | cut -d= -f2- | tr -d '\r' || true)"
  fi
  if [[ -z "$profiles" ]]; then
    profiles="$(_profiles_from_server_tools)"
  fi

  local -a cids=() ctrs=()
  mapfile -t cids < <(_status_project_cids)
  if ((${#cids[@]})); then
    mapfile -t ctrs < <(
      docker inspect -f '{{.Name}}|{{ index .Config.Labels "com.docker.compose.service" }}|{{.State.Status}}|{{if .State.Health}}{{.State.Health.Status}}{{end}}' \
        "${cids[@]}" 2>/dev/null |
        sed 's#^/##' |
        sed '/^[[:space:]]*$/d' |
        sort
    )
  fi

  local -a urls=()
  mapfile -t urls < <(_status_urls 2>/dev/null || true)
  local -a port_rows=() port_summary=()
  mapfile -t port_rows < <(_status_active_port_rows 2>/dev/null || true)
  mapfile -t port_summary < <(_status_active_port_summary 2>/dev/null || true)

  _json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\t'/\\t}"
    printf "%s" "$s"
  }

  _health_color() {
    local h="$1"
    if [[ -z "$h" || "$h" == "null" ]]; then
      printf "%s" "$DIM"
    elif [[ "$h" == "healthy" ]]; then
      printf "%s" "$GREEN"
    elif [[ "$h" == "unhealthy" ]]; then
      printf "%s" "$RED"
    else
      printf "%s" "$YELLOW"
    fi
  }

  _state_color() {
    local s="$1"
    case "$s" in
      running) printf "%s" "$GREEN" ;;
      exited|dead) printf "%s" "$RED" ;;
      restarting) printf "%s" "$YELLOW" ;;
      *) printf "%s" "$DIM" ;;
    esac
  }

  _health_icon() {
    local h="$1"
    if [[ -z "$h" || "$h" == "null" || "$h" == "-" ]]; then
      printf "!"
    elif [[ "$h" == "unhealthy" ]]; then
      printf "×"
    elif [[ "$h" == "healthy" ]]; then
      printf "✓"
    else
      printf "!"
    fi
  }

  local total running
  total=${#ctrs[@]}
  running=0
  if ((total)); then
    local line _n _svc st _h
    for line in "${ctrs[@]}"; do
      IFS='|' read -r _n _svc st _h <<<"$line"
      [[ "$st" == "running" ]] && ((++running))
    done
  fi

  if ((json)); then
    printf "{"
    printf "\"project\":\"%s\"," "$(_json_escape "$project_display")"
    printf "\"profiles\":\"%s\"," "$(_json_escape "$profiles")"
    printf "\"summary\":{\"running\":%s,\"total\":%s}," "$running" "$total"

    printf "\"ports\":["
    local first=1
    local p
    for p in "${port_summary[@]}"; do
      [[ -n "$p" ]] || continue
      ((first)) || printf ","
      first=0
      printf "\"%s\"" "$(_json_escape "$p")"
    done
    printf "],"

    printf "\"ports_by_container\":["
    first=1
    local pr pn pp
    for pr in "${port_rows[@]}"; do
      IFS='|' read -r pn pp <<<"$pr"
      [[ -n "$pn" ]] || continue
      ((first)) || printf ","
      first=0
      printf "{"
      printf "\"name\":\"%s\"," "$(_json_escape "$pn")"
      printf "\"ports\":\"%s\"" "$(_json_escape "${pp:-}")"
      printf "}"
    done
    printf "],"

    printf "\"urls\":["
    first=1
    local u
    for u in "${urls[@]}"; do
      [[ -n "$u" ]] || continue
      ((first)) || printf ","
      first=0
      printf "\"%s\"" "$(_json_escape "$u")"
    done
    printf "]"
    printf "}\n"
    return 0
  fi

  if ((quiet)); then
    return 0
  fi

  printf "%bProject:%b %s\n" "$CYAN" "$NC" "$project_display"
  [[ -n "$profiles" ]] && printf "%bProfiles:%b %s\n" "$CYAN" "$NC" "$profiles"
  printf "%bContainers:%b %b(%s/%s running)%b\n" "$CYAN" "$NC" "$DIM" "$running" "$total" "$NC"

  if ((${#ctrs[@]} == 0)); then
    printf "  (none)\n"
  else
    local w_name=4 w_svc=7
    local line name svc state health
    for line in "${ctrs[@]}"; do
      IFS='|' read -r name svc state health <<<"$line"
      ((${#name} > w_name)) && w_name=${#name}
      ((${#svc} > w_svc)) && w_svc=${#svc}
    done
    ((w_name > 34)) && w_name=34
    ((w_svc > 18)) && w_svc=18

    printf "  %b%-*s%b  %b%-*s%b  %b%-10s%b  %b%s%b\n" \
      "$BOLD" "$w_name" "NAME" "$NC" \
      "$BOLD" "$w_svc" "SERVICE" "$NC" \
      "$BOLD" "STATE" "$NC" \
      "$BOLD" "HEALTH" "$NC"

    for line in "${ctrs[@]}"; do
      IFS='|' read -r name svc state health <<<"$line"
      local name_disp="$name" svc_disp="$svc"
      if ((${#name_disp} > w_name)); then name_disp="${name_disp:0:w_name-3}..."; fi
      if ((${#svc_disp} > w_svc)); then svc_disp="${svc_disp:0:w_svc-3}..."; fi

      local stc hc health_disp hi
      stc="$(_state_color "$state")"
      hc="$(_health_color "${health:-}")"
      health_disp="${health:-}"
      [[ -z "$health_disp" || "$health_disp" == "null" ]] && health_disp="-"
      hi="$(_health_icon "$health_disp")"

      printf "  %-*s  %-*s  %b%-10s%b  %b%s %s%b\n" \
        "$w_name" "$name_disp" \
        "$w_svc" "$svc_disp" \
        "$stc" "${state:-'-'}" "$NC" \
        "$hc" "$hi" "$health_disp" "$NC"
    done
  fi

  printf "%bPorts:%b\n" "$CYAN" "$NC"
  if ((${#port_rows[@]})); then
    if ((${#port_summary[@]})); then
      printf "  %bPublished:%b %s\n" "$DIM" "$NC" "$(IFS=, ; echo "${port_summary[*]}")"
    fi
    local pr pn pp
    local -a port_names=()
    for pr in "${port_rows[@]}"; do
      IFS='|' read -r pn pp <<<"$pr"
      [[ -n "$pn" ]] || continue
      port_names+=("$pn")
    done
    local w_port_name
    w_port_name="$(_container_name_col_width 28 "${port_names[@]}")"

    for pr in "${port_rows[@]}"; do
      IFS='|' read -r pn pp <<<"$pr"
      [[ -n "$pn" ]] || continue
      printf "  - %-*s %s\n" "$w_port_name" "$(_fit_container_name "$pn" "$w_port_name")" "${pp:-(no published ports)}"
    done
  else
    printf "  (none)\n"
  fi

  printf "%bURLs:%b\n" "$CYAN" "$NC"
  if ((${#urls[@]})); then
    local u
    for u in "${urls[@]}"; do
      [[ -n "$u" ]] || continue
      printf "  - %b%s%b\n" "$BLUE" "$u" "$NC"
    done
  else
    printf "  (none)\n"
  fi
}

cmd_status() {
  local json=0 quiet=0
  while [[ "${1:-}" ]]; do
    case "$1" in
      --json) json=1; shift ;;
      --quiet|-q) quiet=1; shift ;;
      -h|--help) usage; return 0 ;;
      *) break ;;
    esac
  done

  if ((json)); then
    _status_full_json "${1:-}"
    return 0
  fi

  _status_core 0 "$quiet"
  if ((quiet)); then
    return 0
  fi

  printf "\n%bProblems:%b\n" "$CYAN" "$NC"
  _status_show_problems || true

  printf "\n%bContainer runtime:%b\n" "$CYAN" "$NC"
  printf "  %bTop consumers:%b\n" "$BOLD" "$NC"
  _status_show_top_consumers || true

  printf "\n  %bStats:%b\n" "$BOLD" "$NC"
  _status_show_stats "${1:-}" || true

  printf "\n%bDisk:%b\n" "$CYAN" "$NC"
  _status_show_disk || true

  printf "\n%bVolumes:%b\n" "$CYAN" "$NC"
  _status_show_volumes || true

  printf "\n%bNetworks:%b\n" "$CYAN" "$NC"
  _status_show_networks || true

  printf "\n%bProbes:%b\n" "$CYAN" "$NC"
  _status_show_probes || true

  printf "\n%bRecent errors:%b\n" "$CYAN" "$NC"
  _status_show_recent_errors || true

  printf "\n%bDrift:%b\n" "$CYAN" "$NC"
  _status_show_drift || true

  printf "\n%bChecks:%b\n" "$CYAN" "$NC"
  _status_checks || true
}

usage() {
  cat <<'EOF'
Usage:
  status [--json] [--quiet] [service]

Examples:
  status
  status --json
  status php82
  STATUS_PROJECT=LocalDevStack status
EOF
}

main() {
  _init_colors
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    return 0
  fi

  need docker awk sed grep find sort

  if ! docker info >/dev/null 2>&1; then
    die "Docker daemon is not reachable."
  fi

  _init_context
  cmd_status "$@"
}

main "$@"
