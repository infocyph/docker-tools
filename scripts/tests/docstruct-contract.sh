#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURES="$ROOT/scripts/tests/fixtures/docstruct"
DOCSTRUCT="${DOCSTRUCT_BIN:-$ROOT/scripts/shells/docstruct.sh}"
IMPL="${DOCSTRUCT_IMPL:-$ROOT/scripts/php/docstruct.php}"
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
