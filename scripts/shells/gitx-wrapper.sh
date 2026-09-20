#!/usr/bin/env bash
set -euo pipefail

REAL_GITX="${GITX_TOOLSET_BIN:-/usr/local/libexec/gitx-toolset}"
[[ -x "$REAL_GITX" ]] || { echo "gitx: Toolset binary missing: $REAL_GITX" >&2; exit 127; }

if [[ "${1:-}" == 'ai-commit' ]]; then
  PROVIDER_LIB="${LDS_AI_PROVIDER_LIB:-/usr/local/lib/docker-tools/ai-provider.sh}"
  [[ -r "$PROVIDER_LIB" ]] || { echo "gitx: AI provider library missing: $PROVIDER_LIB" >&2; exit 70; }

  # shellcheck source=/dev/null
  source "$PROVIDER_LIB"
  ai_config_init || exit $?

  if [[ "$LDS_AI_ENABLED" == 0 ]]; then
    echo 'gitx: AI is disabled by LDS_AI_ENABLED=0' >&2
    exit 69
  fi

  # Toolset owns ai-commit. Its current local provider contract is Ollama/Gemini,
  # not generic OpenAI. Force the local Ollama path so Toolset can never fall back
  # to Gemini/cloud from LocalDevStack. If the active common llm backend is
  # FastFlow, Toolset ai-commit will fail locally until Toolset gains an OpenAI
  # provider; docker-tools must not duplicate that implementation.
  export GITX_AI_PROVIDER=ollama
  export GITX_OLLAMA_URL="$LDS_AI_URL"
  unset GEMINI_API_KEY

  selected_model="$(ai_model)" || exit $?
  export GITX_OLLAMA_MODEL="$selected_model"
  export OLLAMA_MODEL="$selected_model"
fi

exec "$REAL_GITX" "$@"
