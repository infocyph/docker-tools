#!/usr/bin/env bash
set -euo pipefail

BACKEND="${ENV_STORE_BACKEND:-json}"
STORE_FILE="${ENV_STORE_JSON:-/etc/share/state/env-store.json}"
STORE_DB="${ENV_STORE_DB:-/etc/share/state/env-store.db}"
SQLITE_BIN="${ENV_STORE_SQLITE_BIN:-sqlite3}"

die() {
  printf "Error: %s\n" "$*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"
}

json_compact() {
  local in="${1-}" out=""
  out="$(printf '%s' "$in" | jq -c . 2>/dev/null || true)"
  [[ -n "$out" ]] || return 1
  printf '%s' "$out"
}

json_string_value() {
  jq -cn --arg v "${1-}" '$v'
}

storage_to_json() {
  local raw="${1-}" out=""
  out="$(json_compact "$raw" || true)"
  if [[ -n "$out" ]]; then
    printf '%s' "$out"
    return 0
  fi
  json_string_value "$raw"
}

print_value_human_from_json() {
  local j="${1-}"
  if printf '%s' "$j" | jq -e 'type=="string"' >/dev/null 2>&1; then
    printf '%s\n' "$(printf '%s' "$j" | jq -r '.')"
  else
    printf '%s\n' "$(printf '%s' "$j" | jq -c '.')"
  fi
}

now_iso() {
  date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || printf ''
}

ensure_store() {
  if [[ "$BACKEND" == "json" ]]; then
    ensure_store_json
  else
    ensure_store_sqlite
  fi
}

ensure_store_json() {
  local dir
  dir="$(dirname "$STORE_FILE")"
  mkdir -p "$dir"

  if [[ ! -f "$STORE_FILE" || ! -s "$STORE_FILE" ]]; then
    jq -cn --arg ts "$(now_iso)" '{version:1,updated_at:$ts,data:{}}' >"$STORE_FILE"
    return 0
  fi

  if ! jq -e 'type=="object" and (.data|type=="object")' "$STORE_FILE" >/dev/null 2>&1; then
    die "Invalid store format: $STORE_FILE"
  fi
}

ensure_store_sqlite() {
  local dir
  dir="$(dirname "$STORE_DB")"
  mkdir -p "$dir"
  "$SQLITE_BIN" "$STORE_DB" "
    PRAGMA journal_mode=WAL;
    CREATE TABLE IF NOT EXISTS kv (
      k TEXT PRIMARY KEY,
      v TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );
    CREATE TABLE IF NOT EXISTS meta (
      k TEXT PRIMARY KEY,
      v TEXT NOT NULL
    );
    INSERT OR IGNORE INTO meta(k,v) VALUES('version','1');
    INSERT OR IGNORE INTO meta(k,v) VALUES('updated_at','');
  " >/dev/null
}

sql_quote() {
  local s="${1-}"
  s="${s//\'/\'\'}"
  printf "'%s'" "$s"
}

sqlite_meta_get() {
  local key="$1"
  "$SQLITE_BIN" -noheader "$STORE_DB" "SELECT v FROM meta WHERE k=$(sql_quote "$key") LIMIT 1;" 2>/dev/null || true
}

sqlite_touch_updated() {
  local ts
  ts="$(now_iso)"
  "$SQLITE_BIN" "$STORE_DB" "INSERT OR REPLACE INTO meta(k,v) VALUES('updated_at',$(sql_quote "$ts"));" >/dev/null
}

key_ok() {
  local key="${1:-}"
  [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]
}

write_with_filter() {
  (( $# >= 1 )) || die "Internal error: missing jq filter"
  local filter="${!#}"
  local -a jq_args=()
  if (( $# > 1 )); then
    jq_args=("${@:1:$#-1}")
  fi
  local tmp
  tmp="$(mktemp)"
  jq "${jq_args[@]}" "$filter" "$STORE_FILE" >"$tmp"
  mv "$tmp" "$STORE_FILE"
}

cmd_get() {
  local key="${1:-}" def_set=0 def=""
  shift || true
  [[ -n "$key" ]] || die "get <KEY> [--default VALUE]"
  key_ok "$key" || die "Invalid key: $key"

  while [[ "${1:-}" ]]; do
    case "$1" in
      --default)
        shift || true
        def="${1:-}"
        def_set=1
        shift || true
        ;;
      *)
        die "Unknown flag for get: $1"
        ;;
    esac
  done

  if [[ "$BACKEND" == "json" ]]; then
    if jq -e --arg k "$key" '.data | has($k)' "$STORE_FILE" >/dev/null 2>&1; then
      local vj
      vj="$(jq -c --arg k "$key" '.data[$k]' "$STORE_FILE")"
      print_value_human_from_json "$vj"
      return 0
    fi
  else
    local out vj
    out="$("$SQLITE_BIN" -noheader "$STORE_DB" "SELECT v FROM kv WHERE k=$(sql_quote "$key") LIMIT 1;" 2>/dev/null || true)"
    if [[ -n "$out" ]] || "$SQLITE_BIN" -noheader "$STORE_DB" "SELECT 1 FROM kv WHERE k=$(sql_quote "$key") LIMIT 1;" | grep -qx '1'; then
      vj="$(storage_to_json "$out")"
      print_value_human_from_json "$vj"
      return 0
    fi
  fi

  if ((def_set)); then
    printf "%s\n" "$def"
  fi
}

cmd_set() {
  local key="${1:-}" value="${2-}"
  [[ -n "$key" ]] || die "set <KEY> <VALUE>"
  key_ok "$key" || die "Invalid key: $key"
  shift || true
  shift || true
  [[ -z "${1:-}" ]] || die "set accepts exactly 2 arguments"

  local vjson
  vjson="$(json_string_value "$value")"

  if [[ "$BACKEND" == "json" ]]; then
    write_with_filter \
      --arg k "$key" \
      --argjson v "$vjson" \
      --arg ts "$(now_iso)" \
      '.data[$k]=$v | .updated_at=$ts'
  else
    local ts
    ts="$(now_iso)"
    "$SQLITE_BIN" "$STORE_DB" "
      INSERT OR REPLACE INTO kv(k,v,updated_at)
      VALUES($(sql_quote "$key"),$(sql_quote "$vjson"),$(sql_quote "$ts"));
      INSERT OR REPLACE INTO meta(k,v)
      VALUES('updated_at',$(sql_quote "$ts"));
    " >/dev/null
  fi
}

cmd_get_json() {
  local key="${1:-}" def_set=0 def_json='null'
  shift || true
  [[ -n "$key" ]] || die "get-json <KEY> [--default-json JSON]"
  key_ok "$key" || die "Invalid key: $key"

  while [[ "${1:-}" ]]; do
    case "$1" in
      --default-json)
        shift || true
        [[ -n "${1:-}" ]] || die "Missing value for --default-json"
        def_json="$(json_compact "$1" || true)"
        [[ -n "$def_json" ]] || die "Invalid JSON for --default-json"
        def_set=1
        shift || true
        ;;
      *)
        die "Unknown flag for get-json: $1"
        ;;
    esac
  done

  if [[ "$BACKEND" == "json" ]]; then
    if jq -e --arg k "$key" '.data | has($k)' "$STORE_FILE" >/dev/null 2>&1; then
      jq -c --arg k "$key" '.data[$k]' "$STORE_FILE"
      return 0
    fi
  else
    local out
    out="$("$SQLITE_BIN" -noheader "$STORE_DB" "SELECT v FROM kv WHERE k=$(sql_quote "$key") LIMIT 1;" 2>/dev/null || true)"
    if [[ -n "$out" ]] || "$SQLITE_BIN" -noheader "$STORE_DB" "SELECT 1 FROM kv WHERE k=$(sql_quote "$key") LIMIT 1;" | grep -qx '1'; then
      storage_to_json "$out"
      printf '\n'
      return 0
    fi
  fi

  if ((def_set)); then
    printf '%s\n' "$def_json"
    return 0
  fi
  return 1
}

cmd_set_json() {
  local key="${1:-}" raw="${2-}" vjson
  [[ -n "$key" ]] || die "set-json <KEY> <JSON>"
  key_ok "$key" || die "Invalid key: $key"
  shift || true
  shift || true
  [[ -z "${1:-}" ]] || die "set-json accepts exactly 2 arguments"

  vjson="$(json_compact "$raw" || true)"
  [[ -n "$vjson" ]] || die "Invalid JSON value"

  if [[ "$BACKEND" == "json" ]]; then
    write_with_filter \
      --arg k "$key" \
      --argjson v "$vjson" \
      --arg ts "$(now_iso)" \
      '.data[$k]=$v | .updated_at=$ts'
  else
    local ts
    ts="$(now_iso)"
    "$SQLITE_BIN" "$STORE_DB" "
      INSERT OR REPLACE INTO kv(k,v,updated_at)
      VALUES($(sql_quote "$key"),$(sql_quote "$vjson"),$(sql_quote "$ts"));
      INSERT OR REPLACE INTO meta(k,v)
      VALUES('updated_at',$(sql_quote "$ts"));
    " >/dev/null
  fi
}

cmd_unset() {
  local key="${1:-}"
  [[ -n "$key" ]] || die "unset <KEY>"
  key_ok "$key" || die "Invalid key: $key"

  if [[ "$BACKEND" == "json" ]]; then
    write_with_filter \
      --arg k "$key" \
      --arg ts "$(now_iso)" \
      'del(.data[$k]) | .updated_at=$ts'
  else
    "$SQLITE_BIN" "$STORE_DB" "DELETE FROM kv WHERE k=$(sql_quote "$key");" >/dev/null
    sqlite_touch_updated
  fi
}

cmd_has() {
  local key="${1:-}"
  [[ -n "$key" ]] || die "has <KEY>"
  key_ok "$key" || die "Invalid key: $key"
  if [[ "$BACKEND" == "json" ]]; then
    jq -e --arg k "$key" '.data | has($k)' "$STORE_FILE" >/dev/null
  else
    "$SQLITE_BIN" -noheader "$STORE_DB" "SELECT 1 FROM kv WHERE k=$(sql_quote "$key") LIMIT 1;" | grep -qx '1'
  fi
}

cmd_list() {
  if [[ "$BACKEND" == "json" ]]; then
    jq -r '.data | to_entries | sort_by(.key) | .[] | if (.value|type)=="string" then "\(.key)=\(.value)" else "\(.key)=\(.value|tojson)" end' "$STORE_FILE"
  else
    "$SQLITE_BIN" -noheader -separator $'\t' "$STORE_DB" "SELECT k,v FROM kv ORDER BY k;" 2>/dev/null |
      while IFS=$'\t' read -r k v; do
        [[ -n "$k" ]] || continue
        local vj
        vj="$(storage_to_json "${v:-}")"
        if printf '%s' "$vj" | jq -e 'type=="string"' >/dev/null 2>&1; then
          printf "%s=%s\n" "$k" "$(printf '%s' "$vj" | jq -r '.')"
        else
          printf "%s=%s\n" "$k" "$(printf '%s' "$vj" | jq -c '.')"
        fi
      done
  fi
}

cmd_keys() {
  if [[ "$BACKEND" == "json" ]]; then
    jq -r '.data | keys[]' "$STORE_FILE"
  else
    "$SQLITE_BIN" -noheader "$STORE_DB" "SELECT k FROM kv ORDER BY k;" 2>/dev/null
  fi
}

cmd_json() {
  if [[ "$BACKEND" == "json" ]]; then
    jq -c '.' "$STORE_FILE"
  else
    local version updated entries data
    version="$(sqlite_meta_get "version")"
    updated="$(sqlite_meta_get "updated_at")"
    [[ "$version" =~ ^[0-9]+$ ]] || version="1"
    [[ -n "$updated" ]] || updated=""

    entries="$("$SQLITE_BIN" -noheader -separator $'\t' "$STORE_DB" "SELECT k,v FROM kv ORDER BY k;" 2>/dev/null || true)"
    data='{}'
    local k v vj
    while IFS=$'\t' read -r k v; do
      [[ -n "$k" ]] || continue
      vj="$(storage_to_json "${v:-}")"
      data="$(jq -cn --argjson d "$data" --arg kk "$k" --argjson vv "$vj" '$d + {($kk):$vv}')"
    done <<<"$entries"
    jq -cn --argjson ver "$version" --arg updated "$updated" --argjson data "${data:-{}}" \
      '{version:$ver,updated_at:$updated,data:$data}'
  fi
}

cmd_reset() {
  if [[ "$BACKEND" == "json" ]]; then
    jq -cn --arg ts "$(now_iso)" '{version:1,updated_at:$ts,data:{}}' >"$STORE_FILE"
  else
    local ts
    ts="$(now_iso)"
    "$SQLITE_BIN" "$STORE_DB" "
      DELETE FROM kv;
      INSERT OR REPLACE INTO meta(k,v) VALUES('version','1');
      INSERT OR REPLACE INTO meta(k,v) VALUES('updated_at',$(sql_quote "$ts"));
    " >/dev/null
  fi
}

cmd_import() {
  local kv key val
  [[ "${1:-}" ]] || die "import <KEY=VALUE...>"
  for kv in "$@"; do
    [[ "$kv" == *=* ]] || die "Invalid pair: $kv"
    key="${kv%%=*}"
    val="${kv#*=}"
    key_ok "$key" || die "Invalid key: $key"
    cmd_set "$key" "$val"
  done
}

cmd_import_json() {
  local kv key raw
  [[ "${1:-}" ]] || die "import-json <KEY=JSON...>"
  for kv in "$@"; do
    [[ "$kv" == *=* ]] || die "Invalid pair: $kv"
    key="${kv%%=*}"
    raw="${kv#*=}"
    key_ok "$key" || die "Invalid key: $key"
    cmd_set_json "$key" "$raw"
  done
}

usage() {
  cat <<'EOF'
Usage:
  env-store get <KEY> [--default VALUE]
  env-store set <KEY> <VALUE>
  env-store get-json <KEY> [--default-json JSON]
  env-store set-json <KEY> <JSON>
  env-store unset <KEY>
  env-store has <KEY>
  env-store list
  env-store keys
  env-store json
  env-store import KEY=VALUE [KEY=VALUE...]
  env-store import-json KEY=JSON [KEY=JSON...]
  env-store reset

Aliases:
  read -> get
  read-json -> get-json
  write -> set
  modify -> set
  write-json -> set-json
  modify-json -> set-json
  delete -> unset

Env:
  ENV_STORE_BACKEND=json|sqlite
  ENV_STORE_JSON=/etc/share/state/env-store.json
  ENV_STORE_DB=/etc/share/state/env-store.db
  ENV_STORE_SQLITE_BIN=sqlite3
EOF
}

main() {
  need_cmd jq
  BACKEND="${BACKEND,,}"
  case "$BACKEND" in
    json|sqlite) ;;
    *) die "Invalid ENV_STORE_BACKEND: $BACKEND (expected json|sqlite)" ;;
  esac
  if [[ "$BACKEND" == "sqlite" ]]; then
    need_cmd "$SQLITE_BIN"
  fi
  local cmd="${1:-}"
  shift || true

  case "${cmd:-}" in
    -h|--help|"") usage; exit 0 ;;
  esac

  ensure_store

  case "$cmd" in
    get|read) cmd_get "$@" ;;
    get-json|read-json) cmd_get_json "$@" ;;
    set|write|modify) cmd_set "$@" ;;
    set-json|write-json|modify-json) cmd_set_json "$@" ;;
    unset|delete|rm) cmd_unset "$@" ;;
    has) cmd_has "$@" ;;
    list) cmd_list "$@" ;;
    keys) cmd_keys "$@" ;;
    json) cmd_json "$@" ;;
    import) cmd_import "$@" ;;
    import-json) cmd_import_json "$@" ;;
    reset) cmd_reset "$@" ;;
    *)
      die "Unknown command: $cmd"
      ;;
  esac
}

main "$@"
