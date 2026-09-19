#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

fail() {
  printf 'ai-contract: %s\n' "$*" >&2
  exit 1
}

PROVIDER='scripts/lib/ai-provider.sh'
ASKAI='scripts/shells/askai.sh'
GITX='scripts/shells/gitx-wrapper.sh'
ENTRYPOINT='scripts/shells/entrypoint.sh'
HEALTH='scripts/shells/tools-healthcheck.sh'

for file in "$PROVIDER" "$ASKAI" "$GITX" "$ENTRYPOINT" "$HEALTH"; do
  [[ -s "$file" ]] || fail "missing AI contract input: $file"
done

if grep -REn --exclude='docker-tools-hardening-ai-plan.md' --exclude='ai-contract.sh' \
  'ollama[[:space:]]+serve|ollama[[:space:]]+pull|ollama/ollama|EXPOSE[[:space:]]+11434' \
  Dockerfile scripts .github 2>/dev/null; then
  fail 'embedded Ollama runtime/lifecycle contract reappeared'
fi

grep -q 'LDS_AI_URL=http://llm-ollama:11434' Dockerfile || fail 'Docker image AI URL default is not llm-ollama:11434'
grep -q 'LDS_AI_URL:=http://llm-ollama:11434' "$PROVIDER" || fail 'provider AI URL default is not llm-ollama:11434'
if grep -R -n 'https://llm\.localhost' "$PROVIDER" "$ASKAI" "$GITX" "$ENTRYPOINT"; then
  fail 'container-side AI client references user-facing llm-ollama.localhost route'
fi

grep -q 'LDS_AI_PROVIDER:=ollama' "$PROVIDER" || fail 'Ollama provider default missing'
grep -q 'unsupported LDS_AI_PROVIDER' "$PROVIDER" || fail 'unsupported provider guard missing'
if grep -REn 'api\.openai\.com|generativelanguage\.googleapis\.com|anthropic\.com' "$PROVIDER" "$ASKAI"; then
  fail 'implicit external AI provider endpoint added'
fi

grep -q 'GITX_AI_PROVIDER=ollama' "$GITX" || fail 'gitx wrapper does not force local Ollama'
grep -q 'GITX_OLLAMA_URL="$LDS_AI_URL"' "$GITX" || fail 'gitx wrapper does not map LocalDevStack AI URL'
grep -q 'selected_model="$(ai_model)"' "$GITX" || fail 'gitx wrapper does not enforce deterministic model selection'
grep -q '/usr/local/libexec/gitx-toolset' "$GITX" || fail 'gitx Toolset delegation path missing'
grep -q 'mv /usr/local/bin/gitx /usr/local/libexec/gitx-toolset' Dockerfile || fail 'Toolset gitx binary is not preserved behind wrapper'

grep -q 'LDS_AI_CONNECT_TIMEOUT' "$PROVIDER" || fail 'separate AI connect timeout missing'
grep -q 'LDS_AI_PREFLIGHT_TIMEOUT' "$PROVIDER" || fail 'separate AI preflight timeout missing'
grep -q 'LDS_AI_TIMEOUT' "$PROVIDER" || fail 'AI generation timeout missing'
grep -Fq 'LDS_AI_TIMEOUT:=1800' "$PROVIDER" || fail 'AI generation timeout default is not 1800 seconds'
grep -q 'LDS_AI_AVAILABILITY_TTL' "$PROVIDER" || fail 'AI availability cache TTL missing'
grep -q 'LDS_AI_MAX_CONTEXT_BYTES' "$PROVIDER" || fail 'AI context bound missing'
grep -q 'LDS_AI_MAX_REQUEST_BYTES' "$PROVIDER" || fail 'AI request bound missing'
grep -q 'LDS_AI_MAX_RESPONSE_BYTES' "$PROVIDER" || fail 'AI response bound missing'
grep -q 'multiple installed models are available' "$PROVIDER" || fail 'ambiguous-model fail-closed behavior missing'
grep -q 'generation was not retried' "$PROVIDER" || fail 'stream no-replay contract missing'
grep -q '<untrusted-data>' "$PROVIDER" || fail 'untrusted-data prompt boundary missing'
grep -q 'ai_redact' "$PROVIDER" || fail 'AI redaction layer missing'
grep -q 'ai_assert_safe_file' "$ASKAI" || fail 'askai sensitive-file guard missing'

grep -q 'init_ai_env' "$ENTRYPOINT" || fail 'entrypoint AI config initialization missing'
if grep -Eq 'ai_available|/api/tags|/api/generate' "$ENTRYPOINT"; then
  fail 'entrypoint probes optional AI provider during Tools startup'
fi
if grep -Eq 'LDS_AI|llm-ollama|askai' "$HEALTH"; then
  fail 'Tools health was coupled to optional AI availability'
fi

printf 'ai-contract: ok\n'
