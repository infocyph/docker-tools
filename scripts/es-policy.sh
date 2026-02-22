#!/usr/bin/env bash
set -euo pipefail

# es-policy.sh
# - Ensures ILM delete-after-30d policies + data-stream index templates for:
#     1) lds-*-*
#     2) log-*-*
# - Applies ILM policy + replicas=0 to existing indices (and .ds backing indices)
#
# Flags:
#   --force   Overwrite policies and templates (PUT even if they already exist)
#
# Usage:
#   ES_URL=http://elasticsearch:9200 ./es-policy.sh
#   ES_URL=http://elasticsearch:9200 ./es-policy.sh --force

ES_URL="${ES_URL:-http://elasticsearch:9200}"

POLICY_LDS="${POLICY_LDS:-lds-delete-30d}"
POLICY_LOG="${POLICY_LOG:-log-delete-30d}"

TPL_LDS="${TPL_LDS:-lds-template}"
TPL_LOG="${TPL_LOG:-log-template}"

PAT_LDS="${PAT_LDS:-lds-*-*}"
PAT_LOG="${PAT_LOG:-log-*-*}"

REPLICAS="${REPLICAS:-0}"

PAT_DS_LDS="${PAT_DS_LDS:-.ds-lds-*-*}"
PAT_DS_LOG="${PAT_DS_LOG:-.ds-log-*-*}"

FORCE=0
while [[ "${1:-}" != "" ]]; do
  case "$1" in
  --force) FORCE=1; shift ;;
  -h|--help)
    cat <<'EOF'
Usage: es-policy.sh [--force]
  --force   Overwrite ILM policies and index templates (PUT even if they exist)

Env:
  ES_URL=http://elasticsearch:9200
  REPLICAS=0
  POLICY_LDS=lds-delete-30d
  POLICY_LOG=log-delete-30d
  TPL_LDS=lds-template
  TPL_LOG=log-template
  PAT_LDS=lds-*-*
  PAT_LOG=log-*-*
EOF
    exit 0
    ;;
  *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

CURL_PUT=(curl -fsS --connect-timeout 3 --max-time 25)

http_code() {
  curl -sS --connect-timeout 3 --max-time 15 -o /dev/null -w '%{http_code}' "$@" 2>/dev/null || printf '000'
}

es_put() { "${CURL_PUT[@]}" -X PUT -H 'Content-Type: application/json' "$ES_URL$1" -d "$2"; }

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

  # IMPORTANT: data_stream:{} required (your targets are data streams)
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

main() {
  ensure_es_up

  ensure_policy_delete_30d "$POLICY_LDS"
  ensure_policy_delete_30d "$POLICY_LOG"

  ensure_index_template "$TPL_LDS" "$PAT_LDS" "$POLICY_LDS" "$REPLICAS" 700
  ensure_index_template "$TPL_LOG" "$PAT_LOG" "$POLICY_LOG" "$REPLICAS" 650

  apply_settings_to_existing "$PAT_LDS" "$POLICY_LDS" "$REPLICAS"
  apply_settings_to_existing "$PAT_LOG" "$POLICY_LOG" "$REPLICAS"
  apply_settings_to_existing "$PAT_DS_LDS" "$POLICY_LDS" "$REPLICAS"
  apply_settings_to_existing "$PAT_DS_LOG" "$POLICY_LOG" "$REPLICAS"

  echo "DONE: ILM+replicas bootstrap completed."
}

main