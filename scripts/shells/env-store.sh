#!/usr/bin/env bash
set -euo pipefail

BACKEND="${ENV_STORE_BACKEND:-json}"
STORE_FILE="${ENV_STORE_JSON:-/etc/share/state/env-store.json}"
STORE_DB="${ENV_STORE_DB:-/etc/share/state/env-store.db}"
SQLITE_BIN="${ENV_STORE_SQLITE_BIN:-sqlite3}"
LOCK_TIMEOUT_MS="${ENV_STORE_LOCK_TIMEOUT_MS:-5000}"
LOCK_FILE="${STORE_FILE}.lock"
JSON_LOCK_FD=""

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"
}

json_compact() {
  local input="${1-}" out=""
  out="$(printf '%s' "$input" | jq -c . 2>/dev/null || true)"
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
  local json="${1-}"
  if printf '%s' "$json" | jq -e 'type=="string"' >/dev/null 2>&1; then
    printf '%s\n' "$(printf '%s' "$json" | jq -r '.')"
  else
    printf '%s\n' "$(printf '%s' "$json" | jq -c '.')"
  fi
}

now_iso() {
  date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || printf ''
}

json_lock_acquire() {
  [[ "$LOCK_TIMEOUT_MS" =~ ^[0-9]+$ ]] || LOCK_TIMEOUT_MS=5000
  mkdir -p "$(dirname "$STORE_FILE")"
  need_cmd flock

  exec {JSON_LOCK_FD}>"$LOCK_FILE"

  local waited=0
  while ! flock -n "$JSON_LOCK_FD"; do
    if (( waited >= LOCK_TIMEOUT_MS )); then
      exec {JSON_LOCK_FD}>&-
      JSON_LOCK_FD=""
      die "Timed out waiting for env-store lock: $LOCK_FILE"
    fi
    sleep 0.05
    ((waited += 50))
  done
}

json_lock_release() {
  [[ -n "$JSON_LOCK_FD" ]] || return 0
  flock -u "$JSON_LOCK_FD" 2>/dev/null || true
  exec {JSON_LOCK_FD}>&-
  JSON_LOCK_FD=""
}

preserve_store_metadata() {
  local tmp="$1"
  if [[ -f "$STORE_FILE" ]]; then
    chmod --reference="$STORE_FILE" "$tmp"
    chown --reference="$STORE_FILE" "$tmp" 2>/dev/null || true
  else
    chmod 0600 "$tmp"
  fi
}

validate_store_json() {
  jq -e 'type=="object" and (.data|type=="object")' "$1" >/dev/null 2>&1
}

json_atomic_replace() {
  local source="$1" tmp
  local dir
  dir="$(dirname "$STORE_FILE")"
  tmp="$(mktemp "$dir/.env-store.replace.XXXXXX")"

  if ! cat "$source" >"$tmp"; then
    rm -f -- "$tmp"
    return 1
  fi
  preserve_store_metadata "$tmp"
  if ! mv -f -- "$tmp" "$STORE_FILE"; then
    rm -f -- "$tmp"
    return 1
  fi
}

ensure_store() {
  if [[ "$BACKEND" == "json" ]]; then
    ensure_store_json
  else
    ensure_store_sqlite
  fi
}

ensure_store_json() {
  local dir tmp
  dir="$(dirname "$STORE_FILE")"
  mkdir -p "$dir"
  json_lock_acquire

  if [[ ! -f "$STORE_FILE" || ! -s "$STORE_FILE" ]]; then
    tmp="$(mktemp "$dir/.env-store.init.XXXXXX")"
    if ! jq -cn --arg ts "$(now_iso)" '{version:1,updated_at:$ts,data:{}}' >"$tmp"; then
      rm -f -- "$tmp"
      json_lock_release
      die "Failed to initialize store: $STORE_FILE"
    fi
    preserve_store_metadata "$tmp"
    if ! mv -f -- "$tmp" "$STORE_FILE"; then
      rm -f -- "$tmp"
      json_lock_release
      die "Failed to initialize store atomically: $STORE_FILE"
    fi
    json_lock_release
    return 0
  fi

  if ! validate_store_json "$STORE_FILE"; then
    json_lock_release
    die "Invalid store format: $STORE_FILE"
  fi

  json_lock_release
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
  (( $# >= 1 )) || die 'Internal error: missing jq filter'
  local filter="${!#}"
  local -a jq_args=()
  if (( $# > 1 )); then
    jq_args=("${@:1:$#-1}")
  fi

  local dir tmp
  dir="$(dirname "$STORE_FILE")"
  mkdir -p "$dir"
  json_lock_acquire

  if ! validate_store_json "$STORE_FILE"; then
    json_lock_release
    die "Invalid store format: $STORE_FILE"
  fi

  tmp="$(mktemp "$dir/.env-store.write.XXXXXX")"
  if ! jq "${jq_args[@]}" "$filter" "$STORE_FILE" >"$tmp"; then
    rm -f -- "$tmp"
    json_lock_release
    die "Failed to update store: $STORE_FILE"
  fi
  if ! validate_store_json "$tmp"; then
    rm -f -- "$tmp"
    json_lock_release
    die "Refusing invalid store update: $STORE_FILE"
  fi

  preserve_store_metadata "$tmp"
  if ! mv -f -- "$tmp" "$STORE_FILE"; then
    rm -f -- "$tmp"
    json_lock_release
    die "Failed to replace store atomically: $STORE_FILE"
  fi
  json_lock_release
}

cmd_get() {
  local key="${1:-}" def_set=0 def=""
  shift || true
  [[ -n "$key" ]] || die 'get <KEY> [--default VALUE]'
  key_ok "$key" || die "Invalid key: $key"

  while [[ "${1:-}" ]]; do
    case "$1" in
      --default)
        shift || true
        def="${1:-}"
        def_set=1
        shift || true
        ;;
      *) die "Unknown flag for get: $1" ;;
    esac
  done

  if [[ "$BACKEND" == "json" ]]; then
    if jq -e --arg k "$key" '.data | has($k)' "$STORE_FILE" >/dev/null 2>&1; then
      local value_json
      value_json="$(jq -c --arg k "$key" '.data[$k]' "$STORE_FILE")"
      print_value_human_from_json "$value_json"
      return 0
    fi
  else
    local out value_json
    out="$("$SQLITE_BIN" -noheader "$STORE_DB" "SELECT v FROM kv WHERE k=$(sql_quote "$key") LIMIT 1;" 2>/dev/null || true)"
    if [[ -n "$out" ]] || "$SQLITE_BIN" -noheader "$STORE_DB" "SELECT 1 FROM kv WHERE k=$(sql_quote "$key") LIMIT 1;" | grep -qx '1'; then
      value_json="$(storage_to_json "$out")"
      print_value_human_from_json "$value_json"
      return 0
    fi
  fi

  if (( def_set )); then
    printf '%s\n' "$def"
  fi
}

cmd_set() {
  local key="${1:-}" value="${2-}"
  [[ -n "$key" ]] || die 'set <KEY> <VALUE>'
  key_ok "$key" || die "Invalid key: $key"
  shift || true
  shift || true
  [[ -z "${1:-}" ]] || die 'set accepts exactly 2 arguments'

  local value_json
  value_json="$(json_string_value "$value")"

  if [[ "$BACKEND" == "json" ]]; then
    write_with_filter \
      --arg k "$key" \
      --argjson v "$value_json" \
      --arg ts "$(now_iso)" \
      '.data[$k]=$v | .updated_at=$ts'
  else
    local ts
    ts="$(now_iso)"
    "$SQLITE_BIN" "$STORE_DB" "
      INSERT OR REPLACE INTO kv(k,v,updated_at)
      VALUES($(sql_quote "$key"),$(sql_quote "$value_json"),$(sql_quote "$ts"));
      INSERT OR REPLACE INTO meta(k,v)
      VALUES('updated_at',$(sql_quote "$ts"));
    " >/dev/null
  fi
}

cmd_get_json() {
  local key="${1:-}" def_set=0 def_json='null'
  shift || true
  [[ -n "$key" ]] || die 'get-json <KEY> [--default-json JSON]'
  key_ok "$key" || die "Invalid key: $key"

  while [[ "${1:-}" ]]; do
    case "$1" in
      --default-json)
        shift || true
        [[ -n "${1:-}" ]] || die 'Missing value for --default-json'
        def_json="$(json_compact "$1" || true)"
        [[ -n "$def_json" ]] || die 'Invalid JSON for --default-json'
        def_set=1
        shift || true
        ;;
      *) die "Unknown flag for get-json: $1" ;;
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

  if (( def_set )); then
    printf '%s\n' "$def_json"
    return 0
  fi
  return 1
}

cmd_set_json() {
  local key="${1:-}" raw="${2-}" value_json
  [[ -n "$key" ]] || die 'set-json <KEY> <JSON>'
  key_ok "$key" || die "Invalid key: $key"
  shift || true
  shift || true
  [[ -z "${1:-}" ]] || die 'set-json accepts exactly 2 arguments'

  value_json="$(json_compact "$raw" || true)"
  [[ -n "$value_json" ]] || die 'Invalid JSON value'

  if [[ "$BACKEND" == "json" ]]; then
    write_with_filter \
      --arg k "$key" \
      --argjson v "$value_json" \
      --arg ts "$(now_iso)" \
      '.data[$k]=$v | .updated_at=$ts'
  else
    local ts
    ts="$(now_iso)"
    "$SQLITE_BIN" "$STORE_DB" "
      INSERT OR REPLACE INTO kv(k,v,updated_at)
      VALUES($(sql_quote "$key"),$(sql_quote "$value_json"),$(sql_quote "$ts"));
      INSERT OR REPLACE INTO meta(k,v)
      VALUES('updated_at',$(sql_quote "$ts"));
    " >/dev/null
  fi
}

cmd_unset() {
  local key="${1:-}"
  [[ -n "$key" ]] || die 'unset <KEY>'
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
  [[ -n "$key" ]] || die 'has <KEY>'
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
      while IFS=$'\t' read -r key value; do
        [[ -n "$key" ]] || continue
        local value_json
        value_json="$(storage_to_json "${value:-}")"
        if printf '%s' "$value_json" | jq -e 'type=="string"' >/dev/null 2>&1; then
          printf '%s=%s\n' "$key" "$(printf '%s' "$value_json" | jq -r '.')"
        else
          printf '%s=%s\n' "$key" "$(printf '%s' "$value_json" | jq -c '.')"
        fi
      done
  fi
}

cmd_keys() {
  if [[ "$BACKEND" == "json" ]]; then
    jq -r '.data | keys[]' "$STORE_FILE"
  else
    "$SQLITE_BIN" -noheader "$STORE_DB" 'SELECT k FROM kv ORDER BY k;' 2>/dev/null
  fi
}

cmd_json() {
  if [[ "$BACKEND" == "json" ]]; then
    jq -c '.' "$STORE_FILE"
    return 0
  fi

  local version updated entries data key value value_json
  version="$(sqlite_meta_get version)"
  updated="$(sqlite_meta_get updated_at)"
  [[ "$version" =~ ^[0-9]+$ ]] || version=1
  [[ -n "$updated" ]] || updated=""

  entries="$("$SQLITE_BIN" -noheader -separator $'\t' "$STORE_DB" 'SELECT k,v FROM kv ORDER BY k;' 2>/dev/null || true)"
  data='{}'
  while IFS=$'\t' read -r key value; do
    [[ -n "$key" ]] || continue
    value_json="$(storage_to_json "${value:-}")"
    data="$(jq -cn --argjson d "$data" --arg k "$key" --argjson v "$value_json" '$d + {($k):$v}')"
  done <<<"$entries"

  jq -cn --argjson version "$version" --arg updated "$updated" --argjson data "$data" \
    '{version:$version,updated_at:$updated,data:$data}'
}

cmd_reset() {
  if [[ "$BACKEND" == "json" ]]; then
    local dir tmp
    dir="$(dirname "$STORE_FILE")"
    mkdir -p "$dir"
    json_lock_acquire
    tmp="$(mktemp "$dir/.env-store.reset.XXXXXX")"
    if ! jq -cn --arg ts "$(now_iso)" '{version:1,updated_at:$ts,data:{}}' >"$tmp"; then
      rm -f -- "$tmp"
      json_lock_release
      die "Failed to reset store: $STORE_FILE"
    fi
    preserve_store_metadata "$tmp"
    if ! mv -f -- "$tmp" "$STORE_FILE"; then
      rm -f -- "$tmp"
      json_lock_release
      die "Failed to reset store atomically: $STORE_FILE"
    fi
    json_lock_release
    return 0
  fi

  local ts
  ts="$(now_iso)"
  "$SQLITE_BIN" "$STORE_DB" "
    DELETE FROM kv;
    INSERT OR REPLACE INTO meta(k,v) VALUES('version','1');
    INSERT OR REPLACE INTO meta(k,v) VALUES('updated_at',$(sql_quote "$ts"));
  " >/dev/null
}

cmd_import() {
  local pair key value
  [[ "${1:-}" ]] || die 'import <KEY=VALUE...>'
  for pair in "$@"; do
    [[ "$pair" == *=* ]] || die "Invalid pair: $pair"
    key="${pair%%=*}"
    value="${pair#*=}"
    key_ok "$key" || die "Invalid key: $key"
    cmd_set "$key" "$value"
  done
}

cmd_import_json() {
  local pair key raw
  [[ "${1:-}" ]] || die 'import-json <KEY=JSON...>'
  for pair in "$@"; do
    [[ "$pair" == *=* ]] || die "Invalid pair: $pair"
    key="${pair%%=*}"
    raw="${pair#*=}"
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
  ENV_STORE_LOCK_TIMEOUT_MS=5000
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

  local command="${1:-}"
  shift || true
  case "$command" in
    -h|--help|'') usage; exit 0 ;;
  esac

  ensure_store

  case "$command" in
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
    *) die "Unknown command: $command" ;;
  esac
}

main "$@"
