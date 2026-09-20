#!/usr/bin/env bash
set -euo pipefail

ROOT="${AI_TEST_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)}"
ASKAI="${AI_ASKAI_BIN:-$ROOT/scripts/shells/askai.sh}"
GITX_WRAPPER="${AI_GITX_WRAPPER:-$ROOT/scripts/shells/gitx-wrapper.sh}"
GITX_AI_COMMIT="${AI_GITX_AI_COMMIT_BIN:-$ROOT/scripts/shells/gitx-ai-commit.sh}"
PROVIDER="${AI_PROVIDER_LIB:-$ROOT/scripts/lib/ai-provider.sh}"
ROUTER="${AI_FAKE_ROUTER:-$ROOT/scripts/tests/fake-llm-router.php}"
PROMPT="${AI_COMMIT_PROMPT:-$ROOT/scripts/prompts/ai-commit.txt}"

fail() {
  printf 'ai-client-smoke: %s\n' "$*" >&2
  exit 1
}

for required in "$ASKAI" "$GITX_WRAPPER" "$GITX_AI_COMMIT" "$PROVIDER" "$ROUTER" "$PROMPT"; do
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

printf '1/6 askai prompt + common status\n'
[[ "$(bash "$ASKAI" 'hello')" == ok ]] || fail 'askai prompt failed'
status="$(bash "$ASKAI" --status)"
grep -q '^provider=llm$' <<<"$status" || fail 'askai status did not expose common llm provider'
grep -q '^available=1$' <<<"$status" || fail 'askai status did not report provider available'
grep -q '^model=qwen2.5:3b$' <<<"$status" || fail 'askai status did not resolve deterministic model'

printf '2/6 askai file/stdin + OpenAI request shape\n'
printf 'file context\n' >"$tmp/context.txt"
[[ "$(bash "$ASKAI" --file "$tmp/context.txt" 'explain file')" == ok ]] || fail 'askai file context failed'
[[ "$(printf 'stdin context\n' | bash "$ASKAI" 'explain stdin')" == ok ]] || fail 'askai stdin context failed'
request_json="$(tail -n 1 "$capture_file" | base64 -d)"
jq -e '.model == "qwen2.5:3b" and .messages[-1].role == "user"' <<<"$request_json" >/dev/null ||
  fail 'common OpenAI request shape drifted'
[[ "$request_json" == *'### Stdin'* ]] || fail 'stdin context label missing from provider request'

printf '3/6 JSON + sensitive input refusal\n'
[[ "$(bash "$ASKAI" --json 'return json')" == '{"ok":true}' ]] || fail 'askai JSON mode failed'
printf 'SECRET=value\n' >"$tmp/.env"
set +e
bash "$ASKAI" --file "$tmp/.env" explain >"$tmp/out" 2>"$tmp/err"
rc=$?
set -e
[[ "$rc" -eq 77 ]] || fail "askai sensitive file returned $rc instead of 77"

printf '4/6 provider-neutral gitx ai-commit\n'
repo="$tmp/repo"
mkdir -p "$repo"
git -C "$repo" init -q
git -C "$repo" config user.email smoke@example.invalid
git -C "$repo" config user.name smoke
printf 'base\n' >"$repo/file.txt"
git -C "$repo" add file.txt
git -C "$repo" commit -qm init
printf 'change\n' >>"$repo/file.txt"
git -C "$repo" add file.txt

export GITX_AI_COMMIT_BIN="$GITX_AI_COMMIT"
export GITX_AI_COMMIT_PROMPT_FILE="$PROMPT"
rm -rf -- "$LDS_AI_CACHE_DIR"
gitx_out="$(cd "$repo" && printf 'n\n' | bash "$GITX_WRAPPER" ai-commit)"
grep -q 'Generated Commit Message' <<<"$gitx_out" || fail 'gitx common llm commit generation failed'
grep -q 'Commit cancelled' <<<"$gitx_out" || fail 'gitx common llm interactive flow drifted'
[[ "$(git -C "$repo" status --short)" == 'M  file.txt' ]] || fail 'gitx cancellation changed staged state'

printf '5/6 common gitx fails closed on ambiguous model\n'
printf 'ambiguous\n' >"$mode_file"
rm -rf -- "$LDS_AI_CACHE_DIR"
set +e
(cd "$repo" && printf 'n\n' | bash "$GITX_WRAPPER" ai-commit) >"$tmp/out" 2>"$tmp/err"
rc=$?
set -e
[[ "$rc" -eq 78 ]] || fail "ambiguous gitx model returned $rc instead of 78"
grep -q 'multiple installed models' "$tmp/err" || fail 'gitx ambiguity error missing'
printf 'single\n' >"$mode_file"

printf '6/6 non-AI gitx commands remain transparent\n'
cat >"$tmp/gitx-real" <<'STUB'
#!/usr/bin/env bash
printf 'args=%s\n' "$*"
STUB
chmod 700 "$tmp/gitx-real"
export GITX_TOOLSET_BIN="$tmp/gitx-real"
non_ai="$(bash "$GITX_WRAPPER" --version)"
grep -q '^args=--version$' <<<"$non_ai" || fail 'non-AI gitx command was not delegated unchanged'

printf 'ai-client-smoke: ok\n'
