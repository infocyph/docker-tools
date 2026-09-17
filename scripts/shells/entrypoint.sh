#!/bin/bash
set -euo pipefail

HOST_OS="$(printf '%s' "${HOST_OS:-linux}" | tr '[:upper:]' '[:lower:]')" && export HOST_OS

init_project_scope() {
  local project="${STATUS_PROJECT:-${LDS_COMPOSE_PROJECT:-${COMPOSE_PROJECT_NAME:-}}}"
  local candidate detected=""
  local project_env_file="${LDS_PROJECT_ENV_FILE:-${BASH_ENV:-/run/lds-project.env}}"

  project="$(printf '%s' "$project" | xargs 2>/dev/null || true)"

  if [[ -z "$project" ]] && command -v docker >/dev/null 2>&1; then
    for candidate in "${HOSTNAME:-}" "${TOOLS_CONTAINER_NAME:-SERVER_TOOLS}" SERVER_TOOLS; do
      [[ -n "$candidate" ]] || continue
      detected="$(docker inspect -f '{{ index .Config.Labels "com.docker.compose.project" }}' "$candidate" 2>/dev/null || true)"
      detected="$(printf '%s' "$detected" | xargs 2>/dev/null || true)"
      if [[ -n "$detected" && "$detected" != '<no value>' ]]; then
        project="$detected"
        break
      fi
    done
  fi

  # An unresolved stack is a bounded degraded state, never permission to survey
  # unrelated Compose projects on the host daemon.
  [[ -n "$project" ]] || project="unknown"

  STATUS_PROJECT="$project"
  LDS_COMPOSE_PROJECT="$project"
  export STATUS_PROJECT LDS_COMPOSE_PROJECT

  mkdir -p "$(dirname "$project_env_file")"
  umask 022
  {
    printf 'export STATUS_PROJECT=%q\n' "$STATUS_PROJECT"
    printf 'export LDS_COMPOSE_PROJECT=%q\n' "$LDS_COMPOSE_PROJECT"
  } >"$project_env_file"
  chmod 0644 "$project_env_file"
}

init_ai_env() {
  local provider_lib="${LDS_AI_PROVIDER_LIB:-/usr/local/lib/docker-tools/ai-provider.sh}"
  if [[ ! -r "$provider_lib" ]]; then
    echo "[entrypoint] AI provider library missing: $provider_lib" >&2
    exit 70
  fi

  # shellcheck source=/dev/null
  source "$provider_lib"
  if ! ai_config_init; then
    echo '[entrypoint] Invalid LDS_AI_* configuration' >&2
    exit 64
  fi

  export LDS_AI_ENABLED LDS_AI_PROVIDER LDS_AI_URL LDS_AI_MODEL
  export LDS_AI_CONNECT_TIMEOUT LDS_AI_PREFLIGHT_TIMEOUT LDS_AI_TIMEOUT
  export LDS_AI_AVAILABILITY_TTL LDS_AI_MAX_CONTEXT_BYTES LDS_AI_MAX_REQUEST_BYTES LDS_AI_MAX_RESPONSE_BYTES
  export LDS_AI_CACHE_DIR LDS_AI_PROVIDER_LIB
}

init_project_scope
init_ai_env

certify >/dev/null 2>&1 || echo "[entrypoint] Certification failed" >&2
init-php-dirs >/dev/null 2>&1 || echo "[entrypoint] init-php-dirs failed" >&2
git-default >/dev/null 2>&1 || echo "[entrypoint] git-default failed" >&2

if [[ "${ADMIN_PANEL_AUTOSTART:-1}" == "1" ]]; then
  : "${ADMIN_PANEL_BIND:=0.0.0.0}"
  : "${ADMIN_PANEL_PORT:=9911}"
  : "${ADMIN_PANEL_DOCROOT:=/etc/share/admin-panel}"
  : "${ADMIN_PANEL_PHP_SERVER_LOG:=/tmp/admin-panel-php-server.log}"
  : "${ADMIN_PANEL_PID_FILE:=/run/admin-panel.pid}"
  : "${ADMIN_PANEL_TOKEN_FILE:=/run/admin-panel.token}"

  [[ "$ADMIN_PANEL_PORT" =~ ^[0-9]{1,5}$ ]] || {
    echo "[entrypoint] Invalid admin panel port: $ADMIN_PANEL_PORT" >&2
    exit 1
  }

  umask 077
  if [[ -z "${ADMIN_PANEL_TOKEN:-}" ]]; then
    if [[ -s "$ADMIN_PANEL_TOKEN_FILE" ]]; then
      ADMIN_PANEL_TOKEN="$(tr -d '\r\n' <"$ADMIN_PANEL_TOKEN_FILE")"
    else
      ADMIN_PANEL_TOKEN="$(openssl rand -hex 32)"
      printf '%s\n' "$ADMIN_PANEL_TOKEN" >"$ADMIN_PANEL_TOKEN_FILE"
    fi
  else
    printf '%s\n' "$ADMIN_PANEL_TOKEN" >"$ADMIN_PANEL_TOKEN_FILE"
  fi
  chmod 0600 "$ADMIN_PANEL_TOKEN_FILE"
  export ADMIN_PANEL_TOKEN ADMIN_PANEL_TOKEN_FILE
  umask 022

  rm -f -- "$ADMIN_PANEL_PID_FILE"

  if [[ ! -d "$ADMIN_PANEL_DOCROOT" ]]; then
    echo "[entrypoint] Admin panel docroot not found: $ADMIN_PANEL_DOCROOT" >&2
  elif [[ ! -f "$ADMIN_PANEL_DOCROOT/index.php" ]]; then
    echo "[entrypoint] Admin panel index not found: $ADMIN_PANEL_DOCROOT/index.php" >&2
  elif [[ ! -f "$ADMIN_PANEL_DOCROOT/router.php" ]]; then
    echo "[entrypoint] Admin panel router not found: $ADMIN_PANEL_DOCROOT/router.php" >&2
  else
    if ! pgrep -f "php -S ${ADMIN_PANEL_BIND}:${ADMIN_PANEL_PORT}" >/dev/null 2>&1; then
      php -S "${ADMIN_PANEL_BIND}:${ADMIN_PANEL_PORT}" -t "$ADMIN_PANEL_DOCROOT" "$ADMIN_PANEL_DOCROOT/router.php" >>"$ADMIN_PANEL_PHP_SERVER_LOG" 2>&1 &
      printf '%s\n' "$!" >"$ADMIN_PANEL_PID_FILE"
    else
      pgrep -f "php -S ${ADMIN_PANEL_BIND}:${ADMIN_PANEL_PORT}" | head -n 1 >"$ADMIN_PANEL_PID_FILE"
    fi
  fi
else
  rm -f -- "${ADMIN_PANEL_PID_FILE:-/run/admin-panel.pid}" "${ADMIN_PANEL_TOKEN_FILE:-/run/admin-panel.token}"
fi

exec "$@"
