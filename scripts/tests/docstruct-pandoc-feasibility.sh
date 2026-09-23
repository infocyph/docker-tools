#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURES="$ROOT/scripts/tests/fixtures/docstruct"

fail() {
  printf 'docstruct-pandoc-feasibility: %s\n' "$*" >&2
  exit 1
}

command -v pandoc >/dev/null 2>&1 || fail "pandoc is required"
command -v jq >/dev/null 2>&1 || fail "jq is required"

tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT INT TERM

pandoc --from=gfm --to=json "$FIXTURES/sample.md" >"$tmp/markdown.json"
(
  cd "$FIXTURES"
  pandoc --from=rst --to=json sample.rst
) >"$tmp/rst.json"

jq -e '.blocks | type == "array" and length > 0' "$tmp/markdown.json" >/dev/null ||
  fail "Markdown AST is empty"
jq -e '.blocks | type == "array" and length > 0' "$tmp/rst.json" >/dev/null ||
  fail "RST AST is empty"

md_headers="$(jq '[.. | objects | select(.t? == "Header")] | length' "$tmp/markdown.json")"
md_links="$(jq '[.. | objects | select(.t? == "Link")] | length' "$tmp/markdown.json")"
md_code="$(jq '[.. | objects | select(.t? == "CodeBlock")] | length' "$tmp/markdown.json")"

rst_headers="$(jq '[.. | objects | select(.t? == "Header")] | length' "$tmp/rst.json")"
rst_code="$(jq '[.. | objects | select(.t? == "CodeBlock")] | length' "$tmp/rst.json")"
rst_raw="$(jq '[.. | objects | select(.t? == "RawBlock" or .t? == "RawInline")] | length' "$tmp/rst.json")"

md_text="$(jq -c . "$tmp/markdown.json")"
rst_text="$(jq -c . "$tmp/rst.json")"

contains() {
  local haystack="$1" needle="$2"
  if [[ "$haystack" == *"$needle"* ]]; then
    printf 'true'
  else
    printf 'false'
  fi
}

report="$(jq -n \
  --arg pandoc_version "$(pandoc --version | head -n 1)" \
  --argjson md_headers "$md_headers" \
  --argjson md_links "$md_links" \
  --argjson md_code "$md_code" \
  --argjson rst_headers "$rst_headers" \
  --argjson rst_code "$rst_code" \
  --argjson rst_raw "$rst_raw" \
  --argjson md_runtime_link "$(contains "$md_text" 'runtime.rst#runtime-adapter')" \
  --argjson rst_class_text "$(contains "$rst_text" 'RuntimeManager')" \
  --argjson rst_method_text "$(contains "$rst_text" 'RuntimeAdapter.start')" \
  --argjson rst_include_text "$(contains "$rst_text" 'Included Notes')" \
  --argjson rst_toctree_target "$(contains "$rst_text" 'other')" \
  '{
    benchmark:"docker-tools.docstruct-pandoc/v1",
    pandoc:$pandoc_version,
    markdown:{
      headers:$md_headers,
      links:$md_links,
      code_blocks:$md_code,
      linked_target_preserved:$md_runtime_link
    },
    rst:{
      headers:$rst_headers,
      code_blocks:$rst_code,
      raw_nodes:$rst_raw,
      sphinx_class_text_preserved:$rst_class_text,
      sphinx_method_text_preserved:$rst_method_text,
      include_content_visible:$rst_include_text,
      toctree_target_visible:$rst_toctree_target
    }
  }'
)"

jq -e '
  .markdown.headers >= 2
  and .markdown.links >= 1
  and .markdown.code_blocks >= 1
  and .markdown.linked_target_preserved == true
  and .rst.headers >= 2
  and .rst.code_blocks >= 1
  and .rst.sphinx_class_text_preserved == true
  and .rst.sphinx_method_text_preserved == true
' <<<"$report" >/dev/null || fail "Pandoc did not preserve the minimum Markdown/RST structure"

printf '%s\n' "$report"
