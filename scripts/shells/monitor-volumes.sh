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

_to_bytes() {
  local v="${1:-}"
  v="${v//,/}"
  local num unit
  num="$(printf '%s' "$v" | awk '{gsub(/[^0-9.]/,""); print}')"
  unit="$(printf '%s' "$v" | awk '{gsub(/[0-9.]/,""); print}')"
  awk -v n="${num:-0}" -v u="$unit" 'BEGIN{
    mul=1
    if(u=="B"||u=="") mul=1
    else if(u=="kB"||u=="KB") mul=1000
    else if(u=="MB") mul=1000^2
    else if(u=="GB") mul=1000^3
    else if(u=="TB") mul=1000^4
    else if(u=="KiB") mul=1024
    else if(u=="MiB") mul=1024^2
    else if(u=="GiB") mul=1024^3
    else if(u=="TiB") mul=1024^4
    printf "%.0f", (n+0)*mul
  }'
}

_num_or_default() {
  local v="${1:-}" d="${2:-0}"
  if [[ "$v" =~ ^-?[0-9]+$ ]]; then
    printf '%s' "$v"
  else
    printf '%s' "$d"
  fi
}

_state_dir() {
  local -a candidates=()
  if [[ -n "${MONITOR_STATE_DIR:-}" ]]; then
    candidates+=("$MONITOR_STATE_DIR")
  fi
  candidates+=("/etc/share/state" "/tmp/monitor-state" "/tmp")

  local dir probe
  for dir in "${candidates[@]}"; do
    [[ -n "$dir" ]] || continue
    mkdir -p "$dir" >/dev/null 2>&1 || true
    probe="${dir%/}/.monitor-volumes-write.$$"
    if touch "$probe" >/dev/null 2>&1; then
      rm -f "$probe" >/dev/null 2>&1 || true
      printf '%s' "$dir"
      return 0
    fi
  done

  printf '/tmp'
}

_bytes_human() {
  local b="${1:-0}"
  awk -v bytes="$b" 'BEGIN{
    n=bytes+0
    split("B KB MB GB TB",u," ")
    i=1
    while(n>=1024 && i<5){ n/=1024; i++ }
    if(i==1) printf "%.0f %s", n, u[i]
    else printf "%.2f %s", n, u[i]
  }'
}

_state_label() {
  local note="${1:-}" level="${2:-pass}"
  case "$note" in
    ok|"") printf 'OK' ;;
    growth_critical) printf 'Growth Critical' ;;
    growth_fast) printf 'Growth Fast' ;;
    capacity_critical) printf 'Capacity Critical' ;;
    capacity_high) printf 'Capacity High' ;;
    inode_critical) printf 'Inode Critical' ;;
    inode_high) printf 'Inode High' ;;
    *)
      case "$level" in
        fail) printf 'Fail' ;;
        warn) printf 'Warn' ;;
        *) printf 'OK' ;;
      esac
      ;;
  esac
}

_emit_json_csv_array() {
  local raw="${1:-}"
  local -a parts=()
  local part trimmed
  IFS=',' read -r -a parts <<<"$raw"
  printf '['
  local first=1
  for part in "${parts[@]}"; do
    trimmed="${part#"${part%%[![:space:]]*}"}"
    trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
    [[ -n "$trimmed" && "$trimmed" != "-" ]] || continue
    ((first)) || printf ','
    first=0
    printf '"%s"' "$(_json_escape "$trimmed")"
  done
  printf ']'
}

_helper_image() {
  local name img
  for name in SERVER_TOOLS "$(docker ps -q --filter 'label=com.docker.compose.service=server-tools' | head -n1)"; do
    [[ -n "$name" ]] || continue
    img="$(docker inspect -f '{{.Config.Image}}' "$name" 2>/dev/null || true)"
    if [[ -n "$img" ]]; then
      printf '%s' "$img"
      return 0
    fi
  done
  img="$(docker ps --format '{{.Image}}' 2>/dev/null | head -n1 || true)"
  printf '%s' "$img"
}

_pick_probe_runtime() {
  local -a candidates=()
  local img

  img="$(_helper_image)"
  [[ -n "$img" ]] && candidates+=("$img")

  while IFS= read -r img; do
    [[ -n "$img" ]] || continue
    local seen=0 existing
    for existing in "${candidates[@]}"; do
      if [[ "$existing" == "$img" ]]; then
        seen=1
        break
      fi
    done
    ((seen == 0)) && candidates+=("$img")
  done < <(docker ps --format '{{.Image}}' 2>/dev/null | sed '/^[[:space:]]*$/d')

  local shell image
  for image in "${candidates[@]}"; do
    for shell in bash sh; do
      if docker run --rm --entrypoint "$shell" "$image" -c 'command -v df >/dev/null 2>&1 && command -v find >/dev/null 2>&1' >/dev/null 2>&1; then
        printf '%s|%s' "$image" "$shell"
        return 0
      fi
    done
  done

  printf '|'
}

usage() {
  cat <<'EOF'
Usage:
  monitor-volumes [--json] [--top <n>] [--inode-top <n>]

Examples:
  monitor-volumes --json
  monitor-volumes --json --top 20 --inode-top 20
EOF
}

main() {
  local json=0 top_n=0 inode_top_n=0
  local max_rows="${MONITOR_VOLUMES_MAX_ROWS:-200}"
  while [[ "${1:-}" ]]; do
    case "$1" in
      --json) json=1; shift ;;
      --top) top_n="${2:-0}"; shift 2 ;;
      --inode-top) inode_top_n="${2:-0}"; shift 2 ;;
      -h|--help) usage; return 0 ;;
      *) echo "Unknown arg: $1" >&2; usage; return 1 ;;
    esac
  done

  [[ "$max_rows" =~ ^[0-9]+$ ]] || max_rows=200
  ((max_rows < 1)) && max_rows=200
  [[ "$top_n" =~ ^[0-9]+$ ]] || top_n=0
  [[ "$inode_top_n" =~ ^[0-9]+$ ]] || inode_top_n=0
  ((top_n <= 0)) && top_n="$max_rows"
  ((top_n > max_rows)) && top_n="$max_rows"
  ((inode_top_n <= 0)) && inode_top_n="$top_n"
  ((inode_top_n > top_n)) && inode_top_n="$top_n"

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

  local -a cids=()
  if [[ "$project" != "unknown" && -n "$project" ]]; then
    mapfile -t cids < <(docker ps -aq --filter "label=com.docker.compose.project=${project}" 2>/dev/null | sed '/^[[:space:]]*$/d')
  fi
  if ((${#cids[@]} == 0)); then
    mapfile -t cids < <(docker ps -aq 2>/dev/null | sed '/^[[:space:]]*$/d')
  fi

  declare -A vol_service=() vol_present=() vol_probe_targets=()
  local cid cname crunning service mounts m mname mdest
  for cid in "${cids[@]}"; do
    [[ -n "$cid" ]] || continue
    cname="$(docker inspect -f '{{.Name}}' "$cid" 2>/dev/null | sed 's#^/##' || true)"
    [[ -n "$cname" ]] || cname="$cid"
    crunning="$(docker inspect -f '{{if .State.Running}}1{{else}}0{{end}}' "$cid" 2>/dev/null || true)"
    [[ "$crunning" =~ ^[01]$ ]] || crunning=0
    service="$(docker inspect -f '{{index .Config.Labels "com.docker.compose.service"}}' "$cid" 2>/dev/null || true)"
    [[ -n "$service" ]] || service="-"
    mounts="$(docker inspect -f '{{range .Mounts}}{{if eq .Type "volume"}}{{.Name}}|{{.Destination}}{{println}}{{end}}{{end}}' "$cid" 2>/dev/null || true)"
    while IFS= read -r m; do
      [[ -n "$m" ]] || continue
      IFS='|' read -r mname mdest <<<"$m"
      [[ -n "$mname" ]] || continue
      vol_present["$mname"]=1
      if [[ -z "${vol_service[$mname]:-}" ]]; then
        vol_service["$mname"]="$service"
      elif [[ ",${vol_service[$mname]}," != *",$service,"* ]]; then
        vol_service["$mname"]="${vol_service[$mname]},$service"
      fi
      if [[ "$crunning" == "1" && -n "$mdest" ]]; then
        if [[ -n "${vol_probe_targets[$mname]:-}" ]]; then
          vol_probe_targets["$mname"]+=$'\n'"$cname|$mdest"
        else
          vol_probe_targets["$mname"]="$cname|$mdest"
        fi
      fi
    done <<<"$mounts"
  done

  local raw_df
  raw_df="$(docker system df -v 2>/dev/null || true)"
  local -a volume_rows=()
  mapfile -t volume_rows < <(
    printf '%s\n' "$raw_df" | awk '
      BEGIN{sec=0;hdr=0;seen=0}
      /^Local Volumes space usage:/ {sec=1; next}
      sec==1 && /^VOLUME NAME[[:space:]]+LINKS[[:space:]]+SIZE/ {hdr=1; next}
      sec==1 && hdr==1 {
        if ($0 ~ /^[[:space:]]*$/) {
          if (seen) exit
          next
        }
        seen=1
        name=$1; links=$2; size=$3
        if (name != "" && links ~ /^[0-9]+$/) print name "|" links "|" size
      }
    '
  )

  if ((${#volume_rows[@]} == 0)); then
    mapfile -t volume_rows < <(
      docker volume ls --format '{{.Name}}' 2>/dev/null |
        sed '/^[[:space:]]*$/d' |
        awk '{print $1"|0|0B"}'
    )
  fi

  local state_dir history_file
  state_dir="$(_state_dir)"
  history_file="${state_dir%/}/monitor-volume-history.tsv"
  touch "$history_file" >/dev/null 2>&1 || true
  local now_epoch
  now_epoch="$(date -u +%s)"
  local growth_lookback_sec=21600
  local growth_min_age_sec=300

  local docker_root free_bytes=-1
  docker_root="$(docker info --format '{{.DockerRootDir}}' 2>/dev/null || true)"
  if [[ -n "$docker_root" && -d "$docker_root" ]]; then
    free_bytes="$(df -PB1 "$docker_root" 2>/dev/null | awk 'NR==2{print $4}')"
    free_bytes="$(_num_or_default "$free_bytes" -1)"
  fi

  # Cache previous samples before appending current snapshot.
  # Keep both latest sample and an older baseline sample to smooth growth/ETA across quick refreshes.
  declare -A prev_ts=() prev_bytes=() base_ts=() base_bytes=()
  if [[ -s "$history_file" ]]; then
    local min_ts_for_base max_ts_for_base
    min_ts_for_base=$((now_epoch - growth_lookback_sec))
    max_ts_for_base=$((now_epoch - growth_min_age_sec))
    while IFS='|' read -r ts vname b; do
      [[ -n "$ts" && -n "$vname" && -n "$b" ]] || continue
      [[ "$ts" =~ ^[0-9]+$ && "$b" =~ ^[0-9]+$ ]] || continue
      if [[ -z "${prev_ts[$vname]:-}" || "$ts" -gt "${prev_ts[$vname]}" ]]; then
        prev_ts["$vname"]="$ts"
        prev_bytes["$vname"]="$b"
      fi
      if ((ts >= min_ts_for_base && ts <= max_ts_for_base)); then
        if [[ -z "${base_ts[$vname]:-}" || "$ts" -lt "${base_ts[$vname]}" ]]; then
          base_ts["$vname"]="$ts"
          base_bytes["$vname"]="$b"
        fi
      fi
    done <"$history_file"
  fi

  local -a rows=()
  local row vname links size_h size_b svc delta dt growth_bph eta_h pressure level note
  for row in "${volume_rows[@]}"; do
    IFS='|' read -r vname links size_h <<<"$row"
    [[ -n "$vname" ]] || continue
    if [[ "$project" != "unknown" && -n "$project" ]]; then
      if [[ -z "${vol_present[$vname]:-}" ]]; then
        continue
      fi
    fi

    size_b="$(_to_bytes "$size_h")"
    size_b="$(_num_or_default "$size_b" 0)"
    svc="${vol_service[$vname]:--}"
    delta=0
    growth_bph=0
    eta_h=-1
    pressure=-1
    level="pass"
    note="ok"

    if [[ -n "${base_ts[$vname]:-}" && -n "${base_bytes[$vname]:-}" ]]; then
      dt=$((now_epoch - base_ts["$vname"]))
      if ((dt > 0)); then
        delta=$((size_b - base_bytes["$vname"]))
        growth_bph=$((delta * 3600 / dt))
      fi
    elif [[ -n "${prev_ts[$vname]:-}" && -n "${prev_bytes[$vname]:-}" ]]; then
      dt=$((now_epoch - prev_ts["$vname"]))
      if ((dt > 0)); then
        delta=$((size_b - prev_bytes["$vname"]))
        growth_bph=$((delta * 3600 / dt))
      fi
    fi

    if ((growth_bph > 0 && free_bytes > 0)); then
      eta_h=$((free_bytes / growth_bph))
      if ((eta_h <= 6)); then
        level="fail"
        note="growth_critical"
      elif ((eta_h <= 24)); then
        level="warn"
        note="growth_fast"
      fi
    fi

    if ((free_bytes > 0)); then
      pressure=$((size_b * 100 / (size_b + free_bytes)))
      if ((pressure >= 95)); then
        level="fail"
        note="capacity_critical"
      elif ((pressure >= 85 && level != "fail")); then
        level="warn"
        note="capacity_high"
      fi
    fi

    rows+=("$vname|$svc|$links|$size_h|$size_b|$delta|$growth_bph|$eta_h|$pressure|-1|-1|-1|-1|$level|$note")
    printf '%s|%s|%s\n' "$now_epoch" "$vname" "$size_b" >>"$history_file" 2>/dev/null || true
  done

  if [[ -s "$history_file" ]]; then
    tail -n 50000 "$history_file" >"${history_file}.tmp" 2>/dev/null || true
    if [[ -s "${history_file}.tmp" ]]; then
      mv -f "${history_file}.tmp" "$history_file"
    else
      rm -f "${history_file}.tmp" >/dev/null 2>&1 || true
    fi
  fi

  # Sort by size desc and keep up to the effective row limit.
  local rows_count effective_top_n effective_inode_top_n
  rows_count="${#rows[@]}"
  effective_top_n="$top_n"
  ((effective_top_n > rows_count)) && effective_top_n="$rows_count"
  effective_inode_top_n="$inode_top_n"
  ((effective_inode_top_n > effective_top_n)) && effective_inode_top_n="$effective_top_n"

  local -a sorted=()
  if ((${#rows[@]})); then
    mapfile -t sorted < <(printf '%s\n' "${rows[@]}" | sort -t'|' -k5,5nr | head -n "$effective_top_n")
  fi

  # Optional inode scan for biggest volumes.
  local helper_image helper_shell helper_rt
  helper_rt="$(_pick_probe_runtime)"
  IFS='|' read -r helper_image helper_shell <<<"$helper_rt"
  if [[ "$effective_inode_top_n" -gt 0 && ${#sorted[@]} -gt 0 ]]; then
    local -a inode_targets=()
    mapfile -t inode_targets < <(printf '%s\n' "${sorted[@]}" | head -n "$effective_inode_top_n")
    declare -A inode_line=()
    local t out l1 l2 l3 itotal iused ipct fcount btotal bused bavail bpct probe_ok probe_target probe_container probe_path probe_shell probe_mp probe_src
    for t in "${inode_targets[@]}"; do
      IFS='|' read -r vname _ _ _ _ _ _ _ _ _ _ _ _ _ _ <<<"$t"
      [[ -n "$vname" ]] || continue
      probe_ok=0
      itotal=-1
      iused=-1
      ipct=-1
      fcount=-1
      btotal=-1
      bused=-1
      bavail=-1
      bpct=-1
      probe_src="none"

      if [[ -n "${vol_probe_targets[$vname]:-}" ]]; then
        while IFS= read -r probe_target; do
          [[ -n "$probe_target" ]] || continue
          IFS='|' read -r probe_container probe_path <<<"$probe_target"
          if [[ -n "$probe_container" && -n "$probe_path" ]]; then
            for probe_shell in bash sh; do
              out="$(
                docker exec --user 0 -e AP_MONITOR_PATH="$probe_path" "$probe_container" "$probe_shell" -c '
                  di="$(df -Pi "$AP_MONITOR_PATH" 2>/dev/null | { IFS= read -r _h; IFS= read -r _d || true; printf "%s\n" "${_d:-}"; })"
                  db="$(df -PB1 "$AP_MONITOR_PATH" 2>/dev/null | { IFS= read -r _h; IFS= read -r _d || true; printf "%s\n" "${_d:-}"; })"
                  c="$(find "$AP_MONITOR_PATH" -xdev -type f 2>/dev/null | wc -l)"
                  echo "$di"
                  echo "$db"
                  echo "$c"
                ' 2>/dev/null || true
              )"
              l1="$(printf '%s\n' "$out" | sed -n '1p')"
              l2="$(printf '%s\n' "$out" | sed -n '2p')"
              l3="$(printf '%s\n' "$out" | sed -n '3p')"
              itotal="$(printf '%s\n' "$l1" | awk '{print $2}')"
              iused="$(printf '%s\n' "$l1" | awk '{print $3}')"
              ipct="$(printf '%s\n' "$l1" | awk '{print $5}')"
              btotal="$(printf '%s\n' "$l2" | awk '{print $2}')"
              bused="$(printf '%s\n' "$l2" | awk '{print $3}')"
              bavail="$(printf '%s\n' "$l2" | awk '{print $4}')"
              bpct="$(printf '%s\n' "$l2" | awk '{print $5}')"
              ipct="${ipct%\%}"
              bpct="${bpct%\%}"
              itotal="$(_num_or_default "$itotal" -1)"
              iused="$(_num_or_default "$iused" -1)"
              ipct="$(_num_or_default "$ipct" -1)"
              btotal="$(_num_or_default "$btotal" -1)"
              bused="$(_num_or_default "$bused" -1)"
              bavail="$(_num_or_default "$bavail" -1)"
              bpct="$(_num_or_default "$bpct" -1)"
              fcount="$(_num_or_default "$l3" -1)"
              if ((itotal >= 0 || btotal >= 0 || fcount >= 0)); then
                probe_ok=1
                probe_src="exec:${probe_container}:${probe_path}"
                break
              fi
            done
            if ((probe_ok == 1)); then
              break
            fi
          fi
        done <<<"${vol_probe_targets[$vname]}"
      fi

      if ((probe_ok == 0)) && [[ -n "$helper_image" && -n "$helper_shell" ]]; then
        out="$(
          docker run --rm --user 0 --entrypoint "$helper_shell" -v "${vname}:/v:ro" "$helper_image" -c '
            di="$(df -Pi /v 2>/dev/null | { IFS= read -r _h; IFS= read -r _d || true; printf "%s\n" "${_d:-}"; })"
            db="$(df -PB1 /v 2>/dev/null | { IFS= read -r _h; IFS= read -r _d || true; printf "%s\n" "${_d:-}"; })"
            c="$(find /v -xdev -type f 2>/dev/null | wc -l)"
            echo "$di"
            echo "$db"
            echo "$c"
          ' 2>/dev/null || true
        )"
        l1="$(printf '%s\n' "$out" | sed -n '1p')"
        l2="$(printf '%s\n' "$out" | sed -n '2p')"
        l3="$(printf '%s\n' "$out" | sed -n '3p')"
        itotal="$(printf '%s\n' "$l1" | awk '{print $2}')"
        iused="$(printf '%s\n' "$l1" | awk '{print $3}')"
        ipct="$(printf '%s\n' "$l1" | awk '{print $5}')"
        btotal="$(printf '%s\n' "$l2" | awk '{print $2}')"
        bused="$(printf '%s\n' "$l2" | awk '{print $3}')"
        bavail="$(printf '%s\n' "$l2" | awk '{print $4}')"
        bpct="$(printf '%s\n' "$l2" | awk '{print $5}')"
        ipct="${ipct%\%}"
        bpct="${bpct%\%}"
        itotal="$(_num_or_default "$itotal" -1)"
        iused="$(_num_or_default "$iused" -1)"
        ipct="$(_num_or_default "$ipct" -1)"
        btotal="$(_num_or_default "$btotal" -1)"
        bused="$(_num_or_default "$bused" -1)"
        bavail="$(_num_or_default "$bavail" -1)"
        bpct="$(_num_or_default "$bpct" -1)"
        fcount="$(_num_or_default "$l3" -1)"
        if ((itotal >= 0 || btotal >= 0 || fcount >= 0)); then
          probe_ok=1
          probe_src="helper-volume"
        fi
      fi

      if ((probe_ok == 0)); then
        probe_mp="$(docker volume inspect -f '{{ .Mountpoint }}' "$vname" 2>/dev/null | sed -n '1p')"
        if [[ -n "$probe_mp" ]]; then
          if [[ -n "$helper_image" && -n "$helper_shell" ]]; then
            out="$(
              docker run --rm --user 0 --entrypoint "$helper_shell" -v "${probe_mp}:/v:ro" "$helper_image" -c '
                di="$(df -Pi /v 2>/dev/null | { IFS= read -r _h; IFS= read -r _d || true; printf "%s\n" "${_d:-}"; })"
                db="$(df -PB1 /v 2>/dev/null | { IFS= read -r _h; IFS= read -r _d || true; printf "%s\n" "${_d:-}"; })"
                c="$(find /v -xdev -type f 2>/dev/null | wc -l)"
                echo "$di"
                echo "$db"
                echo "$c"
              ' 2>/dev/null || true
            )"
            l1="$(printf '%s\n' "$out" | sed -n '1p')"
            l2="$(printf '%s\n' "$out" | sed -n '2p')"
            l3="$(printf '%s\n' "$out" | sed -n '3p')"
            itotal="$(printf '%s\n' "$l1" | awk '{print $2}')"
            iused="$(printf '%s\n' "$l1" | awk '{print $3}')"
            ipct="$(printf '%s\n' "$l1" | awk '{print $5}')"
            btotal="$(printf '%s\n' "$l2" | awk '{print $2}')"
            bused="$(printf '%s\n' "$l2" | awk '{print $3}')"
            bavail="$(printf '%s\n' "$l2" | awk '{print $4}')"
            bpct="$(printf '%s\n' "$l2" | awk '{print $5}')"
            ipct="${ipct%\%}"
            bpct="${bpct%\%}"
            itotal="$(_num_or_default "$itotal" -1)"
            iused="$(_num_or_default "$iused" -1)"
            ipct="$(_num_or_default "$ipct" -1)"
            btotal="$(_num_or_default "$btotal" -1)"
            bused="$(_num_or_default "$bused" -1)"
            bavail="$(_num_or_default "$bavail" -1)"
            bpct="$(_num_or_default "$bpct" -1)"
            fcount="$(_num_or_default "$l3" -1)"
            if ((itotal >= 0 || btotal >= 0 || fcount >= 0)); then
              probe_ok=1
              probe_src="helper-bind-mountpoint"
            fi
          fi

          if ((probe_ok == 0)) && [[ -d "$probe_mp" ]]; then
            l1="$(df -Pi "$probe_mp" 2>/dev/null | sed -n '2p')"
            l2="$(df -PB1 "$probe_mp" 2>/dev/null | sed -n '2p')"
            l3="$(find "$probe_mp" -xdev -type f 2>/dev/null | wc -l)"
            itotal="$(printf '%s\n' "$l1" | awk '{print $2}')"
            iused="$(printf '%s\n' "$l1" | awk '{print $3}')"
            ipct="$(printf '%s\n' "$l1" | awk '{print $5}')"
            btotal="$(printf '%s\n' "$l2" | awk '{print $2}')"
            bused="$(printf '%s\n' "$l2" | awk '{print $3}')"
            bavail="$(printf '%s\n' "$l2" | awk '{print $4}')"
            bpct="$(printf '%s\n' "$l2" | awk '{print $5}')"
            ipct="${ipct%\%}"
            bpct="${bpct%\%}"
            itotal="$(_num_or_default "$itotal" -1)"
            iused="$(_num_or_default "$iused" -1)"
            ipct="$(_num_or_default "$ipct" -1)"
            btotal="$(_num_or_default "$btotal" -1)"
            bused="$(_num_or_default "$bused" -1)"
            bavail="$(_num_or_default "$bavail" -1)"
            bpct="$(_num_or_default "$bpct" -1)"
            fcount="$(_num_or_default "$l3" -1)"
            if ((itotal >= 0 || btotal >= 0 || fcount >= 0)); then
              probe_ok=1
              probe_src="local-mountpoint"
            fi
          fi
        fi
      fi

      if ((probe_ok == 1)); then
        inode_line["$vname"]="$itotal|$iused|$ipct|$fcount|$btotal|$bused|$bavail|$bpct|$probe_src"
      else
        inode_line["$vname"]="-1|-1|-1|-1|-1|-1|-1|-1|none"
      fi
    done

    local -a patched=()
    local _btotal _bused _bavail _bpct _psrc
    for t in "${sorted[@]}"; do
      IFS='|' read -r vname svc links size_h size_b delta growth_bph eta_h pressure _itotal _iused _ipct _fcount level note <<<"$t"
      if [[ -n "${inode_line[$vname]:-}" ]]; then
        IFS='|' read -r _itotal _iused _ipct _fcount _btotal _bused _bavail _bpct _psrc <<<"${inode_line[$vname]}"
        if [[ "$_bpct" =~ ^[0-9]+$ ]] && (( _bpct >= 0 )); then
          pressure="$_bpct"
        fi
        if [[ "$_bavail" =~ ^[0-9]+$ ]] && (( growth_bph > 0 && _bavail > 0 )); then
          eta_h=$(( _bavail / growth_bph ))
          if (( eta_h <= 6 )); then
            level="fail"
            note="growth_critical"
          elif (( eta_h <= 24 )) && [[ "$level" == "pass" ]]; then
            level="warn"
            note="growth_fast"
          fi
        fi
        if [[ "$pressure" =~ ^[0-9]+$ ]] && (( pressure >= 95 )); then
          level="fail"
          note="capacity_critical"
        elif [[ "$pressure" =~ ^[0-9]+$ ]] && (( pressure >= 85 )) && [[ "$level" != "fail" ]]; then
          level="warn"
          note="capacity_high"
        fi
        if (( _ipct >= 95 )); then
          level="fail"
          note="inode_critical"
        elif (( _ipct >= 85 )) && [[ "$level" != "fail" ]]; then
          level="warn"
          note="inode_high"
        fi
      fi
      patched+=("$vname|$svc|$links|$size_h|$size_b|$delta|$growth_bph|$eta_h|$pressure|${_itotal:--1}|${_iused:--1}|${_ipct:--1}|${_fcount:--1}|$level|$note|${_psrc:-none}")
    done
    sorted=("${patched[@]}")
  fi

  local total=0 pass=0 warn=0 fail=0 inode_scanned=0
  local r
  for r in "${sorted[@]}"; do
    ((++total))
    IFS='|' read -r _ _ _ _ _ _ _ _ _ _ _ ipct _ lvl _ _ <<<"$r"
    if [[ "$ipct" =~ ^[0-9]+$ && "$ipct" -ge 0 ]]; then
      ((++inode_scanned))
    fi
    case "$lvl" in
      pass) ((++pass)) ;;
      warn) ((++warn)) ;;
      *) ((++fail)) ;;
    esac
  done

  if ((json == 0)); then
    printf 'Volume Monitor | project=%s volumes=%d pass=%d warn=%d fail=%d inode_scanned=%d\n' \
      "$project" "$total" "$pass" "$warn" "$fail" "$inode_scanned"
    return 0
  fi

  printf '{'
  printf '"ok":true,'
  printf '"generated_at":"%s",' "$(_json_escape "$(date -u +%Y-%m-%dT%H:%M:%SZ)")"
  printf '"project":"%s",' "$(_json_escape "$project")"
  printf '"filters":{"top":%d,"inode_top":%d},' "$effective_top_n" "$effective_inode_top_n"
  printf '"summary":{"volumes":%d,"pass":%d,"warn":%d,"fail":%d,"inode_scanned":%d,"docker_root_free_bytes":%s},' \
    "$total" "$pass" "$warn" "$fail" "$inode_scanned" "$(_num_or_default "$free_bytes" -1)"
  printf '"items":['
  local f=1 v itotal iused ipct fcount eta_display pressure_display inode_display files_display state_label
  for r in "${sorted[@]}"; do
    IFS='|' read -r vname svc links size_h size_b delta growth_bph eta_h pressure itotal iused ipct fcount level note psrc <<<"$r"
    eta_display='-'
    pressure_display='-'
    inode_display='-'
    files_display='-'
    if [[ "$eta_h" =~ ^-?[0-9]+$ ]] && ((eta_h >= 0)); then
      eta_display="$eta_h"
    fi
    if [[ "$pressure" =~ ^-?[0-9]+$ ]] && ((pressure >= 0)); then
      pressure_display="$pressure"
    fi
    if [[ "$ipct" =~ ^-?[0-9]+$ ]] && ((ipct >= 0)); then
      inode_display="$ipct"
    fi
    if [[ "$fcount" =~ ^-?[0-9]+$ ]] && ((fcount >= 0)); then
      files_display="$fcount"
    fi
    state_label="$(_state_label "$note" "$level")"
    ((f)) || printf ','
    f=0
    printf '{'
    printf '"volume":"%s",' "$(_json_escape "$vname")"
    printf '"services":"%s",' "$(_json_escape "$svc")"
    printf '"services_list":%s,' "$(_emit_json_csv_array "$svc")"
    printf '"links":%s,' "$(_num_or_default "$links" 0)"
    printf '"size":"%s",' "$(_json_escape "$size_h")"
    printf '"size_bytes":%s,' "$(_num_or_default "$size_b" 0)"
    printf '"delta_bytes":%s,' "$(_num_or_default "$delta" 0)"
    printf '"delta_human":"%s",' "$(_json_escape "$(_bytes_human "$(_num_or_default "$delta" 0)")")"
    printf '"growth_bph":%s,' "$(_num_or_default "$growth_bph" 0)"
    printf '"growth_human_per_hour":"%s",' "$(_json_escape "$(_bytes_human "$(_num_or_default "$growth_bph" 0)")")"
    printf '"eta_hours":%s,' "$(_num_or_default "$eta_h" -1)"
    printf '"eta_display":"%s",' "$(_json_escape "$eta_display")"
    printf '"pressure_pct":%s,' "$(_num_or_default "$pressure" -1)"
    printf '"pressure_display":"%s",' "$(_json_escape "$pressure_display")"
    printf '"inode_total":%s,' "$(_num_or_default "$itotal" -1)"
    printf '"inode_used":%s,' "$(_num_or_default "$iused" -1)"
    printf '"inode_pct":%s,' "$(_num_or_default "$ipct" -1)"
    printf '"inode_display":"%s",' "$(_json_escape "$inode_display")"
    printf '"file_count":%s,' "$(_num_or_default "$fcount" -1)"
    printf '"files_display":"%s",' "$(_json_escape "$files_display")"
    printf '"level":"%s",' "$(_json_escape "$level")"
    printf '"note":"%s",' "$(_json_escape "$note")"
    printf '"state_label":"%s",' "$(_json_escape "$state_label")"
    printf '"probe_source":"%s"' "$(_json_escape "${psrc:-none}")"
    printf '}'
  done
  printf ']'
  printf '}\n'
}

main "$@"
