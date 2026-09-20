#!/usr/bin/env bash
set -euo pipefail

ROOT="${AI_TEST_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)}"
ASKAI="${AI_ASKAI_BIN:-$ROOT/scripts/shells/askai.sh}"
GITX_WRAPPER="${AI_GITX_WRAPPER:-$ROOT/scripts/shells/gitx-wrapper.sh}"
PROVIDER="${AI_PROVIDER_LIB:-$ROOT/scripts/lib/ai-provider.sh}"
ROUTER="${AI_FAKE_ROUTER:-$ROOT/scripts/tests/fake-llm-router.php}"

fail() {
  printf 'ai-client-smoke: %s\n' "$*" >&2
  exit 1
}

for required in "$ASKAI" "$GITX_WRAPPER" "$PROVIDER" "$ROUTER"; do
  [[ -r "$required" ]] || fail "required test input missing: $required"
done

tmp="$(mktemp -d)"
pid=''
cleanup() {
  [[ -z "$pid" ]] || kill "$pid" >/dev/null 2>&1 || true
  rm -rf -- "$tmp"
}
trap cleanup EXIT INT TERM

mode_file="$tmp/mode"
capture_file="$tmp/capture"
printf 'single\n' >"$mode_file"
: >"$capture_file"

port=$((40000 + RANDOM % 15000))
FAKE_LLM_MODE_FILE="$mode_file" \
FAKE_LLM_CAPTURE_FILE="$capture_file" \
php -S "127.0.0.1:$port" "$ROUTER" >"$tmp/server.log" 2>&1 &
pid=$!

export LDS_AI_PROVIDER_LIB="$PROVIDER"
export LDS_AI_ENABLED=1
export LDS_AI_PROVIDER=llm
export LDS_AI_URL="http://127.0.0.1:$port"
export LDS_AI_MODEL=''
export LDS_AI_THINK=''
export LDS_AI_CONNECT_TIMEOUT=1
export LDS_AI_PREFLIGHT_TIMEOUT=2
export LDS_AI_TIMEOUT=3
export LDS_AI_AVAILABILITY_TTL=1
export LDS_AI_MAX_CONTEXT_BYTES=524288
export LDS_AI_MAX_REQUEST_BYTES=1048576
export LDS_AI_MAX_RESPONSE_BYTES=2097152
export LDS_AI_CACHE_DIR="$tmp/cache"

for _ in $(seq 1 30); do
  if curl -fsS --connect-timeout 1 --max-time 1 "$LDS_AI_URL/v1/models" >/dev/null 2>&1; then
    break
  fi
  kill -0 "$pid" >/dev/null 2>&1 || { cat "$tmp/server.log" >&2; fail 'fake provider exited early'; }
  sleep 0.1
done
curl -fsS --connect-timeout 1 --max-time 1 "$LDS_AI_URL/v1/models" >/dev/null || fail 'fake provider did not start'

printf '1/7 askai prompt + common status\n'
[[ "$(bash "$ASKAI" 'hello')" == ok ]] || fail 'askai prompt failed'
status="$(bash "$ASKAI" --status)"
grep -q '^provider=llm$' <<<"$status" || fail 'askai status did not expose common llm provider'
grep -q '^available=1$' <<<"$status" || fail 'askai status did not report provider available'
grep -q '^model=qwen2.5:3b$' <<<"$status" || fail 'askai status did not resolve deterministic model'
grep -q '^think=auto$' <<<"$status" || fail 'askai status did not expose thinking default'

printf '2/7 askai file/stdin + OpenAI request shape\n'
printf 'file context\n' >"$tmp/context.txt"
[[ "$(bash "$ASKAI" --file "$tmp/context.txt" 'explain file')" == ok ]] || fail 'askai file context failed'
[[ "$(printf 'stdin context\n' | bash "$ASKAI" 'explain stdin')" == ok ]] || fail 'askai stdin context failed'
request_json="$(tail -n 1 "$capture_file" | base64 -d)"
jq -e '.model == "qwen2.5:3b" and .messages[-1].role == "user"' <<<"$request_json" >/dev/null ||
  fail 'common OpenAI request shape drifted'
[[ "$request_json" == *'### Stdin'* ]] || fail 'stdin context label missing from provider request'

printf '3/7 askai per-request thinking + JSON hard-off\n'
[[ "$(bash "$ASKAI" --think 'think request')" == ok ]] || fail 'askai --think failed'
request_json="$(tail -n 1 "$capture_file" | base64 -d)"
jq -e '.think == true and .reasoning_effort == "high"' <<<"$request_json" >/dev/null || fail 'askai --think request fields missing'

[[ "$(bash "$ASKAI" --no-think 'direct request')" == ok ]] || fail 'askai --no-think failed'
request_json="$(tail -n 1 "$capture_file" | base64 -d)"
jq -e '.think == false and .reasoning_effort == "none"' <<<"$request_json" >/dev/null || fail 'askai --no-think request fields missing'

LDS_AI_THINK=true bash "$ASKAI" --think-auto 'provider default' >/dev/null || fail 'askai --think-auto failed'
request_json="$(tail -n 1 "$capture_file" | base64 -d)"
jq -e '((has("think") | not) and (has("reasoning_effort") | not))' <<<"$request_json" >/dev/null || fail 'askai --think-auto did not omit thinking fields'

[[ "$(LDS_AI_THINK=true bash "$ASKAI" --json 'return json')" == '{"ok":true}' ]] || fail 'askai JSON mode failed'
request_json="$(tail -n 1 "$capture_file" | base64 -d)"
jq -e '.think == false and .reasoning_effort == "none"' <<<"$request_json" >/dev/null || fail 'askai JSON mode did not force thinking off'

printf '4/7 sensitive input refusal\n'
printf 'SECRET=value\n' >"$tmp/.env"
set +e
bash "$ASKAI" --file "$tmp/.env" explain >"$tmp/out" 2>"$tmp/err"
rc=$?
set -e
[[ "$rc" -eq 77 ]] || fail "askai sensitive file returned $rc instead of 77"

printf '5/7 gitx ai-commit delegates to Toolset local-only\n'
cat >"$tmp/gitx-real" <<'STUB'
#!/usr/bin/env bash
printf 'provider=%s\n' "${GITX_AI_PROVIDER:-}"
printf 'ollama_url=%s\n' "${GITX_OLLAMA_URL:-}"
printf 'model=%s\n' "${GITX_OLLAMA_MODEL:-}"
printf 'gemini_key=%s\n' "${GEMINI_API_KEY+x}"
printf 'args=%s\n' "$*"
STUB
chmod 700 "$tmp/gitx-real"
export GITX_TOOLSET_BIN="$tmp/gitx-real"
export GEMINI_API_KEY='must-not-reach-toolset'
rm -rf -- "$LDS_AI_CACHE_DIR"

wrapper_out="$(bash "$GITX_WRAPPER" ai-commit --dry-run)"
grep -q '^provider=ollama$' <<<"$wrapper_out" || fail 'gitx wrapper did not force Toolset local Ollama mode'
grep -q "^ollama_url=$LDS_AI_URL$" <<<"$wrapper_out" || fail 'gitx wrapper did not map the LocalDevStack llm URL'
grep -q '^model=qwen2.5:3b$' <<<"$wrapper_out" || fail 'gitx wrapper did not pin deterministic model'
grep -q '^gemini_key=$' <<<"$wrapper_out" || fail 'gitx wrapper leaked Gemini credentials to Toolset'
grep -q '^args=ai-commit --dry-run$' <<<"$wrapper_out" || fail 'gitx wrapper changed Toolset ai-commit arguments'

printf '6/7 gitx model ambiguity fails before Toolset\n'
printf 'ambiguous\n' >"$mode_file"
rm -rf -- "$LDS_AI_CACHE_DIR"
set +e
bash "$GITX_WRAPPER" ai-commit --dry-run >"$tmp/out" 2>"$tmp/err"
rc=$?
set -e
[[ "$rc" -eq 78 ]] || fail "ambiguous gitx model returned $rc instead of 78"
grep -q 'multiple installed models' "$tmp/err" || fail 'gitx ambiguity error missing'
printf 'single\n' >"$mode_file"

printf '7/7 non-AI gitx commands remain transparent\n'
non_ai="$(bash "$GITX_WRAPPER" --version)"
grep -q '^args=--version$' <<<"$non_ai" || fail 'non-AI gitx command was not delegated unchanged'

printf 'ai-client-smoke: ok\n'
