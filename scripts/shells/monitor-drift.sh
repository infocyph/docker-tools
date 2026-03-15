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

_docker_exec_pref_shell() {
  local c="${1:-}" script="${2:-}"
  [[ -n "$c" ]] || return 0
  docker exec "$c" bash -c "$script" 2>/dev/null || docker exec "$c" sh -c "$script" 2>/dev/null || true
}

_container_sha() {
  local c="${1:-}" f="${2:-}"
  [[ -n "$c" && -n "$f" ]] || return 0
  _docker_exec_pref_shell "$c" "if [ -f \"$f\" ]; then sha256sum \"$f\" 2>/dev/null | awk '{print \$1}'; fi"
}

_choose_dest_dir() {
  local c="${1:-}"
  shift || true
  local d
  for d in "$@"; do
    [[ -n "$d" ]] || continue
    if docker exec "$c" bash -c "[ -d \"$d\" ]" >/dev/null 2>&1 || docker exec "$c" sh -c "[ -d \"$d\" ]" >/dev/null 2>&1; then
      printf '%s' "$d"
      return 0
    fi
  done
}

_find_container() {
  local key="${1:-}" raw n s i st
  raw="$(docker ps -a --format '{{.Names}}|{{.Label "com.docker.compose.service"}}|{{.Image}}|{{.State}}' 2>/dev/null || true)"
  while IFS='|' read -r n s i st; do
    [[ -n "$n" ]] || continue
    case "$key" in
      nginx)
        if [[ "${n,,} ${s,,} ${i,,}" == *nginx* ]]; then
          printf '%s|%s\n' "$n" "$st"
          return 0
        fi
        ;;
      apache)
        if [[ "${n,,} ${s,,} ${i,,}" == *apache* ]]; then
          printf '%s|%s\n' "$n" "$st"
          return 0
        fi
        ;;
      fpm)
        if [[ "${n,,} ${s,,} ${i,,}" == *php* || "${n,,} ${s,,} ${i,,}" == *fpm* ]]; then
          printf '%s|%s\n' "$n" "$st"
          return 0
        fi
        ;;
    esac
  done <<<"$raw"
}

usage() {
  cat <<'EOF'
Usage:
  monitor-drift [--json]

Examples:
  monitor-drift --json
EOF
}

main() {
  local json=0
  while [[ "${1:-}" ]]; do
    case "$1" in
      --json) json=1; shift ;;
      -h|--help) usage; return 0 ;;
      *) echo "Unknown arg: $1" >&2; usage; return 1 ;;
    esac
  done

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

  local pass=0 warn=0 fail=0 components=0
  local -a items=()
  local comp src_dir find_glob container_info container cstate dest_dir

  # component|source_dir|glob|dest_candidates_csv
  local -a specs=(
    "nginx|/etc/share/vhosts/nginx|*.conf|/etc/nginx/conf.d,/etc/share/vhosts/nginx,/etc/nginx/sites-enabled"
    "apache|/etc/share/vhosts/apache|*.conf|/etc/apache2/sites-enabled,/etc/apache2/conf-enabled,/etc/share/vhosts/apache,/usr/local/apache2/conf/vhosts"
    "fpm|/etc/share/vhosts/fpm|*.conf|/usr/local/etc/php-fpm.domains,/usr/local/etc/php-fpm.d,/etc/share/vhosts/fpm"
  )

  for spec in "${specs[@]}"; do
    IFS='|' read -r comp src_dir find_glob dest_dir <<<"$spec"
    ((++components))

    local level="pass" note="ok"
    local total_src=0 matched=0 changed=0 missing=0 extra=0
    container="-"
    cstate="-"

    container_info="$(_find_container "$comp" || true)"
    if [[ -z "$container_info" ]]; then
      level="warn"
      note="container_not_found"
      items+=("$comp|$container|$cstate|$src_dir|-|$total_src|$matched|$changed|$missing|$extra|$level|$note")
      ((++warn))
      continue
    fi
    IFS='|' read -r container cstate <<<"$container_info"
    if [[ "$cstate" != "running" ]]; then
      level="fail"
      note="container_not_running"
      items+=("$comp|$container|$cstate|$src_dir|-|$total_src|$matched|$changed|$missing|$extra|$level|$note")
      ((++fail))
      continue
    fi

    local -a dest_candidates=()
    IFS=',' read -r -a dest_candidates <<<"$dest_dir"
    dest_dir="$(_choose_dest_dir "$container" "${dest_candidates[@]}")"
    if [[ -z "$dest_dir" ]]; then
      level="fail"
      note="active_config_dir_not_found"
      items+=("$comp|$container|$cstate|$src_dir|-|$total_src|$matched|$changed|$missing|$extra|$level|$note")
      ((++fail))
      continue
    fi

    if [[ ! -d "$src_dir" ]]; then
      level="warn"
      note="source_dir_missing"
      items+=("$comp|$container|$cstate|$src_dir|$dest_dir|$total_src|$matched|$changed|$missing|$extra|$level|$note")
      ((++warn))
      continue
    fi

    local src_file rel base host_sha dst_rel dst_base dst_sha
    while IFS= read -r src_file; do
      [[ -f "$src_file" ]] || continue
      rel="${src_file#$src_dir/}"
      base="$(basename -- "$src_file")"
      ((++total_src))

      host_sha="$(sha256sum "$src_file" 2>/dev/null | awk '{print $1}')"
      dst_rel="${dest_dir}/${rel}"
      dst_base="${dest_dir}/${base}"
      dst_sha="$(_container_sha "$container" "$dst_rel")"
      if [[ -z "$dst_sha" && "$dst_rel" != "$dst_base" ]]; then
        dst_sha="$(_container_sha "$container" "$dst_base")"
      fi

      if [[ -z "$dst_sha" ]]; then
        ((++missing))
      elif [[ "$dst_sha" == "$host_sha" ]]; then
        ((++matched))
      else
        ((++changed))
      fi
    done < <(find "$src_dir" -type f -name "$find_glob" 2>/dev/null)

    # Extra files in active destination that have no source counterpart by basename.
    local tmp_src tmp_dst
    tmp_src="$(mktemp)"
    tmp_dst="$(mktemp)"
    find "$src_dir" -type f -name "$find_glob" -exec basename {} \; 2>/dev/null | sort -u >"$tmp_src" || true
    _docker_exec_pref_shell "$container" "find \"$dest_dir\" -type f -name \"$find_glob\" -exec basename {} \\; 2>/dev/null" | sort -u >"$tmp_dst" || true
    extra="$(comm -13 "$tmp_src" "$tmp_dst" 2>/dev/null | sed '/^[[:space:]]*$/d' | wc -l | awk '{print $1}')"
    extra="${extra:-0}"
    rm -f "$tmp_src" "$tmp_dst" >/dev/null 2>&1 || true

    if ((changed > 0 || missing > 0)); then
      level="fail"
      note="drift_detected"
      ((++fail))
    elif ((extra > 0)); then
      level="warn"
      note="active_extra_files"
      ((++warn))
    else
      level="pass"
      note="in_sync"
      ((++pass))
    fi

    items+=("$comp|$container|$cstate|$src_dir|$dest_dir|$total_src|$matched|$changed|$missing|$extra|$level|$note")
  done

  if ((json == 0)); then
    printf 'Config Drift | project=%s components=%d pass=%d warn=%d fail=%d\n' \
      "$project" "$components" "$pass" "$warn" "$fail"
    return 0
  fi

  printf '{'
  printf '"ok":true,'
  printf '"generated_at":"%s",' "$(_json_escape "$(date -u +%Y-%m-%dT%H:%M:%SZ)")"
  printf '"project":"%s",' "$(_json_escape "$project")"
  printf '"summary":{"components":%d,"pass":%d,"warn":%d,"fail":%d},' "$components" "$pass" "$warn" "$fail"
  printf '"items":['
  local f=1 row
  for row in "${items[@]}"; do
    IFS='|' read -r comp container cstate src_dir dest_dir total_src matched changed missing extra level note <<<"$row"
    ((f)) || printf ','
    f=0
    printf '{'
    printf '"component":"%s",' "$(_json_escape "$comp")"
    printf '"container":"%s",' "$(_json_escape "$container")"
    printf '"container_state":"%s",' "$(_json_escape "$cstate")"
    printf '"source_dir":"%s",' "$(_json_escape "$src_dir")"
    printf '"active_dir":"%s",' "$(_json_escape "$dest_dir")"
    printf '"source_files":%s,' "$(_json_escape "$total_src")"
    printf '"matched":%s,' "$(_json_escape "$matched")"
    printf '"changed":%s,' "$(_json_escape "$changed")"
    printf '"missing":%s,' "$(_json_escape "$missing")"
    printf '"extra":%s,' "$(_json_escape "$extra")"
    printf '"level":"%s",' "$(_json_escape "$level")"
    printf '"note":"%s"' "$(_json_escape "$note")"
    printf '}'
  done
  printf ']'
  printf '}\n'
}

main "$@"
