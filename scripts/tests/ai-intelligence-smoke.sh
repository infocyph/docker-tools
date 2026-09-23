#!/usr/bin/env bash
set -euo pipefail

ROOT="${AI_TEST_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)}"
AIOPS="${AI_AIOPS_BIN:-$ROOT/scripts/shells/aiops.sh}"
ASKAI="${AI_ASKAI_BIN:-$ROOT/scripts/shells/askai.sh}"
PROVIDER="${AI_PROVIDER_LIB:-$ROOT/scripts/lib/ai-provider.sh}"
ROUTER="${AI_FAKE_ROUTER:-$ROOT/scripts/tests/fake-llm-router.php}"
ADMIN_BOOTSTRAP="${AI_ADMIN_BOOTSTRAP:-$ROOT/scripts/admin-panel/app/bootstrap.php}"

fail() {
  printf 'ai-intelligence-smoke: %s\n' "$*" >&2
  exit 1
}

for path in "$AIOPS" "$ASKAI" "$PROVIDER" "$ROUTER"; do
  [[ -r "$path" ]] || fail "required test input missing: $path"
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
export LDS_AI_RUNTIME=cpu
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
export LDS_AIOPS_COLLECT_TIMEOUT=2
export AI_ADMIN_AIOPS_TARGET="$AIOPS"
export AI_ADMIN_ASKAI_TARGET="$ASKAI"

mkdir -p "$tmp/admin-bin"
cat >"$tmp/admin-bin/aiops" <<'WRAP'
#!/usr/bin/env bash
exec bash "$AI_ADMIN_AIOPS_TARGET" "$@"
WRAP
cat >"$tmp/admin-bin/askai" <<'WRAP'
#!/usr/bin/env bash
exec bash "$AI_ADMIN_ASKAI_TARGET" "$@"
WRAP
chmod 700 "$tmp/admin-bin/aiops" "$tmp/admin-bin/askai"
export ADMIN_PANEL_AIOPS_BIN="$tmp/admin-bin/aiops"
export ADMIN_PANEL_ASKAI_BIN="$tmp/admin-bin/askai"

for _ in $(seq 1 30); do
  if curl -fsS --connect-timeout 1 --max-time 1 "$LDS_AI_URL/v1/models" >/dev/null 2>&1; then
    break
  fi
  kill -0 "$pid" >/dev/null 2>&1 || { cat "$tmp/server.log" >&2; fail 'fake provider exited early'; }
  sleep 0.1
done
curl -fsS --connect-timeout 1 --max-time 1 "$LDS_AI_URL/v1/models" >/dev/null || fail 'fake provider did not start'

mkdir -p "$tmp/bin"
cat >"$tmp/bin/collector" <<'STUB'
#!/usr/bin/env bash
name="$(basename "$0")"
case "$name" in
  status)
    printf '%s\n' '{"ok":true,"project":"smoke","summary":{"healthy":7,"unhealthy":1},"api_key":"super-secret-value"}'
    ;;
  monitor-alerts)
    printf '%s\n' '{"ok":true,"summary":{"firing":1},"incidents":[{"id":"db_fail","firing":true}]}'
    ;;
  monitor-slo)
    printf '%s\n' '{"ok":true,"summary":{"fail":1,"pass":3}}'
    ;;
  monitor-db)
    printf '%s\n' '{"ok":true,"summary":{"fail":1},"items":[{"engine":"redis","level":"fail"}],"token":"secret-token-value"}'
    ;;
  monitor-queue)
    printf '%s\n' '{"ok":true,"summary":{"fail":0,"warn":1}}'
    ;;
  monitor-tls)
    printf '%s\n' '{"ok":true,"summary":{"fail":0,"warn":1}}'
    ;;
  monitor-volumes)
    printf '%s\n' '{"ok":true,"summary":{"fail":0,"warn":1}}'
    ;;
  monitor-drift)
    printf '%s\n' '{"ok":true,"summary":{"fail":0,"warn":1}}'
    ;;
  monitor-log-heatmap)
    printf '%s\n' '{"ok":true,"summary":{"errors":4},"top":[{"signature":"timeout","count":4}]}'
    ;;
  *)
    exit 64
    ;;
esac
STUB
chmod 700 "$tmp/bin/collector"
for name in status monitor-alerts monitor-slo monitor-db monitor-queue monitor-tls monitor-volumes monitor-drift monitor-log-heatmap; do
  ln -s collector "$tmp/bin/$name"
done
export PATH="$tmp/bin:$PATH"

printf '1/8 operational explanation + deterministic redaction\n'
out="$(bash "$AIOPS" explain db --json --think)"
jq -e '.ok == true and .source == "db" and .answer == "ok"' <<<"$out" >/dev/null || fail 'db explanation failed'
context="$(jq -r '.context' <<<"$out")"
grep -q '\[REDACTED\]' <<<"$context" || fail 'operational context was not redacted'
if grep -q 'secret-token-value' <<<"$context"; then
  fail 'secret leaked into returned AI context'
fi
request_json="$(tail -n 1 "$capture_file" | base64 -d)"
jq -e '.think == true and .reasoning_effort == "high"' <<<"$request_json" >/dev/null || fail 'aiops --think request fields missing'

[[ "$(bash "$AIOPS" explain queue --no-think)" == ok ]] || fail 'aiops --no-think failed'
request_json="$(tail -n 1 "$capture_file" | base64 -d)"
jq -e '.think == false and .reasoning_effort == "none"' <<<"$request_json" >/dev/null || fail 'aiops --no-think request fields missing'

LDS_AI_THINK=true bash "$AIOPS" explain tls --think-auto >/dev/null || fail 'aiops --think-auto failed'
request_json="$(tail -n 1 "$capture_file" | base64 -d)"
jq -e '(.think? == null) and (.reasoning_effort? == null)' <<<"$request_json" >/dev/null || fail 'aiops --think-auto did not omit thinking fields'

printf '2/8 context-only never generates\n'
before="$(wc -l <"$capture_file" | tr -d '[:space:]')"
logs_context="$(bash "$AIOPS" explain logs --context-only)"
after="$(wc -l <"$capture_file" | tr -d '[:space:]')"
[[ "$before" == "$after" ]] || fail 'context-only unexpectedly called generation endpoint'
grep -q '"errors":4' <<<"$logs_context" || fail 'log context missing deterministic heatmap data'

printf '3/8 troubleshoot summary\n'
troubleshoot="$(bash "$AIOPS" troubleshoot --json)"
jq -e '.ok == true and .source == "troubleshoot" and .answer == "ok"' <<<"$troubleshoot" >/dev/null || fail 'troubleshoot analysis failed'
jq -er '.context' <<<"$troubleshoot" | grep -q '"kind":"troubleshoot"' || fail 'troubleshoot context missing combined snapshot'

printf '4/8 review + Graphify input safety\n'
printf 'server_name app.localhost;\n' >"$tmp/nginx.conf"
[[ "$(bash "$AIOPS" review --file "$tmp/nginx.conf")" == ok ]] || fail 'safe config review failed'
printf '{"nodes":3,"edges":2}\n' >"$tmp/graphify.json"
[[ "$(bash "$AIOPS" graphify --file "$tmp/graphify.json")" == ok ]] || fail 'Graphify analysis failed'
printf 'SECRET=value\n' >"$tmp/.env"
set +e
bash "$AIOPS" review --file "$tmp/.env" >"$tmp/out" 2>"$tmp/err"
rc=$?
set -e
[[ "$rc" -eq 77 ]] || fail "sensitive review input returned $rc instead of 77"

dd if=/dev/zero bs=1000 count=600 2>/dev/null | tr '\000' x >"$tmp/large.txt"
set +e
bash "$AIOPS" review --file "$tmp/large.txt" >"$tmp/out" 2>"$tmp/err"
rc=$?
set -e
[[ "$rc" -eq 65 ]] || fail "oversized review input returned $rc instead of 65"

printf '5/8 deterministic document review is additive and validated\n'
mkdir -p "$tmp/docroot"
cat >"$tmp/docroot/README.md" <<'MD'
# Runtime architecture

The runtime delegates provider selection through a deterministic internal contract.
PASSWORD=secret-token-value
MD
doc_sha="$(sha256sum "$tmp/docroot/README.md" | awk '{print $1}')"
doc_bytes="$(wc -c <"$tmp/docroot/README.md" | tr -d '[:space:]')"
jq -n \
  --arg root "$tmp/docroot" \
  --arg sha "$doc_sha" \
  --argjson bytes "$doc_bytes" \
  '{
    schema:"docker-tools.docstruct/v1",
    root:$root,
    files:[{path:"README.md",format:"markdown",sha256:$sha,bytes:$bytes,parser:"pandoc",status:"ok",warnings:[]}],
    nodes:[{id:"README.md#document",type:"document",label:"README.md",source_file:"README.md",evidence:{source_file:"README.md",precision:"document"}}],
    edges:[],
    unresolved_references:[],
    warnings:[],
    stats:{files:1,nodes:1,edges:0,unresolved_references:0}
  }' >"$tmp/docstruct.json"

export DOCSTRUCT_REVIEW_ROOT="$tmp/docroot"
before="$(wc -l <"$capture_file" | tr -d '[:space:]')"
doc_context="$(bash "$AIOPS" document-review --file "$tmp/docstruct.json" --context-only)"
after="$(wc -l <"$capture_file" | tr -d '[:space:]')"
[[ "$before" == "$after" ]] || fail 'document-review context-only unexpectedly called generation endpoint'
jq -e '
  .schema == "docker-tools.docstruct-context/v1"
  and .base_schema == "docker-tools.docstruct/v1"
  and (.structure.schema == "docker-tools.docstruct/v1")
  and (.passages | length == 1)
  and .passages[0].source_file == "README.md"
' <<<"$doc_context" >/dev/null || fail 'document-review context did not include bounded source passage'
grep -q 'runtime delegates provider selection' <<<"$doc_context" || fail 'document-review source passage missing'
if grep -q 'secret-token-value' <<<"$doc_context"; then
  fail 'document-review passage leaked a secret value'
fi
grep -q 'PASSWORD=\[REDACTED\]' <<<"$doc_context" || fail 'document-review passage was not redacted'

printf 'docstruct-review\n' >"$mode_file"
review_patch="$(bash "$AIOPS" document-review --file "$tmp/docstruct.json")"
jq -e '
  .schema == "docker-tools.docstruct-review/v1"
  and .base_schema == "docker-tools.docstruct/v1"
  and (.base_sha256 | type == "string" and length == 64)
  and (.patch.add_nodes | length == 1)
  and .patch.add_nodes[0].id == "README.md#semantic-runtime"
  and (.patch.add_edges | length == 1)
  and .patch.add_edges[0].source == "README.md#document"
' <<<"$review_patch" >/dev/null || fail 'valid document-review additive patch was not accepted'

printf 'docstruct-review-invalid-target\n' >"$mode_file"
set +e
bash "$AIOPS" document-review --file "$tmp/docstruct.json" >"$tmp/out" 2>"$tmp/err"
rc=$?
set -e
[[ "$rc" -eq 69 ]] || fail "invalid document-review target returned $rc instead of 69"
grep -q 'unknown nodes or source files' "$tmp/err" || fail 'invalid document-review target error missing'

printf 'single\n' >"$mode_file"
printf '{"schema":"wrong"}\n' >"$tmp/not-docstruct.json"
set +e
bash "$AIOPS" document-review --file "$tmp/not-docstruct.json" >"$tmp/out" 2>"$tmp/err"
rc=$?
set -e
[[ "$rc" -eq 65 ]] || fail "invalid document-review input returned $rc instead of 65"

unset DOCSTRUCT_REVIEW_ROOT

printf '6/8 repository review is metadata-only\n'
repo_dir="$tmp/repo"
mkdir -p "$repo_dir"
git -C "$repo_dir" init -q
git -C "$repo_dir" config user.email smoke@example.invalid
git -C "$repo_dir" config user.name smoke
printf 'base\n' >"$repo_dir/file.txt"
git -C "$repo_dir" add file.txt
git -C "$repo_dir" commit -qm init
printf 'changed\n' >>"$repo_dir/file.txt"
repo_context="$(cd "$repo_dir" && bash "$AIOPS" repo-review --context-only)"
grep -q '"kind":"repository-metadata"' <<<"$repo_context" || fail 'repo review metadata contract missing'
grep -q 'file.txt' <<<"$repo_context" || fail 'repo review metadata did not include changed filename'
grep -q '"unstaged_files"' <<<"$repo_context" || fail 'repo review unstaged metadata field missing'
if grep -q '^diff --git ' <<<"$repo_context"; then
  fail 'repo review unexpectedly included diff content'
fi

printf '7/8 bounded admin service delegates to aiops\n'
if [[ -r "$ADMIN_BOOTSTRAP" ]]; then
  AI_ADMIN_BOOTSTRAP="$ADMIN_BOOTSTRAP" php <<'PHP'
<?php
declare(strict_types=1);

require getenv('AI_ADMIN_BOOTSTRAP');
$service = new AdminPanel\Service\AiAssistantService();

$status = $service->status();
if (($status['available'] ?? false) !== true || ($status['think'] ?? '') !== 'auto') {
    fwrite(STDERR, "admin AI status did not report available/default thinking mode\n");
    exit(1);
}

$result = $service->analyze(['source' => 'db', 'request' => 'Explain the failure.', 'think' => 'on']);
if (($result['ok'] ?? false) !== true || ($result['answer'] ?? '') !== 'ok' || !str_contains((string)($result['context'] ?? ''), '[REDACTED]')) {
    fwrite(STDERR, "admin AI analysis contract failed\n");
    exit(1);
}

$off = $service->analyze(['source' => 'queue', 'think' => false]);
if (($off['ok'] ?? false) !== true) {
    fwrite(STDERR, "admin AI boolean no-thinking contract failed\n");
    exit(1);
}

$invalid = $service->analyze(['source' => 'not-a-source']);
if (($invalid['error'] ?? '') !== 'validation_source') {
    fwrite(STDERR, "admin AI source validation contract failed\n");
    exit(1);
}

$invalidThink = $service->analyze(['source' => 'db', 'think' => 'sometimes']);
if (($invalidThink['error'] ?? '') !== 'validation_think') {
    fwrite(STDERR, "admin AI thinking validation contract failed\n");
    exit(1);
}
PHP
fi

printf '8/8 admin request-level thinking reaches provider\n'
request_json="$(tail -n 2 "$capture_file" | head -n 1 | base64 -d)"
jq -e '.think == true and .reasoning_effort == "high"' <<<"$request_json" >/dev/null || fail 'admin think=on request fields missing'
request_json="$(tail -n 1 "$capture_file" | base64 -d)"
jq -e '.think == false and .reasoning_effort == "none"' <<<"$request_json" >/dev/null || fail 'admin think=false request fields missing'

printf 'ai-intelligence-smoke: ok\n'
