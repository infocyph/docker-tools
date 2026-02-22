#!/usr/bin/env bash
set -euo pipefail

# es-month-policy.sh
# - Ensures ILM delete-after-30d policies + index templates for:
#     1) lds-*-*
#     2) log-*-*
# - Applies ILM policy + single-node friendly replicas=0 to existing indices.
# - Also applies to data stream backing indices:
#     .ds-lds-*-* and .ds-log-*-*
#
# Usage:
#   ES_URL=http://elasticsearch:9200 ./es-month-policy.sh
#   # defaults to http://elasticsearch:9200

ES_URL="${ES_URL:-http://elasticsearch:9200}"

# Policy/template names
POLICY_LDS="${POLICY_LDS:-lds-delete-30d}"
POLICY_LOG="${POLICY_LOG:-log-delete-30d}"

TPL_LDS="${TPL_LDS:-lds-template}"
TPL_LOG="${TPL_LOG:-log-template}"

PAT_LDS="${PAT_LDS:-lds-*-*}"
PAT_LOG="${PAT_LOG:-log-*-*}"

# Single-node: replicas must be 0 to avoid yellow
REPLICAS="${REPLICAS:-0}"

# Derive data stream backing index patterns (best-effort)
PAT_DS_LDS="${PAT_DS_LDS:-.ds-lds-*-*}"
PAT_DS_LOG="${PAT_DS_LOG:-.ds-log-*-*}"

CURL=(curl -fsS --connect-timeout 3 --max-time 20)

http_code() {
  "${CURL[@]}" -o /dev/null -w '%{http_code}' "$@"
}

es_put() {
  "${CURL[@]}" -X PUT -H 'Content-Type: application/json' "$ES_URL$1" -d "$2"
}

ensure_es_up() {
  local code="000"
  code="$(http_code "$ES_URL/")" || true
  if [[ "$code" != "200" && "$code" != "401" ]]; then
    echo "Error: Elasticsearch not reachable at: $ES_URL (HTTP $code)" >&2
    exit 1
  fi
}

policy_exists() {
  local name="$1"
  [[ "$(http_code "$ES_URL/_ilm/policy/$name")" == "200" ]]
}

template_exists() {
  local name="$1"
  [[ "$(http_code "$ES_URL/_index_template/$name")" == "200" ]]
}

ensure_policy_delete_30d() {
  local name="$1"
  if policy_exists "$name"; then
    echo "OK: ILM policy exists: $name"
    return 0
  fi

  echo "CREATE: ILM policy: $name (delete after 30d)"
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

  echo "OK: ILM policy created: $name"
}

ensure_index_template() {
  local tpl="$1" pattern="$2" policy="$3" replicas="$4" priority="${5:-500}"

  if template_exists "$tpl"; then
    echo "OK: index template exists: $tpl (pattern=$pattern, policy=$policy, replicas=$replicas)"
    return 0
  fi

  echo "CREATE: index template: $tpl (pattern=$pattern, policy=$policy, replicas=$replicas)"
  es_put "/_index_template/$tpl" "{
    \"index_patterns\": [\"$pattern\"],
    \"template\": {
      \"settings\": {
        \"index.lifecycle.name\": \"$policy\",
        \"number_of_replicas\": $replicas
      }
    },
    \"priority\": $priority
  }" >/dev/null

  echo "OK: index template created: $tpl"
}

apply_settings_to_existing() {
  local pattern="$1" policy="$2" replicas="$3"

  # Does anything match?
  local code="000"
  code="$(http_code "$ES_URL/_cat/indices/$pattern?h=index")" || true

  if [[ "$code" == "404" ]]; then
    echo "SKIP: no indices match: $pattern"
    return 0
  fi

  echo "APPLY: policy='$policy', replicas=$replicas to: $pattern"
  local sc="000"
  sc="$(http_code -X PUT -H 'Content-Type: application/json' "$ES_URL/$pattern/_settings" \
    -d "{\"index.lifecycle.name\":\"$policy\",\"index.number_of_replicas\":$replicas}")" || true

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

  # 1) Policies
  ensure_policy_delete_30d "$POLICY_LDS"
  ensure_policy_delete_30d "$POLICY_LOG"

  # 2) Templates (ILM + replicas=0)
  ensure_index_template "$TPL_LDS" "$PAT_LDS" "$POLICY_LDS" "$REPLICAS" 700
  ensure_index_template "$TPL_LOG" "$PAT_LOG" "$POLICY_LOG" "$REPLICAS" 650

  # 3) Apply to existing indices (both normal + data-stream backing indices)
  apply_settings_to_existing "$PAT_LDS" "$POLICY_LDS" "$REPLICAS"
  apply_settings_to_existing "$PAT_LOG" "$POLICY_LOG" "$REPLICAS"

  # Data stream backing indices (.ds-...) often carry the yellow replica issue too
  apply_settings_to_existing "$PAT_DS_LDS" "$POLICY_LDS" "$REPLICAS"
  apply_settings_to_existing "$PAT_DS_LOG" "$POLICY_LOG" "$REPLICAS"

  echo "DONE: ILM+replicas bootstrap completed."
}

main "$@"
