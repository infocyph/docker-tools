#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURES="$ROOT/scripts/tests/fixtures/docstruct"
DOCSTRUCT="${DOCSTRUCT_BIN:-$ROOT/scripts/shells/docstruct.sh}"
IMPL="${DOCSTRUCT_IMPL:-$ROOT/scripts/php/docstruct.php}"
GRAPHIFY_IMPL="${DOCSTRUCT_GRAPHIFY_IMPL:-$ROOT/scripts/php/docstruct-graphify.php}"
GRAPHIFY_MERGE_IMPL="${DOCSTRUCT_GRAPHIFY_MERGE_IMPL:-$ROOT/scripts/php/docstruct-graphify-merge.php}"
CONTEXT_IMPL="${DOCSTRUCT_CONTEXT_IMPL:-$ROOT/scripts/php/docstruct-context.php}"
PHP_BIN="${DOCSTRUCT_PHP_BIN:-$(command -v php || true)}"

fail() {
  printf 'docstruct-contract: %s\n' "$*" >&2
  exit 1
}

command -v jq >/dev/null 2>&1 || fail "jq is required"
command -v pandoc >/dev/null 2>&1 || fail "pandoc is required"
command -v php >/dev/null 2>&1 || fail "php is required"

tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT INT TERM

DOCSTRUCT_IMPL="$IMPL" DOCSTRUCT_PHP_BIN="$PHP_BIN" bash "$DOCSTRUCT" "$FIXTURES" --output "$tmp/one.json"

DOCSTRUCT_IMPL="$IMPL" DOCSTRUCT_PHP_BIN="$PHP_BIN" bash "$DOCSTRUCT" "$FIXTURES" --output "$tmp/two.json"

cmp -s "$tmp/one.json" "$tmp/two.json" || fail "same corpus did not produce deterministic JSON"

jq -e '
  .schema == "docker-tools.docstruct/v1"
  and .stats.files == 8
  and (.nodes | any(.id == "sample.md#document" and .type == "document"))
  and (.nodes | any(.source_file == "sample.md" and .type == "section" and .label == "Runtime Guide"))
  and (.nodes | any(.source_file == "sample.md" and .type == "code_block" and .language == "bash"))
  and (.nodes | any(.id == "sample.rst#runtime-adapter" and .type == "link_target"))
  and (.nodes | any(.source_file == "sample.rst" and .type == "directive" and .directive == "include" and .argument == "included.rst"))
  and (.nodes | any(.source_file == "sample.rst" and .type == "directive" and .directive == "toctree"))
  and (.edges | any(.source == "sample.md#document" and .target == "sample.rst#runtime-adapter" and .relation == "links_to"))
  and (.edges | any(.source == "sample.rst#document" and .target == "included.rst#document" and .relation == "includes"))
  and (.edges | any(.source == "sample.rst#document" and .target == "other.rst#document" and .reference_type == "toctree"))
  and (.unresolved_references | any(.source_file == "sample.rst" and .target == "RuntimeManager" and .reference_type == "class"))
  and (.unresolved_references | any(.source_file == "sample.rst" and .target == "RuntimeAdapter.start" and .reference_type == "meth"))
  and (.files | any(.path == "bug_report.yml" and .format == "yaml" and .parser == "yq"))
  and (.files | any(.path == "config.json" and .format == "json" and .parser == "php-json"))
  and (.files | any(.path == "project.toml" and .format == "toml" and .parser == "yq"))
  and (.files | any(.path == "settings.ini" and .format == "ini" and .parser == "php-ini"))
  and (.nodes | any(.source_file == "bug_report.yml" and .type == "config_key" and .key_path == "body"))
  and (.nodes | any(.source_file == "config.json" and .type == "config_key" and .key_path == "runtime.provider"))
  and (.nodes | any(.source_file == "project.toml" and .type == "config_key" and .key_path == "tool.docstruct.enabled"))
  and (.nodes | any(.source_file == "settings.ini" and .type == "config_key" and .key_path == "docs.guide"))
  and (.edges | any(.source_file == "settings.ini" and .target == "sample.rst#runtime-adapter" and .reference_type == "config_path"))
  and (.edges | any(.source_file == "settings.ini" and .target == "https://example.invalid/docs" and .reference_type == "url"))
  and (([.edges[].target, .unresolved_references[].target] | index("secret.rst")) == null)
' "$tmp/one.json" >/dev/null || fail "normalized document structure contract failed"

jq -e '
  [.nodes[], .edges[], .unresolved_references[]]
  | map(select(.source_file == "sample.rst"))
  | all(.evidence.source_file == "sample.rst")
' "$tmp/one.json" >/dev/null || fail "RST structural facts lost source evidence"

printf 'docstruct-contract: bounded review context\n'

DOCSTRUCT_IMPL="$IMPL" \
DOCSTRUCT_CONTEXT_IMPL="$CONTEXT_IMPL" \
DOCSTRUCT_REVIEW_ROOT="$FIXTURES" \
DOCSTRUCT_PHP_BIN="$PHP_BIN" \
  bash "$DOCSTRUCT" context "$tmp/one.json" >"$tmp/review-context.json"

base="$(cat "$tmp/one.json")"
base_hash="$(printf '%s' "$base" | sha256sum | awk '{print $1}')"
jq -e --arg base_sha256 "$base_hash" '
  .schema == "docker-tools.docstruct-context/v1"
  and .base_schema == "docker-tools.docstruct/v1"
  and .base_sha256 == $base_sha256
  and (.passages | length == 4)
  and (.chunks | type == "array" and length >= 1)
  and (.chunks | all((.files | length) <= 4 and .bytes <= 49152))
  and (.passages | all(.format == "markdown" or .format == "rst"))
  and ([.passages[].source_file] | index("settings.ini") == null)
  and ([.passages[].source_file] | index("config.json") == null)
' "$tmp/review-context.json" >/dev/null || fail "bounded review context contract failed"

DOCSTRUCT_REVIEW_FILE_BYTES=32 \
DOCSTRUCT_REVIEW_TOTAL_BYTES=80 \
DOCSTRUCT_IMPL="$IMPL" \
DOCSTRUCT_CONTEXT_IMPL="$CONTEXT_IMPL" \
DOCSTRUCT_REVIEW_ROOT="$FIXTURES" \
DOCSTRUCT_PHP_BIN="$PHP_BIN" \
  bash "$DOCSTRUCT" context "$tmp/one.json" >"$tmp/review-context-small.json"
jq -e '
  .stats.passage_bytes <= 80
  and .stats.file_limit_bytes == 32
  and .stats.total_limit_bytes == 80
  and (.passages | any(.truncated == true))
' "$tmp/review-context-small.json" >/dev/null || fail "review context limits were not enforced"

jq '.root = "/"' "$tmp/one.json" >"$tmp/review-context-outside.json"
set +e
DOCSTRUCT_IMPL="$IMPL" \
DOCSTRUCT_CONTEXT_IMPL="$CONTEXT_IMPL" \
DOCSTRUCT_REVIEW_ROOT="$FIXTURES" \
DOCSTRUCT_PHP_BIN="$PHP_BIN" \
  bash "$DOCSTRUCT" context "$tmp/review-context-outside.json" >/dev/null 2>"$tmp/review-context-outside.err"
rc=$?
set -e
[[ "$rc" -eq 77 ]] || fail "outside-workspace review root returned $rc instead of 77"
grep -q 'outside the allowed review workspace' "$tmp/review-context-outside.err" ||
  fail "outside-workspace review root error missing"

printf 'docstruct-contract: Graphify fragment export\n'

DOCSTRUCT_IMPL="$IMPL" \
DOCSTRUCT_GRAPHIFY_IMPL="$GRAPHIFY_IMPL" \
DOCSTRUCT_PHP_BIN="$PHP_BIN" \
  bash "$DOCSTRUCT" graphify "$tmp/one.json" --output "$tmp/graphify.json"

DOCSTRUCT_IMPL="$IMPL" \
DOCSTRUCT_GRAPHIFY_IMPL="$GRAPHIFY_IMPL" \
DOCSTRUCT_PHP_BIN="$PHP_BIN" \
  bash "$DOCSTRUCT" graphify "$tmp/one.json" --source-root /host/TalkingBytes --output "$tmp/graphify-host.json"
jq -e '
  (.nodes | all(.source_file | startswith("/host/TalkingBytes/")))
  and (.edges | all(.source_file | startswith("/host/TalkingBytes/")))
' "$tmp/graphify-host.json" >/dev/null || fail "Graphify source-root remap failed"

set +e
DOCSTRUCT_IMPL="$IMPL" \
DOCSTRUCT_GRAPHIFY_IMPL="$GRAPHIFY_IMPL" \
DOCSTRUCT_PHP_BIN="$PHP_BIN" \
  bash "$DOCSTRUCT" graphify "$tmp/one.json" --source-root relative/path >/dev/null 2>"$tmp/graphify-root.err"
rc=$?
set -e
[[ "$rc" -eq 65 ]] || fail "relative Graphify source root returned $rc instead of 65"
grep -q 'source root must be absolute' "$tmp/graphify-root.err" ||
  fail "relative Graphify source-root error missing"

jq -e '
  (.nodes | length > 0)
  and (.nodes | all(
    (.id | test("^docstruct_[a-z0-9_]+$"))
    and (.docstruct_origin == "docker-tools.docstruct/v1")
    and (.file_type == "document")
    and (.source_file | startswith("/"))))
  and (.edges | all(
    (.source | test("^[a-z0-9_]+$"))
    and (.target | test("^[a-z0-9_]+$"))
    and (.confidence == "EXTRACTED")
    and (.confidence_score == 1)
    and (.docstruct_origin == "docker-tools.docstruct/v1")))
  and (.hyperedges == [])
  and (.input_tokens == 0)
  and (.output_tokens == 0)
  and (.nodes | any(.id == "docstruct_sample_document"))
  and (.nodes | any(.id == "docstruct_sample_runtime_adapter"))
  and (.edges | any(.source == "docstruct_sample_document" and .target == "docstruct_sample_runtime_adapter" and .relation == "references"))
  and ([.nodes[].id] | all(test("config_[a-f0-9]{16}$") | not))
' "$tmp/graphify.json" >/dev/null || fail "Graphify mechanical fragment contract failed"

base="$(cat "$tmp/one.json")"
base_hash="$(printf '%s' "$base" | sha256sum | awk '{print $1}')"
jq -n \
  --arg base_sha256 "$base_hash" \
  '{
    schema:"docker-tools.docstruct-review/v1",
    base_schema:"docker-tools.docstruct/v1",
    base_sha256:$base_sha256,
    patch:{
      add_nodes:[{
        id:"sample.md#semantic-runtime",
        type:"concept",
        label:"Runtime architecture",
        source_file:"sample.md",
        reason:"Explicit semantic concept for export contract.",
        confidence:0.92
      }],
      add_edges:[{
        source:"sample.md#document",
        target:"sample.md#semantic-runtime",
        relation:"conceptually_related_to",
        source_file:"sample.md",
        reason:"The README describes the runtime architecture.",
        confidence:0.9
      }],
      corrections:[],
      unresolved:[]
    }
  }' >"$tmp/review.json"

DOCSTRUCT_IMPL="$IMPL" \
DOCSTRUCT_GRAPHIFY_IMPL="$GRAPHIFY_IMPL" \
DOCSTRUCT_PHP_BIN="$PHP_BIN" \
  bash "$DOCSTRUCT" graphify "$tmp/one.json" --review "$tmp/review.json" --output "$tmp/graphify-reviewed.json"

jq -e '
  (.nodes | any(.id == "docstruct_sample_runtime_architecture" and .file_type == "concept"))
  and (.edges | any(
    .source == "docstruct_sample_document"
    and .target == "docstruct_sample_runtime_architecture"
    and .relation == "conceptually_related_to"
    and .confidence == "INFERRED"
    and .confidence_score == 0.95))
' "$tmp/graphify-reviewed.json" >/dev/null || fail "Graphify reviewed fragment contract failed"

jq '.base_sha256 = "wrong"' "$tmp/review.json" >"$tmp/review-wrong.json"
set +e
DOCSTRUCT_IMPL="$IMPL" \
DOCSTRUCT_GRAPHIFY_IMPL="$GRAPHIFY_IMPL" \
DOCSTRUCT_PHP_BIN="$PHP_BIN" \
  bash "$DOCSTRUCT" graphify "$tmp/one.json" --review "$tmp/review-wrong.json" >/dev/null 2>"$tmp/graphify-review.err"
rc=$?
set -e
[[ "$rc" -eq 65 ]] || fail "mismatched Graphify review returned $rc instead of 65"
grep -q 'does not belong to this docstruct artifact' "$tmp/graphify-review.err" ||
  fail "mismatched Graphify review error missing"

printf 'docstruct-contract: safe Graphify merge\n'

cat >"$tmp/code-graph.json" <<'JSON'
{
  "nodes": [
    {
      "id": "src_runtime_php_runtime",
      "label": "Runtime",
      "file_type": "class",
      "source_file": "src/Runtime.php"
    },
    {
      "id": "docstruct_old_document",
      "label": "Old document",
      "file_type": "document",
      "source_file": "/tmp/old.md",
      "docstruct_origin": "docker-tools.docstruct/v1"
    },
    {
      "id": "legacy_semantic_doc",
      "label": "Legacy semantic document",
      "file_type": "document",
      "source_file": "/tmp/legacy.rst"
    }
  ],
  "edges": [
    {
      "source": "src_runtime_php_runtime",
      "target": "src_runtime_php_runtime",
      "relation": "calls",
      "source_file": "src/Runtime.php"
    },
    {
      "source": "docstruct_old_document",
      "target": "docstruct_old_document",
      "relation": "contains",
      "source_file": "/tmp/old.md",
      "docstruct_origin": "docker-tools.docstruct/v1"
    }
  ],
  "hyperedges": [],
  "input_tokens": 11,
  "output_tokens": 0
}
JSON

DOCSTRUCT_IMPL="$IMPL" \
DOCSTRUCT_GRAPHIFY_IMPL="$GRAPHIFY_IMPL" \
DOCSTRUCT_GRAPHIFY_MERGE_IMPL="$GRAPHIFY_MERGE_IMPL" \
DOCSTRUCT_PHP_BIN="$PHP_BIN" \
  bash "$DOCSTRUCT" graphify-merge "$tmp/code-graph.json" "$tmp/graphify-reviewed.json" --output "$tmp/merged-graph.json"

jq -e '
  (.nodes | any(.id == "src_runtime_php_runtime" and .file_type == "class"))
  and ([.nodes[].id] | index("docstruct_old_document") == null)
  and ([.nodes[].id] | index("legacy_semantic_doc") == null)
  and (.nodes | any(.id == "docstruct_sample_document"))
  and (.edges | any(.relation == "calls" and .source == "src_runtime_php_runtime"))
  and ([.edges[] | select(.source == "docstruct_old_document" or .target == "docstruct_old_document")] | length == 0)
  and (.input_tokens == 11)
' "$tmp/merged-graph.json" >/dev/null || fail "safe Graphify merge did not preserve code and replace docstruct nodes"

DOCSTRUCT_IMPL="$IMPL" \
DOCSTRUCT_GRAPHIFY_IMPL="$GRAPHIFY_IMPL" \
DOCSTRUCT_GRAPHIFY_MERGE_IMPL="$GRAPHIFY_MERGE_IMPL" \
DOCSTRUCT_PHP_BIN="$PHP_BIN" \
  bash "$DOCSTRUCT" graphify-merge "$tmp/merged-graph.json" "$tmp/graphify-reviewed.json" --output "$tmp/merged-graph-two.json"
cmp -s "$tmp/merged-graph.json" "$tmp/merged-graph-two.json" || fail "Graphify merge is not idempotent"

jq '.nodes += [{
  "id":"docstruct_sample_document",
  "label":"Collision",
  "file_type":"class",
  "source_file":"src/Collision.php"
}]' "$tmp/code-graph.json" >"$tmp/collision-graph.json"
set +e
DOCSTRUCT_IMPL="$IMPL" \
DOCSTRUCT_GRAPHIFY_IMPL="$GRAPHIFY_IMPL" \
DOCSTRUCT_GRAPHIFY_MERGE_IMPL="$GRAPHIFY_MERGE_IMPL" \
DOCSTRUCT_PHP_BIN="$PHP_BIN" \
  bash "$DOCSTRUCT" graphify-merge "$tmp/collision-graph.json" "$tmp/graphify.json" >/dev/null 2>"$tmp/collision.err"
rc=$?
set -e
[[ "$rc" -eq 65 ]] || fail "Graphify merge collision returned $rc instead of 65"
grep -q 'collides with an existing code/graph node' "$tmp/collision.err" || fail "Graphify merge collision error missing"

printf 'docstruct-contract: scan selection and gitignore\n'

DOCSTRUCT_IMPL="$IMPL" \
DOCSTRUCT_GRAPHIFY_IMPL="$GRAPHIFY_IMPL" \
DOCSTRUCT_PHP_BIN="$PHP_BIN" \
  bash "$DOCSTRUCT" "$FIXTURES" --include '*.rst' --exclude 'included.rst' --output "$tmp/filtered.json"
jq -e '
  .stats.files == 2
  and (.files | all(.format == "rst"))
  and ([.files[].path] | index("included.rst") == null)
' "$tmp/filtered.json" >/dev/null || fail "include/exclude scan filters failed"

if command -v git >/dev/null 2>&1; then
  mkdir -p "$tmp/gitignored"
  git -C "$tmp/gitignored" init -q
  printf 'ignored.md\n' >"$tmp/gitignored/.gitignore"
  printf '# Keep\n' >"$tmp/gitignored/keep.md"
  printf '# Ignore\n' >"$tmp/gitignored/ignored.md"

  DOCSTRUCT_IMPL="$IMPL" DOCSTRUCT_PHP_BIN="$PHP_BIN" \
    bash "$DOCSTRUCT" "$tmp/gitignored" --output "$tmp/gitignored-default.json"
  jq -e '.stats.files == 1 and .files[0].path == "keep.md"' "$tmp/gitignored-default.json" >/dev/null ||
    fail "default gitignore filtering failed"

  DOCSTRUCT_IMPL="$IMPL" DOCSTRUCT_PHP_BIN="$PHP_BIN" \
    bash "$DOCSTRUCT" "$tmp/gitignored" --no-gitignore --output "$tmp/gitignored-all.json"
  jq -e '.stats.files == 2' "$tmp/gitignored-all.json" >/dev/null ||
    fail "--no-gitignore did not restore ignored document"
fi

set +e
DOCSTRUCT_MAX_REFERENCES=1 \
DOCSTRUCT_IMPL="$IMPL" DOCSTRUCT_PHP_BIN="$PHP_BIN" \
  bash "$DOCSTRUCT" "$FIXTURES/sample.md" >/dev/null 2>"$tmp/reference-limit.err"
rc=$?
set -e
[[ "$rc" -eq 65 ]] || fail "reference cap returned $rc instead of 65"
grep -q 'DOCSTRUCT_MAX_REFERENCES' "$tmp/reference-limit.err" || fail "reference cap error missing"

printf 'docstruct-contract: security bounds\n'

mkdir -p "$tmp/security/root"
printf '# Outside\n' >"$tmp/security/outside.md"
ln -s ../outside.md "$tmp/security/root/linked.md"
DOCSTRUCT_IMPL="$IMPL" \
DOCSTRUCT_PHP_BIN="$PHP_BIN" \
  bash "$DOCSTRUCT" "$tmp/security/root" --output "$tmp/security.json"
jq -e '.stats.files == 0 and .stats.nodes == 0' "$tmp/security.json" >/dev/null ||
  fail "symlinked file escaped the explicit corpus"

printf '# Too large for test limit\n' >"$tmp/security/root/large.md"
set +e
DOCSTRUCT_MAX_FILE_BYTES=4 \
DOCSTRUCT_IMPL="$IMPL" \
DOCSTRUCT_PHP_BIN="$PHP_BIN" \
  bash "$DOCSTRUCT" "$tmp/security/root" >/dev/null 2>"$tmp/security.err"
rc=$?
set -e
[[ "$rc" -eq 65 ]] || fail "oversized file returned $rc instead of 65"
grep -q 'DOCSTRUCT_MAX_FILE_BYTES' "$tmp/security.err" || fail "oversized file error missing"

rm -f "$tmp/security/root/large.md"
cat >"$tmp/security/root/escape.md" <<'MD'
# Escape

[Outside](../../outside.md)
MD
DOCSTRUCT_IMPL="$IMPL" \
DOCSTRUCT_PHP_BIN="$PHP_BIN" \
  bash "$DOCSTRUCT" "$tmp/security/root" --output "$tmp/escape.json"
jq -e '
  .unresolved_references
  | any(.target == "../../outside.md" and .reason == "target_outside_root")
' "$tmp/escape.json" >/dev/null || fail "outside-root reference was not retained as unresolved"

printf 'docstruct-contract: malformed input handling\n'

mkdir -p "$tmp/malformed"
printf '{"broken": ' >"$tmp/malformed/bad.json"
cat >"$tmp/malformed/bad.toml" <<'TOML'
[tool
broken = true
TOML

DOCSTRUCT_IMPL="$IMPL" \
DOCSTRUCT_PHP_BIN="$PHP_BIN" \
  bash "$DOCSTRUCT" "$tmp/malformed" --output "$tmp/malformed.json"

jq -e '
  (.files | any(.path == "bad.json" and .status == "error"))
  and (.files | any(.path == "bad.toml" and .status == "error"))
  and (.warnings | length >= 2)
' "$tmp/malformed.json" >/dev/null || fail "malformed inputs were not surfaced deterministically"

printf 'docstruct-contract: ok\n'
