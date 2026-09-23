#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURES="$ROOT/scripts/tests/fixtures/docstruct"
DOCSTRUCT="${DOCSTRUCT_BIN:-$ROOT/scripts/shells/docstruct.sh}"

fail() {
  printf 'docstruct-contract: %s\n' "$*" >&2
  exit 1
}

command -v jq >/dev/null 2>&1 || fail "jq is required"
command -v pandoc >/dev/null 2>&1 || fail "pandoc is required"
command -v php >/dev/null 2>&1 || fail "php is required"

tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT INT TERM

DOCSTRUCT_IMPL="$ROOT/scripts/php/docstruct.php" DOCSTRUCT_PHP_BIN="$(command -v php)"   bash "$DOCSTRUCT" "$FIXTURES" --output "$tmp/one.json"

DOCSTRUCT_IMPL="$ROOT/scripts/php/docstruct.php" DOCSTRUCT_PHP_BIN="$(command -v php)"   bash "$DOCSTRUCT" "$FIXTURES" --output "$tmp/two.json"

cmp -s "$tmp/one.json" "$tmp/two.json" || fail "same corpus did not produce deterministic JSON"

jq -e '
  .schema == "docker-tools.docstruct/v1"
  and .stats.files == 7
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
  and (.nodes | any(.source_file == "bug_report.yml" and .type == "config_key" and .key_path == "body"))
  and (.nodes | any(.source_file == "config.json" and .type == "config_key" and .key_path == "runtime.provider"))
  and (.nodes | any(.source_file == "project.toml" and .type == "config_key" and .key_path == "tool.docstruct.enabled"))
' "$tmp/one.json" >/dev/null || fail "normalized document structure contract failed"

jq -e '
  [.nodes[], .edges[], .unresolved_references[]]
  | map(select(.source_file == "sample.rst"))
  | all(.evidence.source_file == "sample.rst")
' "$tmp/one.json" >/dev/null || fail "RST structural facts lost source evidence"

printf 'docstruct-contract: ok\n'
