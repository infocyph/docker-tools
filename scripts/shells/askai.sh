#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  askai <prompt>
  askai <file> [instruction]
  <command> | askai [instruction]

Environment:
  AI_MODEL_NAME       Ollama model to use (required)
  ASKAI_CONTEXT_MIN   Minimum context size (default: 2048)
  ASKAI_CONTEXT_MAX   Maximum context size (default: 32768)
  ASKAI_HTTP_TIMEOUT  Request timeout in seconds (default: 600)
EOF
}

die() {
  printf 'askai: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

require_positive_integer() {
  local name="$1"
  local value="$2"

  [[ "$value" =~ ^[1-9][0-9]*$ ]] || die "$name must be a positive integer"
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

require_command curl
require_command jq

model_name="${AI_MODEL_NAME:-}"
api_url="http://127.0.0.1:11434"
context_min="${ASKAI_CONTEXT_MIN:-2048}"
context_max="${ASKAI_CONTEXT_MAX:-32768}"
http_timeout="${ASKAI_HTTP_TIMEOUT:-600}"

[[ -n "$model_name" ]] || die "AI_MODEL_NAME is empty; configure a model before using askai"
require_positive_integer ASKAI_CONTEXT_MIN "$context_min"
require_positive_integer ASKAI_CONTEXT_MAX "$context_max"
require_positive_integer ASKAI_HTTP_TIMEOUT "$http_timeout"
((context_min <= context_max)) || die "ASKAI_CONTEXT_MIN cannot exceed ASKAI_CONTEXT_MAX"

input=""
instruction=""

if [[ ! -t 0 ]]; then
  input="$(cat)"
fi

if [[ -n "${input//[[:space:]]/}" ]]; then
  instruction="$*"
elif (($# > 0)) && [[ -f "$1" ]]; then
  input="$(<"$1")"
  shift
  instruction="$*"
elif (($# > 0)); then
  input="$*"
else
  usage >&2
  die "provide a prompt, a readable file, or piped input"
fi

[[ -n "${input//[[:space:]]/}" ]] || die "input is empty"

if [[ -n "$instruction" ]]; then
  printf -v full_prompt '%s\n\n%s' "$instruction" "$input"
else
  full_prompt="$input"
fi

word_count="$(wc -w <<<"$full_prompt")"
word_count="${word_count//[[:space:]]/}"
estimated_tokens=$(((word_count * 13 + 9) / 10))
context_size=$((estimated_tokens + 500))

((context_size < context_min)) && context_size=$context_min
((context_size > context_max)) && context_size=$context_max

printf '[askai] model=%s context=%s\n' "$model_name" "$context_size" >&2

payload="$(jq -n \
  --arg model "$model_name" \
  --arg prompt "$full_prompt" \
  --argjson context "$context_size" \
  '{model: $model, prompt: $prompt, stream: false, options: {num_ctx: $context}}')"

response=""
if ! response="$(curl \
  --fail-with-body \
  --silent \
  --show-error \
  --connect-timeout 5 \
  --max-time "$http_timeout" \
  --header 'Content-Type: application/json' \
  --data "$payload" \
  "${api_url}/api/generate")"; then
  if jq -e . >/dev/null 2>&1 <<<"$response"; then
    api_error="$(jq -r '.error // empty' <<<"$response")"
    [[ -n "$api_error" ]] && die "Ollama request failed: $api_error"
  fi
  die "Ollama request failed at ${api_url}"
fi

jq -e . >/dev/null 2>&1 <<<"$response" || die "Ollama returned invalid JSON"
api_error="$(jq -r '.error // empty' <<<"$response")"
[[ -z "$api_error" ]] || die "Ollama request failed: $api_error"

jq -er '.response | strings' <<<"$response" || die "Ollama response did not contain generated text"
