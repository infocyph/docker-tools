#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

fail() {
  printf 'ai-intelligence-contract: %s\n' "$*" >&2
  exit 1
}

AIOPS='scripts/shells/aiops.sh'
PROVIDER='scripts/lib/ai-provider.sh'
SERVICE='scripts/admin-panel/src/Service/AiAssistantService.php'
ENDPOINT='scripts/admin-panel/src/Api/AiAssistantEndpoint.php'
KERNEL='scripts/admin-panel/src/App/Kernel.php'
ROUTER='scripts/admin-panel/src/Routing/Router.php'
PAGE='scripts/admin-panel/app/pages/ai_assistant.php'

for file in "$AIOPS" "$PROVIDER" "$SERVICE" "$ENDPOINT" "$KERNEL" "$ROUTER" "$PAGE"; do
  [[ -s "$file" ]] || fail "missing intelligence contract input: $file"
done

grep -Fq "rg -a -q '\\x00' -- \"\$path\"" "$PROVIDER" || fail 'AI binary guard is not using exact ripgrep NUL detection'

for collector in status monitor-alerts monitor-slo monitor-db monitor-queue monitor-tls monitor-volumes monitor-drift monitor-log-heatmap; do
  grep -q "$collector" "$AIOPS" || fail "aiops collector missing: $collector"
done
grep -Fq 'timeout "${timeout_sec}s" "${cmd[@]}"' "$AIOPS" || fail 'aiops collectors are not bounded by fixed argv timeout'
grep -q 'ai_redact' "$AIOPS" || fail 'aiops redaction missing'
grep -q 'ai_assert_safe_file' "$AIOPS" || fail 'aiops safe-file boundary missing'
grep -q 'ai_generate_context' "$AIOPS" || fail 'aiops does not reuse provider context boundary'
grep -q -- '--context-only' "$AIOPS" || fail 'aiops context preview mode missing'
grep -q 'repository-metadata' "$AIOPS" || fail 'repository metadata review helper missing'
grep -q 'graphify' "$AIOPS" || fail 'Graphify analysis helper missing'
grep -q 'document-review' "$AIOPS" || fail 'document-review command missing'
grep -q 'docker-tools.docstruct-context/v1' "$AIOPS" || fail 'document-review bounded context contract missing'
grep -q 'ai_generate_context_json' "$AIOPS" || fail 'document-review strict JSON generation missing'
grep -q 'aiops_generate_document_patch' "$AIOPS" || fail 'document-review JSON retry helper missing'
grep -q 'structured generation failed; retrying once' "$AIOPS" || fail 'document-review bounded retry diagnostic missing'
grep -q -- '--think)' "$AIOPS" || fail 'aiops thinking-on override missing'
grep -q -- '--no-think)' "$AIOPS" || fail 'aiops thinking-off override missing'
grep -q -- '--think-auto)' "$AIOPS" || fail 'aiops provider-default thinking override missing'
if grep -Eq '(^|[[:space:]])eval([[:space:]]|$)|bash[[:space:]]+-c|sh[[:space:]]+-c' "$AIOPS"; then
  fail 'aiops introduced command-string execution'
fi
grep -Fq 'diff --no-ext-diff --stat' "$AIOPS" || fail 'repo-review diff stat contract missing'
grep -Fq 'diff --no-ext-diff --name-status' "$AIOPS" || fail 'repo-review unstaged metadata contract missing'
grep -Fq 'diff --cached --no-ext-diff --name-status' "$AIOPS" || fail 'repo-review staged metadata contract missing'
if grep -q -- '--patch' "$AIOPS" || grep -Eq 'git[[:space:]].*show([[:space:]]|$)' "$AIOPS"; then
  fail 'repo-review started sending repository content implicitly'
fi

grep -q 'ProcessRunner::run' "$SERVICE" || fail 'admin AI service bypasses ProcessRunner'
grep -q 'DEFAULT_ANALYSIS_TIMEOUT_SECONDS = 1800' "$SERVICE" || fail 'admin AI long-generation default missing'
grep -q "getenv('LDS_AI_TIMEOUT')" "$SERVICE" || fail 'admin AI does not share the provider generation timeout'
if grep -Eq 'ANALYSIS_TIMEOUT_SECONDS = 45|45000|45-second UI bound' "$SERVICE" "$PAGE"; then
  fail 'legacy 45-second admin AI timeout reappeared'
fi
grep -q "source === 'troubleshoot'" "$SERVICE" || fail 'admin troubleshooting action missing'
grep -q 'normalizeThinkRequest' "$SERVICE" || fail 'admin request-level thinking normalization missing'
grep -q -- "--think'" "$SERVICE" || fail 'admin thinking-on CLI mapping missing'
grep -q -- "--no-think'" "$SERVICE" || fail 'admin thinking-off CLI mapping missing'
grep -q -- "--think-auto'" "$SERVICE" || fail 'admin provider-default thinking CLI mapping missing'
grep -q "REQUEST_METHOD" "$ENDPOINT" || fail 'admin AI endpoint method gate missing'
grep -q "method === 'POST'" "$ENDPOINT" || fail 'admin AI generation is not POST-only'
grep -q "'/api/ai-assistant'" "$KERNEL" || fail 'admin AI API route missing'
grep -q "'ai-assistant'" "$ROUTER" || fail 'admin AI page route missing'
grep -q 'AbortController' "$PAGE" || fail 'admin AI cancellation UX missing'
grep -q 'Run Analysis' "$PAGE" || fail 'admin AI action is not explicit'
grep -q 'Context Sent' "$PAGE" || fail 'admin AI context disclosure missing'
grep -q 'id="aiThink"' "$PAGE" || fail 'admin request-level thinking selector missing'
grep -q 'think: think.value' "$PAGE" || fail 'admin UI does not send thinking mode per request'

grep -q 'COPY scripts/shells/aiops.sh /usr/local/bin/aiops' Dockerfile || fail 'aiops is not installed in image'
grep -q '/usr/local/bin/aiops' Dockerfile || fail 'aiops executable contract missing'

printf 'ai-intelligence-contract: ok\n'
