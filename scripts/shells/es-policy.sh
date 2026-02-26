#!/usr/bin/env bash
set -euo pipefail

# es-policy.sh
# - Ensures ILM delete-after-30d policies + data-stream index templates for:
#     1) lds-*-*-*
#     2) log-*-*
# - Applies ILM policy + replicas=0 to existing indices (and .ds backing indices)
# - Provisions Kibana Data Views:
#     1) "LDS logs"         -> lds-*-*-*
#     2) "All logs + LDS"   -> logs-*-*,logs-*,lds-*-*-*
#   and sets "All logs + LDS" as the default data view.
#
# Flags:
#   --force   Overwrite ILM policies/templates and update Kibana data views/default

###############################################################################
# UI (mkhost-like): colored tags
###############################################################################
BOLD=$'\033[1m'
DIM=$'\033[2m'
RED=$'\033[1;31m'
GREEN=$'\033[1;32m'
CYAN=$'\033[1;36m'
YELLOW=$'\033[1;33m'
MAGENTA=$'\033[1;35m'
NC=$'\033[0m'

_tag() { printf '%b' "$1"; }
say()  { printf '%b\n' "$*"; }

ok()   { say "${GREEN}[ok]${NC} $*"; }
warn() { say "${YELLOW}[warn]${NC} $*"; }
err()  { say "${RED}[err]${NC} $*"; }
info() { say "${CYAN}[info]${NC} $*"; }
step() { say "${MAGENTA}${BOLD}==>${NC} $*"; }
dim()  { say "${DIM}$*${NC}"; }

###############################################################################
# Config
###############################################################################
ES_URL="${ES_URL:-http://elasticsearch:9200}"
KIBANA_URL="${KIBANA_URL:-http://kibana:5601}"

POLICY_LDS="${POLICY_LDS:-lds-delete-30d}"
POLICY_LOG="${POLICY_LOG:-log-delete-30d}"

TPL_LDS="${TPL_LDS:-lds-template}"
TPL_LOG="${TPL_LOG:-log-template}"

PAT_LDS="${PAT_LDS:-lds-*-*-*}"         # lds-[service]-[kind]-YYYYMMDD
PAT_LOG="${PAT_LOG:-log-*-*}"

REPLICAS="${REPLICAS:-0}"

PAT_DS_LDS="${PAT_DS_LDS:-.ds-lds-*-*-*}"
PAT_DS_LOG="${PAT_DS_LOG:-.ds-log-*-*}"

DV1_NAME="${DV1_NAME:-LDS logs}"
DV1_TITLE="${DV1_TITLE:-lds-*-*-*}"

DV2_NAME="${DV2_NAME:-All logs + LDS}"
DV2_TITLE="${DV2_TITLE:-logs-*-*,logs-*,lds-*-*-*}"

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
EOF
    exit 0
    ;;
  *) err "Unknown arg: $1"; exit 2 ;;
  esac
done

###############################################################################
# Curl helpers
###############################################################################
CURL_ES_PUT=(curl -fsS --connect-timeout 3 --max-time 25)
CURL_KBN=(curl -fsS --connect-timeout 3 --max-time 25 -H 'kbn-xsrf: true' -H 'Content-Type: application/json')

http_code() {
  curl -sS --connect-timeout 3 --max-time 15 -o /dev/null -w '%{http_code}' "$@" 2>/dev/null || printf '000'
}

es_put() { "${CURL_ES_PUT[@]}" -X PUT -H 'Content-Type: application/json' "$ES_URL$1" -d "$2"; }

###############################################################################
# Elasticsearch
###############################################################################
ensure_es_up() {
  local code="000"
  code="$(http_code "$ES_URL/")"
  if [[ "$code" != "200" && "$code" != "401" ]]; then
    err "Elasticsearch not reachable: $ES_URL (HTTP $code)"
    exit 1
  fi
  ok "Elasticsearch reachable: $ES_URL"
}

policy_exists()   { [[ "$(http_code "$ES_URL/_ilm/policy/$1")" == "200" ]]; }
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
    info "force update ILM policy: $name"
    put_policy_delete_30d "$name"
    ok "updated ILM policy: $name"
    return 0
  fi

  if policy_exists "$name"; then
    ok "ILM policy exists: $name"
    return 0
  fi

  info "create ILM policy: $name (delete after 30d)"
  put_policy_delete_30d "$name"
  ok "created ILM policy: $name"
}

put_index_template() {
  local tpl="$1" pattern="$2" policy="$3" replicas="$4" priority="$5"
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
    info "force update template: $tpl (pattern=$pattern, policy=$policy, replicas=$replicas)"
    put_index_template "$tpl" "$pattern" "$policy" "$replicas" "$priority"
    ok "updated template: $tpl"
    return 0
  fi

  if template_exists "$tpl"; then
    ok "template exists: $tpl"
    return 0
  fi

  info "create template: $tpl (pattern=$pattern, policy=$policy, replicas=$replicas)"
  put_index_template "$tpl" "$pattern" "$policy" "$replicas" "$priority"
  ok "created template: $tpl"
}

apply_settings_to_existing() {
  local pattern="$1" policy="$2" replicas="$3"

  local code="000"
  code="$(http_code "$ES_URL/_cat/indices/$pattern?h=index")"
  if [[ "$code" == "404" ]]; then
    dim "[skip] no indices match: $pattern"
    return 0
  fi

  info "apply settings: pattern=$pattern policy=$policy replicas=$replicas"
  local sc="000"
  sc="$(http_code -X PUT -H 'Content-Type: application/json' "$ES_URL/$pattern/_settings" \
    -d "{\"index.lifecycle.name\":\"$policy\",\"index.number_of_replicas\":$replicas}")"

  if [[ "$sc" == "200" ]]; then
    ok "settings applied: $pattern"
  elif [[ "$sc" == "404" ]]; then
    dim "[skip] nothing to update: $pattern"
  else
    warn "failed applying settings: $pattern (HTTP $sc)"
  fi
}

###############################################################################
# Kibana Data Views
###############################################################################
ensure_kibana_up() {
  local code="000"
  code="$(http_code "$KIBANA_URL/api/status")"
  if [[ "$code" != "200" ]]; then
    warn "Kibana not reachable: $KIBANA_URL (HTTP $code) — skipping data views"
    return 1
  fi
  ok "Kibana reachable: $KIBANA_URL"
  return 0
}

kbn_get_all_data_views() {
  curl -sS --connect-timeout 3 --max-time 25 -H 'kbn-xsrf: true' "$KIBANA_URL/api/data_views"
}

kbn_find_data_view_id_by_title() {
  local title="$1"
  if command -v jq >/dev/null 2>&1; then
    kbn_get_all_data_views | jq -r --arg t "$title" '.data_view[]? | select(.title==$t) | .id' | head -n1
  else
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
      info "force update data view: $name (title=$title)"
      kbn_update_data_view "$id" "$name" "$title" "$timefield" >/dev/null || {
        warn "failed updating data view: $name (title=$title)"
      }
      ok "updated data view: $name"
    else
      ok "data view exists: $name (title=$title)"
    fi
    printf '%s\n' "$id"
    return 0
  fi

  info "create data view: $name (title=$title)"
  local resp="" created=""
  resp="$(kbn_create_data_view "$name" "$title" "$timefield" 2>/dev/null || true)"

  if command -v jq >/dev/null 2>&1; then
    id="$(printf '%s' "$resp" | jq -r '.data_view.id // empty')"
  else
    id="$(printf '%s' "$resp" | tr '\n' ' ' | sed -n 's/.*"id":"\([^"]*\)".*/\1/p' | head -n1)"
  fi

  if [[ -z "$id" ]]; then
    warn "created data view '$name' but could not parse id (install jq)."
    warn "raw response: $resp"
    return 0
  fi

  ok "created data view: $name (id=$id)"
  printf '%s\n' "$id"
}

setup_kibana_data_views() {
  ensure_kibana_up || return 0

  local tf="@timestamp"
  local id2=""

  ensure_data_view "$DV1_NAME" "$DV1_TITLE" "$tf" >/dev/null || true
  id2="$(ensure_data_view "$DV2_NAME" "$DV2_TITLE" "$tf" || true)"

  if [[ -n "$id2" ]]; then
    info "set default data view: $DV2_NAME (id=$id2)"
    kbn_set_default_data_view "$id2" >/dev/null || {
      warn "failed to set default data view"
      return 0
    }
    ok "default data view set: $DV2_NAME"
  else
    warn "could not determine id for '$DV2_NAME' — cannot set default (install jq)"
  fi
}

main() {
  ensure_es_up

  step "Elasticsearch policies/templates"
  ensure_policy_delete_30d "$POLICY_LDS"
  ensure_policy_delete_30d "$POLICY_LOG"

  ensure_index_template "$TPL_LDS" "$PAT_LDS" "$POLICY_LDS" "$REPLICAS" 700
  ensure_index_template "$TPL_LOG" "$PAT_LOG" "$POLICY_LOG" "$REPLICAS" 650

  step "Apply settings to existing indices"
  apply_settings_to_existing "$PAT_LDS" "$POLICY_LDS" "$REPLICAS"
  apply_settings_to_existing "$PAT_LOG" "$POLICY_LOG" "$REPLICAS"
  apply_settings_to_existing "$PAT_DS_LDS" "$POLICY_LDS" "$REPLICAS"
  apply_settings_to_existing "$PAT_DS_LOG" "$POLICY_LOG" "$REPLICAS"

  step "Kibana data views"
  setup_kibana_data_views

  ok "done"
}

main