#!/usr/bin/env bash
set -euo pipefail

# es-policy.sh
# - Ensures ILM delete-after-30d policies + data-stream index templates for:
#     1) lds-*-*
#     2) log-*-*
# - Applies ILM policy + replicas=0 to existing indices (and .ds backing indices)
# - Provisions Kibana Data Views:
#     1) "LDS logs"         -> lds-*-*
#     2) "All logs + LDS"   -> logs-*-*,logs-*,lds-*-*
#   and sets "All logs + LDS" as the default data view.
#
# Flags:
#   --force   Overwrite ILM policies/templates and update Kibana data views/default
#
# Usage:
#   ES_URL=http://elasticsearch:9200 KIBANA_URL=http://kibana:5601 ./es-policy.sh
#   ./es-policy.sh --force

ES_URL="${ES_URL:-http://elasticsearch:9200}"
KIBANA_URL="${KIBANA_URL:-http://kibana:5601}"

POLICY_LDS="${POLICY_LDS:-lds-delete-30d}"
POLICY_LOG="${POLICY_LOG:-log-delete-30d}"

TPL_LDS="${TPL_LDS:-lds-template}"
TPL_LOG="${TPL_LOG:-log-template}"

PAT_LDS="${PAT_LDS:-lds-*-*}"
PAT_LOG="${PAT_LOG:-log-*-*}"

# Single-node: replicas must be 0 to avoid yellow
REPLICAS="${REPLICAS:-0}"

# Data stream backing index patterns
PAT_DS_LDS="${PAT_DS_LDS:-.ds-lds-*-*}"
PAT_DS_LOG="${PAT_DS_LOG:-.ds-log-*-*}"

# Kibana data views requested
DV1_NAME="${DV1_NAME:-LDS logs}"
DV1_TITLE="${DV1_TITLE:-lds-*-*}"

DV2_NAME="${DV2_NAME:-All logs + LDS}"
DV2_TITLE="${DV2_TITLE:-logs-*-*,logs-*,lds-*-*}"

FORCE=0
while [[ "${1:-}" != "" ]]; do
  case "$1" in
  --force) FORCE=1; shift ;;
  -h|--help)
    cat <<'EOF'
Usage: es-policy.sh [--force]
  --force   Overwrite ILM policies/templates and update Kibana data views/default

Env:
  ES_URL=http://elasticsearch:9200
  KIBANA_URL=http://kibana:5601
  REPLICAS=0

Kibana Data Views:
  DV1_NAME="LDS logs"
  DV1_TITLE="lds-*-*"
  DV2_NAME="All logs + LDS"
  DV2_TITLE="logs-*-*,logs-*,lds-*-*"
EOF
    exit 0
    ;;
  *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

# For mutating ES calls
CURL_ES_PUT=(curl -fsS --connect-timeout 3 --max-time 25)
# For Kibana calls (needs kbn-xsrf)
CURL_KBN=(curl -fsS --connect-timeout 3 --max-time 25 -H 'kbn-xsrf: true' -H 'Content-Type: application/json')

# Quiet HTTP code helper (avoids noisy "curl: (22) 404" output)
http_code() {
  curl -sS --connect-timeout 3 --max-time 15 -o /dev/null -w '%{http_code}' "$@" 2>/dev/null || printf '000'
}

es_put() { "${CURL_ES_PUT[@]}" -X PUT -H 'Content-Type: application/json' "$ES_URL$1" -d "$2"; }

ensure_es_up() {
  local code="000"
  code="$(http_code "$ES_URL/")"
  if [[ "$code" != "200" && "$code" != "401" ]]; then
    echo "Error: Elasticsearch not reachable at: $ES_URL (HTTP $code)" >&2
    exit 1
  fi
}

policy_exists() { [[ "$(http_code "$ES_URL/_ilm/policy/$1")" == "200" ]]; }
template_exists() { [[ "$(http_code "$ES_URL/_index_template/$1")" == "200" ]]; }

put_policy_delete_30d() {
  local name="$1"
  es_put "/_ilm/policy/$name" '{
    "policy": {
      "phases": {
        "hot": { "actions": {} },
        "delete": {
          "min_age": "30d",
          "actions": { "delete": {} }
        }
      }
    }
  }' >/dev/null
}

ensure_policy_delete_30d() {
  local name="$1"
  if (( FORCE )); then
    echo "FORCE: updating ILM policy: $name"
    put_policy_delete_30d "$name"
    echo "OK: ILM policy updated: $name"
    return 0
  fi

  if policy_exists "$name"; then
    echo "OK: ILM policy exists: $name"
    return 0
  fi

  echo "CREATE: ILM policy: $name (delete after 30d)"
  put_policy_delete_30d "$name"
  echo "OK: ILM policy created: $name"
}

put_index_template() {
  local tpl="$1" pattern="$2" policy="$3" replicas="$4" priority="$5"
  # IMPORTANT: data_stream:{} required because your targets are data streams.
  # NOTE: use index.number_of_replicas (safe across versions).
  es_put "/_index_template/$tpl" "{
    \"index_patterns\": [\"$pattern\"],
    \"data_stream\": {},
    \"template\": {
      \"settings\": {
        \"index.lifecycle.name\": \"$policy\",
        \"index.number_of_replicas\": $replicas
      }
    },
    \"priority\": $priority
  }" >/dev/null
}

ensure_index_template() {
  local tpl="$1" pattern="$2" policy="$3" replicas="$4" priority="${5:-500}"

  if (( FORCE )); then
    echo "FORCE: updating index template: $tpl (pattern=$pattern, policy=$policy, replicas=$replicas)"
    put_index_template "$tpl" "$pattern" "$policy" "$replicas" "$priority"
    echo "OK: index template updated: $tpl"
    return 0
  fi

  if template_exists "$tpl"; then
    echo "OK: index template exists: $tpl (pattern=$pattern, policy=$policy, replicas=$replicas)"
    return 0
  fi

  echo "CREATE: index template: $tpl (pattern=$pattern, policy=$policy, replicas=$replicas)"
  put_index_template "$tpl" "$pattern" "$policy" "$replicas" "$priority"
  echo "OK: index template created: $tpl"
}

apply_settings_to_existing() {
  local pattern="$1" policy="$2" replicas="$3"

  local code="000"
  code="$(http_code "$ES_URL/_cat/indices/$pattern?h=index")"
  if [[ "$code" == "404" ]]; then
    echo "SKIP: no indices match: $pattern"
    return 0
  fi

  echo "APPLY: policy='$policy', replicas=$replicas to: $pattern"
  local sc="000"
  sc="$(http_code -X PUT -H 'Content-Type: application/json' "$ES_URL/$pattern/_settings" \
    -d "{\"index.lifecycle.name\":\"$policy\",\"index.number_of_replicas\":$replicas}")"

  if [[ "$sc" == "200" ]]; then
    echo "OK: settings applied: $pattern"
  elif [[ "$sc" == "404" ]]; then
    echo "SKIP: nothing to update: $pattern"
  else
    echo "WARN: failed applying settings to $pattern (HTTP $sc)" >&2
  fi
}

# ---------------- Kibana Data Views ----------------

ensure_kibana_up() {
  local code="000"
  # /api/status exists and doesn't require auth when security disabled (in most setups)
  code="$(http_code "$KIBANA_URL/api/status")"
  if [[ "$code" != "200" ]]; then
    echo "WARN: Kibana not reachable at: $KIBANA_URL (HTTP $code) — skipping data view setup" >&2
    return 1
  fi
  return 0
}

kbn_get_all_data_views() {
  # returns JSON
  curl -sS --connect-timeout 3 --max-time 25 -H 'kbn-xsrf: true' "$KIBANA_URL/api/data_views"
}

kbn_find_data_view_id_by_title() {
  local title="$1"
  if command -v jq >/dev/null 2>&1; then
    kbn_get_all_data_views | jq -r --arg t "$title" '.data_view[]? | select(.title==$t) | .id' | head -n1
  else
    # best-effort fallback (not perfect JSON parsing)
    kbn_get_all_data_views | tr '\n' ' ' | sed -n "s/.*\"title\":\"$title\"[^}]*\"id\":\"\([^\"]*\)\".*/\1/p" | head -n1
  fi
}

kbn_create_data_view() {
  local name="$1" title="$2" timefield="$3"
  "${CURL_KBN[@]}" -X POST "$KIBANA_URL/api/data_views/data_view" \
    -d "{
      \"data_view\": {
        \"title\": \"$title\",
        \"name\": \"$name\",
        \"timeFieldName\": \"$timefield\"
      }
    }"
}

kbn_update_data_view() {
  local id="$1" name="$2" title="$3" timefield="$4"

  # Kibana supports update via POST /api/data_views/data_view/<id>
  # Some versions also accept PUT. We'll try PUT then fallback to POST.
  if curl -sS --connect-timeout 3 --max-time 25 -o /dev/null -w '%{http_code}' \
    -X PUT "$KIBANA_URL/api/data_views/data_view/$id" \
    -H 'kbn-xsrf: true' -H 'Content-Type: application/json' \
    -d "{
        \"data_view\": {
          \"title\": \"$title\",
          \"name\": \"$name\",
          \"timeFieldName\": \"$timefield\"
        }
      }" 2>/dev/null | grep -qx '200'; then
    return 0
  fi

  "${CURL_KBN[@]}" -X POST "$KIBANA_URL/api/data_views/data_view/$id" \
    -d "{
      \"data_view\": {
        \"title\": \"$title\",
        \"name\": \"$name\",
        \"timeFieldName\": \"$timefield\"
      }
    }"
}

kbn_set_default_data_view() {
  local id="$1"
  "${CURL_KBN[@]}" -X POST "$KIBANA_URL/api/kibana/settings" \
    -d "{\"changes\":{\"defaultIndex\":\"$id\"}}"
}

ensure_data_view() {
  local name="$1" title="$2" timefield="$3"
  local id=""
  id="$(kbn_find_data_view_id_by_title "$title" || true)"

  if [[ -n "$id" ]]; then
    if (( FORCE )); then
      echo "FORCE: updating Kibana data view: '$name' (title=$title)"
      kbn_update_data_view "$id" "$name" "$title" "$timefield" >/dev/null || {
        echo "WARN: failed updating data view '$name' (title=$title)" >&2
      }
      echo "OK: Kibana data view updated: $name"
    else
      echo "OK: Kibana data view exists: $name (title=$title)"
    fi
    printf '%s\n' "$id"
    return 0
  fi

  echo "CREATE: Kibana data view: $name (title=$title)"
  local resp=""
  resp="$(kbn_create_data_view "$name" "$title" "$timefield" 2>/dev/null || true)"

  if command -v jq >/dev/null 2>&1; then
    id="$(printf '%s' "$resp" | jq -r '.data_view.id // empty')"
  else
    id="$(printf '%s' "$resp" | tr '\n' ' ' | sed -n 's/.*"id":"\([^"]*\)".*/\1/p' | head -n1)"
  fi

  if [[ -z "$id" ]]; then
    echo "WARN: created data view '$name' but could not parse id (missing jq?). Response:" >&2
    echo "$resp" >&2
    return 0
  fi

  echo "OK: Kibana data view created: $name (id=$id)"
  printf '%s\n' "$id"
}

setup_kibana_data_views() {
  ensure_kibana_up || return 0

  # Always use @timestamp for Discover
  local tf="@timestamp"

  local id1="" id2=""
  id1="$(ensure_data_view "$DV1_NAME" "$DV1_TITLE" "$tf" || true)"
  id2="$(ensure_data_view "$DV2_NAME" "$DV2_TITLE" "$tf" || true)"

  if [[ -n "$id2" ]]; then
    echo "SET DEFAULT: Kibana data view -> $DV2_NAME (id=$id2)"
    kbn_set_default_data_view "$id2" >/dev/null || {
      echo "WARN: failed to set default data view in Kibana" >&2
      return 0
    }
    echo "OK: default data view set: $DV2_NAME"
  else
    echo "WARN: could not determine id for '$DV2_NAME' — cannot set default (install jq for reliability)" >&2
  fi
}

main() {
  ensure_es_up

  # ES: policies + templates
  ensure_policy_delete_30d "$POLICY_LDS"
  ensure_policy_delete_30d "$POLICY_LOG"

  ensure_index_template "$TPL_LDS" "$PAT_LDS" "$POLICY_LDS" "$REPLICAS" 700
  ensure_index_template "$TPL_LOG" "$PAT_LOG" "$POLICY_LOG" "$REPLICAS" 650

  # ES: apply to existing indices + backing indices
  apply_settings_to_existing "$PAT_LDS" "$POLICY_LDS" "$REPLICAS"
  apply_settings_to_existing "$PAT_LOG" "$POLICY_LOG" "$REPLICAS"
  apply_settings_to_existing "$PAT_DS_LDS" "$POLICY_LDS" "$REPLICAS"
  apply_settings_to_existing "$PAT_DS_LOG" "$POLICY_LOG" "$REPLICAS"

  # Kibana: data views + default
  setup_kibana_data_views

  echo "DONE: ES policies/templates/settings + Kibana data views completed."
}

main
