#!/usr/bin/env bash
set -euo pipefail

# lds-ilm-bootstrap.sh
# - Creates ILM delete-after-30d policies + index templates for:
#     1) lds-*-*
#     2) log-*-*
# - Attaches the policies to existing indices matching those patterns.
#
# Usage:
#   ES_URL=http://elasticsearch:9200 ./lds-ilm-bootstrap.sh
#   # or just ./lds-ilm-bootstrap.sh (defaults to http://elasticsearch:9200)

ES_URL="${ES_URL:-http://elasticsearch:9200}"

# Policy/template names (change if you want different retention per pattern)
POLICY_LDS="${POLICY_LDS:-lds-delete-30d}"
POLICY_LOG="${POLICY_LOG:-log-delete-30d}"

TPL_LDS="${TPL_LDS:-lds-template}"
TPL_LOG="${TPL_LOG:-log-template}"

PAT_LDS="${PAT_LDS:-lds-*-*}"
PAT_LOG="${PAT_LOG:-log-*-*}"

CURL=(curl -fsS --connect-timeout 3 --max-time 15)

http_code() {
  # prints HTTP code only
  "${CURL[@]}" -o /dev/null -w '%{http_code}' "$@"
}

es_get() { "${CURL[@]}" -X GET "$ES_URL$1"; }
es_put() { "${CURL[@]}" -X PUT -H 'Content-Type: application/json' "$ES_URL$1" -d "$2"; }
es_post() { "${CURL[@]}" -X POST -H 'Content-Type: application/json' "$ES_URL$1" -d "$2"; }

ensure_es_up() {
  local code
  code="$(http_code "$ES_URL/")" || code="000"
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
  local tpl="$1" pattern="$2" policy="$3" priority="${4:-500}"

  if template_exists "$tpl"; then
    echo "OK: index template exists: $tpl (pattern=$pattern, policy=$policy)"
    return 0
  fi

  echo "CREATE: index template: $tpl (pattern=$pattern, policy=$policy)"
  es_put "/_index_template/$tpl" "{
    \"index_patterns\": [\"$pattern\"],
    \"template\": {
      \"settings\": {
        \"index.lifecycle.name\": \"$policy\"
      }
    },
    \"priority\": $priority
  }" >/dev/null

  echo "OK: index template created: $tpl"
}

attach_policy_to_existing_indices() {
  local pattern="$1" policy="$2"

  # Check if there are any indices matching pattern
  local code
  code="$(http_code "$ES_URL/_cat/indices/$pattern?h=index")" || code="000"

  if [[ "$code" == "404" ]]; then
    echo "SKIP: no indices match: $pattern"
    return 0
  fi
  if [[ "$code" != "200" ]]; then
    # Some ES versions return 200 with empty body; anything else is suspicious but non-fatal.
    echo "WARN: could not verify indices for pattern: $pattern (HTTP $code) — continuing" >&2
  fi

  echo "APPLY: ILM policy '$policy' to existing indices: $pattern"
  # Use PUT /<pattern>/_settings — ignores missing indices? (pattern not found can 404)
  # We'll treat 404 as "nothing to do".
  local sc
  sc="$(http_code -X PUT -H 'Content-Type: application/json' "$ES_URL/$pattern/_settings" \
    -d "{\"index.lifecycle.name\":\"$policy\"}")" || sc="000"

  if [[ "$sc" == "200" ]]; then
    echo "OK: policy applied to existing indices: $pattern"
  elif [[ "$sc" == "404" ]]; then
    echo "SKIP: no indices to update: $pattern"
  else
    echo "WARN: failed applying policy to $pattern (HTTP $sc)" >&2
  fi
}

main() {
  ensure_es_up

  # 1) Ensure policies
  ensure_policy_delete_30d "$POLICY_LDS"
  ensure_policy_delete_30d "$POLICY_LOG"

  # 2) Ensure templates (so new indices automatically get ILM)
  ensure_index_template "$TPL_LDS" "$PAT_LDS" "$POLICY_LDS" 700
  ensure_index_template "$TPL_LOG" "$PAT_LOG" "$POLICY_LOG" 650

  # 3) Attach to existing indices (best-effort)
  attach_policy_to_existing_indices "$PAT_LDS" "$POLICY_LDS"
  attach_policy_to_existing_indices "$PAT_LOG" "$POLICY_LOG"

  echo "DONE: ILM bootstrap completed."
}

main "$@"
