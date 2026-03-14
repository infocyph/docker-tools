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

usage() {
  cat <<'EOF'
Usage:
  monitor-volumes [--json] [--top <n>] [--inode-top <n>]

Examples:
  monitor-volumes --json
  monitor-volumes --json --top 20 --inode-top 8
EOF
}

main() {
  local json=0 top_n=20 inode_top_n=8
  while [[ "${1:-}" ]]; do
    case "$1" in
      --json) json=1; shift ;;
      --top) top_n="${2:-20}"; shift 2 ;;
      --inode-top) inode_top_n="${2:-8}"; shift 2 ;;
      -h|--help) usage; return 0 ;;
      *) echo "Unknown arg: $1" >&2; usage; return 1 ;;
    esac
  done

  [[ "$top_n" =~ ^[0-9]+$ ]] || top_n=20
  [[ "$inode_top_n" =~ ^[0-9]+$ ]] || inode_top_n=8
  ((top_n < 1)) && top_n=1
  ((top_n > 200)) && top_n=200
  ((inode_top_n < 0)) && inode_top_n=0
  ((inode_top_n > 30)) && inode_top_n=30

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

  declare -A vol_service=() vol_present=()
  local cid service mounts m
  for cid in "${cids[@]}"; do
    [[ -n "$cid" ]] || continue
    service="$(docker inspect -f '{{index .Config.Labels "com.docker.compose.service"}}' "$cid" 2>/dev/null || true)"
    [[ -n "$service" ]] || service="-"
    mounts="$(docker inspect -f '{{range .Mounts}}{{if eq .Type "volume"}}{{.Name}}{{println}}{{end}}{{end}}' "$cid" 2>/dev/null || true)"
    while IFS= read -r m; do
      [[ -n "$m" ]] || continue
      vol_present["$m"]=1
      if [[ -z "${vol_service[$m]:-}" ]]; then
        vol_service["$m"]="$service"
      elif [[ ",${vol_service[$m]}," != *",$service,"* ]]; then
        vol_service["$m"]="${vol_service[$m]},$service"
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

  local history_file="/etc/share/state/monitor-volume-history.tsv"
  mkdir -p /etc/share/state >/dev/null 2>&1 || true
  touch "$history_file" >/dev/null 2>&1 || true
  local now_epoch
  now_epoch="$(date -u +%s)"

  local docker_root free_bytes=-1
  docker_root="$(docker info --format '{{.DockerRootDir}}' 2>/dev/null || true)"
  if [[ -n "$docker_root" && -d "$docker_root" ]]; then
    free_bytes="$(df -PB1 "$docker_root" 2>/dev/null | awk 'NR==2{print $4}')"
    free_bytes="$(_num_or_default "$free_bytes" -1)"
  fi

  # Cache previous samples before appending current snapshot.
  declare -A prev_ts=() prev_bytes=()
  if [[ -s "$history_file" ]]; then
    while IFS='|' read -r ts vname b; do
      [[ -n "$ts" && -n "$vname" && -n "$b" ]] || continue
      [[ "$ts" =~ ^[0-9]+$ && "$b" =~ ^[0-9]+$ ]] || continue
      prev_ts["$vname"]="$ts"
      prev_bytes["$vname"]="$b"
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
    pressure=0
    level="pass"
    note="ok"

    if [[ -n "${prev_ts[$vname]:-}" && -n "${prev_bytes[$vname]:-}" ]]; then
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
    printf '%s|%s|%s\n' "$now_epoch" "$vname" "$size_b" >>"$history_file"
  done

  if [[ -s "$history_file" ]]; then
    tail -n 50000 "$history_file" >"${history_file}.tmp" 2>/dev/null || true
    if [[ -s "${history_file}.tmp" ]]; then
      mv -f "${history_file}.tmp" "$history_file"
    else
      rm -f "${history_file}.tmp" >/dev/null 2>&1 || true
    fi
  fi

  # Sort by size desc and keep top N.
  local -a sorted=()
  if ((${#rows[@]})); then
    mapfile -t sorted < <(printf '%s\n' "${rows[@]}" | sort -t'|' -k5,5nr | head -n "$top_n")
  fi

  # Optional inode scan for biggest volumes.
  local helper_image
  helper_image="$(_helper_image)"
  if [[ -n "$helper_image" && "$inode_top_n" -gt 0 && ${#sorted[@]} -gt 0 ]]; then
    local -a inode_targets=()
    mapfile -t inode_targets < <(printf '%s\n' "${sorted[@]}" | head -n "$inode_top_n")
    declare -A inode_line=()
    local t out l1 l2 itotal iused ipct fcount
    for t in "${inode_targets[@]}"; do
      IFS='|' read -r vname _ _ _ _ _ _ _ _ _ _ _ _ _ _ <<<"$t"
      [[ -n "$vname" ]] || continue
      out="$(
        docker run --rm -v "${vname}:/v:ro" "$helper_image" sh -lc '
          d="$(df -Pi /v 2>/dev/null | awk "NR==2{print \$2\"|\"\$3\"|\"\$5}")"
          [ -n "$d" ] || d="-1|-1|-"
          c="$(find /v -xdev -type f 2>/dev/null | wc -l | awk "{print \$1}")"
          echo "$d"
          echo "$c"
        ' 2>/dev/null || true
      )"
      l1="$(printf '%s\n' "$out" | sed -n '1p')"
      l2="$(printf '%s\n' "$out" | sed -n '2p')"
      IFS='|' read -r itotal iused ipct <<<"$l1"
      ipct="${ipct%\%}"
      itotal="$(_num_or_default "$itotal" -1)"
      iused="$(_num_or_default "$iused" -1)"
      ipct="$(_num_or_default "$ipct" -1)"
      fcount="$(_num_or_default "$l2" -1)"
      inode_line["$vname"]="$itotal|$iused|$ipct|$fcount"
    done

    local -a patched=()
    for t in "${sorted[@]}"; do
      IFS='|' read -r vname svc links size_h size_b delta growth_bph eta_h pressure _itotal _iused _ipct _fcount level note <<<"$t"
      if [[ -n "${inode_line[$vname]:-}" ]]; then
        IFS='|' read -r _itotal _iused _ipct _fcount <<<"${inode_line[$vname]}"
        if (( _ipct >= 95 )); then
          level="fail"
          note="inode_critical"
        elif (( _ipct >= 85 )) && [[ "$level" != "fail" ]]; then
          level="warn"
          note="inode_high"
        fi
      fi
      patched+=("$vname|$svc|$links|$size_h|$size_b|$delta|$growth_bph|$eta_h|$pressure|${_itotal:--1}|${_iused:--1}|${_ipct:--1}|${_fcount:--1}|$level|$note")
    done
    sorted=("${patched[@]}")
  fi

  local total=0 pass=0 warn=0 fail=0 inode_scanned=0
  local r
  for r in "${sorted[@]}"; do
    ((++total))
    IFS='|' read -r _ _ _ _ _ _ _ _ _ _ _ ipct _ _ lvl _ <<<"$r"
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
  printf '"filters":{"top":%d,"inode_top":%d},' "$top_n" "$inode_top_n"
  printf '"summary":{"volumes":%d,"pass":%d,"warn":%d,"fail":%d,"inode_scanned":%d,"docker_root_free_bytes":%s},' \
    "$total" "$pass" "$warn" "$fail" "$inode_scanned" "$(_num_or_default "$free_bytes" -1)"
  printf '"items":['
  local f=1 v itotal iused ipct fcount
  for r in "${sorted[@]}"; do
    IFS='|' read -r vname svc links size_h size_b delta growth_bph eta_h pressure itotal iused ipct fcount level note <<<"$r"
    ((f)) || printf ','
    f=0
    printf '{'
    printf '"volume":"%s",' "$(_json_escape "$vname")"
    printf '"services":"%s",' "$(_json_escape "$svc")"
    printf '"links":%s,' "$(_num_or_default "$links" 0)"
    printf '"size":"%s",' "$(_json_escape "$size_h")"
    printf '"size_bytes":%s,' "$(_num_or_default "$size_b" 0)"
    printf '"delta_bytes":%s,' "$(_num_or_default "$delta" 0)"
    printf '"delta_human":"%s",' "$(_json_escape "$(_bytes_human "$(_num_or_default "$delta" 0)")")"
    printf '"growth_bph":%s,' "$(_num_or_default "$growth_bph" 0)"
    printf '"growth_human_per_hour":"%s",' "$(_json_escape "$(_bytes_human "$(_num_or_default "$growth_bph" 0)")")"
    printf '"eta_hours":%s,' "$(_num_or_default "$eta_h" -1)"
    printf '"pressure_pct":%s,' "$(_num_or_default "$pressure" -1)"
    printf '"inode_total":%s,' "$(_num_or_default "$itotal" -1)"
    printf '"inode_used":%s,' "$(_num_or_default "$iused" -1)"
    printf '"inode_pct":%s,' "$(_num_or_default "$ipct" -1)"
    printf '"file_count":%s,' "$(_num_or_default "$fcount" -1)"
    printf '"level":"%s",' "$(_json_escape "$level")"
    printf '"note":"%s"' "$(_json_escape "$note")"
    printf '}'
  done
  printf ']'
  printf '}\n'
}

main "$@"
