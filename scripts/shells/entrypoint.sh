#!/bin/bash
set -euo pipefail

OLLAMA_PID=""
COMMAND_PID=""

entrypoint_log() {
  printf '[entrypoint] %s\n' "$*" >&2
}

enabled() {
  case "${1,,}" in
    1|true|yes|on) return 0 ;;
    *) return 1 ;;
  esac
}

stop_child() {
  local pid="${1:-}"

  if [[ -n "$pid" ]] && kill -0 "$pid" >/dev/null 2>&1; then
    kill -TERM "$pid" >/dev/null 2>&1 || true
  fi
}

cleanup_children() {
  stop_child "$COMMAND_PID"
  stop_child "$OLLAMA_PID"

  [[ -n "$COMMAND_PID" ]] && wait "$COMMAND_PID" 2>/dev/null || true
  [[ -n "$OLLAMA_PID" ]] && wait "$OLLAMA_PID" 2>/dev/null || true
}

forward_signal() {
  local signal="$1"

  [[ -n "$COMMAND_PID" ]] && kill -s "$signal" "$COMMAND_PID" >/dev/null 2>&1 || true
  [[ -n "$OLLAMA_PID" ]] && kill -s "$signal" "$OLLAMA_PID" >/dev/null 2>&1 || true
}

wait_for_ollama() {
  local api_url="$1"
  local timeout="$2"
  local attempt

  for ((attempt = 1; attempt <= timeout; attempt++)); do
    if curl --fail --silent --show-error \
      --connect-timeout 1 \
      --max-time 2 \
      "${api_url}/api/tags" >/dev/null 2>&1; then
      return 0
    fi

    if ! kill -0 "$OLLAMA_PID" >/dev/null 2>&1; then
      entrypoint_log "Ollama exited before becoming ready."
      wait "$OLLAMA_PID" || true
      return 1
    fi

    sleep 1
  done

  entrypoint_log "Ollama did not become ready within ${timeout}s."
  return 1
}

ollama_has_model() {
  local api_url="$1"
  local model_name="$2"

  curl --fail --silent --show-error \
    --connect-timeout 1 \
    --max-time 5 \
    "${api_url}/api/tags" \
    | jq --exit-status --arg model "$model_name" \
      'any(.models[]?; .name == $model or .model == $model)' >/dev/null
}

start_ollama() {
  local api_url="${OLLAMA_API_URL:-http://127.0.0.1:11434}"
  local model_name="${AI_MODEL_NAME:-}"
  local ready_timeout="${OLLAMA_READY_TIMEOUT:-120}"

  if [[ -z "$model_name" ]]; then
    entrypoint_log "AI_MODEL_NAME is empty; skipping Ollama startup."
    return 0
  fi

  if ! enabled "${OLLAMA_AUTOSTART:-1}"; then
    entrypoint_log "Ollama autostart is disabled."
    return 0
  fi

  if ! command -v ollama >/dev/null 2>&1; then
    entrypoint_log "Ollama autostart requested, but the ollama command is unavailable."
    return 1
  fi

  if [[ ! "$ready_timeout" =~ ^[1-9][0-9]*$ ]]; then
    entrypoint_log "Invalid OLLAMA_READY_TIMEOUT '${ready_timeout}'; using 120s."
    ready_timeout=120
  fi

  entrypoint_log "Starting Ollama daemon."
  ollama serve &
  OLLAMA_PID=$!
  trap cleanup_children EXIT

  entrypoint_log "Waiting for Ollama at ${api_url}."
  wait_for_ollama "$api_url" "$ready_timeout"

  if ollama_has_model "$api_url" "$model_name"; then
    entrypoint_log "Model '${model_name}' is ready."
    return 0
  fi

  entrypoint_log "Model '${model_name}' is missing; pulling it now."
  OLLAMA_HOST="$api_url" ollama pull "$model_name"
  entrypoint_log "Model '${model_name}' is ready."
}

HOST_OS="$(printf '%s' "${HOST_OS:-linux}" | tr '[:upper:]' '[:lower:]')" && export HOST_OS
certify >/dev/null 2>&1 || echo "[entrypoint] Certification failed" >&2
init-php-dirs >/dev/null 2>&1 || echo "[entrypoint] init-php-dirs failed" >&2
git-default >/dev/null 2>&1 || echo "[entrypoint] git-default failed" >&2

start_ollama

if [[ "${ADMIN_PANEL_AUTOSTART:-1}" == "1" ]]; then
  : "${ADMIN_PANEL_BIND:=0.0.0.0}"
  : "${ADMIN_PANEL_PORT:=9911}"
  : "${ADMIN_PANEL_DOCROOT:=/etc/share/admin-panel}"
  : "${ADMIN_PANEL_PHP_SERVER_LOG:=/tmp/admin-panel-php-server.log}"

  if [[ ! -d "$ADMIN_PANEL_DOCROOT" ]]; then
    echo "[entrypoint] Admin panel docroot not found: $ADMIN_PANEL_DOCROOT" >&2
  elif [[ ! -f "$ADMIN_PANEL_DOCROOT/index.php" ]]; then
    echo "[entrypoint] Admin panel index not found: $ADMIN_PANEL_DOCROOT/index.php" >&2
  elif [[ ! -f "$ADMIN_PANEL_DOCROOT/router.php" ]]; then
    echo "[entrypoint] Admin panel router not found: $ADMIN_PANEL_DOCROOT/router.php" >&2
  else
    if ! pgrep -f "php -S ${ADMIN_PANEL_BIND}:${ADMIN_PANEL_PORT}" >/dev/null 2>&1; then
      php -S "${ADMIN_PANEL_BIND}:${ADMIN_PANEL_PORT}" -t "$ADMIN_PANEL_DOCROOT" "$ADMIN_PANEL_DOCROOT/router.php" >>"$ADMIN_PANEL_PHP_SERVER_LOG" 2>&1 &
    fi
  fi
fi

if [[ -z "$OLLAMA_PID" ]]; then
  exec "$@"
fi

"$@" <&0 &
COMMAND_PID=$!

trap 'forward_signal TERM' TERM
trap 'forward_signal INT' INT
trap 'forward_signal HUP' HUP

set +e
wait -n "$OLLAMA_PID" "$COMMAND_PID"
exit_status=$?
set -e

if kill -0 "$COMMAND_PID" >/dev/null 2>&1; then
  entrypoint_log "Ollama stopped; terminating the main command."
else
  entrypoint_log "Main command stopped; terminating Ollama."
fi

cleanup_children
trap - EXIT TERM INT HUP
exit "$exit_status"
