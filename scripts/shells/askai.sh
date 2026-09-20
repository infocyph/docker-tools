#!/usr/bin/env bash
set -euo pipefail

resolve_provider_lib() {
  local configured="${LDS_AI_PROVIDER_LIB:-}" script_dir
  if [[ -n "$configured" && -r "$configured" ]]; then
    printf '%s\n' "$configured"
    return 0
  fi
  if [[ -r /usr/local/lib/docker-tools/ai-provider.sh ]]; then
    printf '%s\n' /usr/local/lib/docker-tools/ai-provider.sh
    return 0
  fi
  script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
  if [[ -r "$script_dir/../lib/ai-provider.sh" ]]; then
    printf '%s\n' "$script_dir/../lib/ai-provider.sh"
    return 0
  fi
  return 1
}

PROVIDER_LIB="$(resolve_provider_lib)" || {
  echo 'askai: AI provider library not found' >&2
  exit 70
}
# shellcheck source=/dev/null
source "$PROVIDER_LIB"

usage() {
  cat <<'USAGE'
Usage: askai [options] [prompt...]

Pure LocalDevStack AI client. The common provider endpoint defaults to http://llm:11434.

Options:
  -f, --file PATH       Add a non-sensitive text file as untrusted context.
      --stdin           Read stdin as untrusted context even when attached to a TTY.
  -s, --system TEXT     Add user-provided system guidance after the fixed safety guard.
  -m, --model MODEL     Override LDS_AI_MODEL for this request.
      --json            Request a valid JSON response.
      --stream          Stream response chunks; generation is never replayed after output.
      --status          Show provider availability/model status without generating.
  -h, --help            Show this help.

Input rules:
  * Piped stdin is consumed automatically.
  * .env, private keys, credentials/secrets files, and P12/PFX files are refused.
  * Context/request/response byte limits come from LDS_AI_MAX_* variables.
  * Known credential values are redacted before the provider request is built.
USAGE
}

file=''
force_stdin=0
system_text=''
model_override=''
json_mode=0
stream=0
status_only=0
prompt_parts=()

while (($# > 0)); do
  case "$1" in
    -f|--file)
      (($# >= 2)) || { echo "askai: missing value for $1" >&2; exit 64; }
      file="$2"
      shift 2
      ;;
    --stdin)
      force_stdin=1
      shift
      ;;
    -s|--system)
      (($# >= 2)) || { echo "askai: missing value for $1" >&2; exit 64; }
      system_text="$2"
      shift 2
      ;;
    -m|--model)
      (($# >= 2)) || { echo "askai: missing value for $1" >&2; exit 64; }
      model_override="$2"
      shift 2
      ;;
    --json)
      json_mode=1
      shift
      ;;
    --stream)
      stream=1
      shift
      ;;
    --status)
      status_only=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      prompt_parts+=("$@")
      break
      ;;
    -*)
      echo "askai: unknown option: $1" >&2
      exit 64
      ;;
    *)
      prompt_parts+=("$1")
      shift
      ;;
  esac
done

if [[ -n "$model_override" ]]; then
  LDS_AI_MODEL="$model_override"
  export LDS_AI_MODEL
fi

ai_config_init || exit $?

if ((status_only)); then
  printf 'enabled=%s\nprovider=%s\nurl=%s\n' "$LDS_AI_ENABLED" "$LDS_AI_PROVIDER" "$LDS_AI_URL"
  if [[ "$LDS_AI_ENABLED" == 0 ]]; then
    printf 'available=0\nmodel=\n'
    exit 0
  fi
  if ai_available; then
    printf 'available=1\n'
    if selected_model="$(ai_model 2>/dev/null)"; then
      printf 'model=%s\n' "$selected_model"
      exit 0
    fi
    printf 'model=ambiguous_or_unavailable\n'
    exit 78
  fi
  printf 'available=0\nmodel=\n'
  exit 69
fi

context_tmp="$(mktemp "${TMPDIR:-/tmp}/askai-context.XXXXXX")"
chmod 600 "$context_tmp"
cleanup() {
  rm -f -- "$context_tmp"
}
trap cleanup EXIT INT TERM

append_context_file() {
  local label="$1" path="$2" size current
  ai_assert_safe_file "$path" || return $?
  size="$(wc -c <"$path" | tr -d '[:space:]')"
  ai_is_uint "$size" || { echo "askai: cannot determine size for $path" >&2; return 65; }
  current="$(wc -c <"$context_tmp" | tr -d '[:space:]')"
  if ((10#$current + 10#$size > 10#$LDS_AI_MAX_CONTEXT_BYTES)); then
    echo "askai: combined context exceeds LDS_AI_MAX_CONTEXT_BYTES=$LDS_AI_MAX_CONTEXT_BYTES" >&2
    return 65
  fi
  printf '### %s\n' "$label" >>"$context_tmp"
  cat -- "$path" >>"$context_tmp"
  printf '\n' >>"$context_tmp"
}

if [[ -n "$file" ]]; then
  append_context_file "File: $file" "$file"
fi

read_stdin=0
if ((force_stdin)); then
  read_stdin=1
elif [[ ! -t 0 ]] && read -r -t 0; then
  read_stdin=1
fi

if ((read_stdin)); then
  stdin_tmp="$(mktemp "${TMPDIR:-/tmp}/askai-stdin.XXXXXX")"
  chmod 600 "$stdin_tmp"
  head -c "$((10#$LDS_AI_MAX_CONTEXT_BYTES + 1))" >"$stdin_tmp"
  stdin_size="$(wc -c <"$stdin_tmp" | tr -d '[:space:]')"
  if ! ai_is_uint "$stdin_size" || ((10#$stdin_size > 10#$LDS_AI_MAX_CONTEXT_BYTES)); then
    rm -f -- "$stdin_tmp"
    echo "askai: stdin exceeds LDS_AI_MAX_CONTEXT_BYTES=$LDS_AI_MAX_CONTEXT_BYTES" >&2
    exit 65
  fi
  append_context_file 'Stdin' "$stdin_tmp"
  rm -f -- "$stdin_tmp"
fi

prompt=''
if ((${#prompt_parts[@]} > 0)); then
  printf -v prompt '%s ' "${prompt_parts[@]}"
  prompt="${prompt% }"
fi

context="$(cat -- "$context_tmp")"
if [[ -z "$prompt" ]]; then
  if [[ -n "$context" ]]; then
    prompt='Analyze the supplied context and provide the most useful concise explanation.'
  else
    usage >&2
    exit 64
  fi
fi

if ((stream)); then
  ai_stream_context "$prompt" "$context" "$system_text" "$json_mode"
elif ((json_mode)); then
  ai_generate_context_json "$prompt" "$context" "$system_text"
else
  ai_generate_context "$prompt" "$context" "$system_text"
fi
