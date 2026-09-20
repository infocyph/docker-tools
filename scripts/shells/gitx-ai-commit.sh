#!/usr/bin/env bash
set -euo pipefail

PROVIDER_LIB="${LDS_AI_PROVIDER_LIB:-/usr/local/lib/docker-tools/ai-provider.sh}"
PROMPT_FILE="${GITX_AI_COMMIT_PROMPT_FILE:-/usr/local/lib/docker-tools/ai-commit.txt}"
MAX_DIFF_BYTES="${GITX_MAX_DIFF_BYTES:-524288}"

[[ -r "$PROVIDER_LIB" ]] || { echo "gitx: AI provider library missing: $PROVIDER_LIB" >&2; exit 70; }
[[ -r "$PROMPT_FILE" ]] || { echo "gitx: AI commit prompt missing: $PROMPT_FILE" >&2; exit 70; }
# shellcheck source=/dev/null
source "$PROVIDER_LIB"

git_cmd() {
  git -c safe.directory='*' "$@"
}

die_gitx() {
  printf 'gitx: %s\n' "$*" >&2
  exit 1
}

[[ "$MAX_DIFF_BYTES" =~ ^[1-9][0-9]*$ ]] || die_gitx "GITX_MAX_DIFF_BYTES must be a positive integer"

include_sensitive=0
while (($#)); do
  case "$1" in
    --include-sensitive)
      include_sensitive=1
      shift
      ;;
    --persist-api-key)
      printf 'gitx: --persist-api-key is ignored; LocalDevStack uses only the local llm endpoint.\n' >&2
      shift
      ;;
    -h|--help)
      cat <<'EOF'
Usage: gitx ai-commit [--include-sensitive]

Generate a commit message through LocalDevStack's common local llm endpoint.
The normal path redacts known credential patterns before model inference.
EOF
      exit 0
      ;;
    *)
      die_gitx "unknown ai-commit option: $1"
      ;;
  esac
done

command -v git >/dev/null 2>&1 || die_gitx 'git is required'
command -v jq >/dev/null 2>&1 || die_gitx 'jq is required'
git_cmd rev-parse --is-inside-work-tree >/dev/null 2>&1 || die_gitx 'not inside a Git repository'
git_cmd diff --cached --quiet && die_gitx "No staged changes found. Stage changes first with 'git add <files>'."

tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT INT TERM
diff_file="$tmp/staged.diff"
git_cmd diff --cached --no-ext-diff >"$diff_file"
size="$(wc -c <"$diff_file" | tr -d '[:space:]')"
[[ "$size" =~ ^[0-9]+$ ]] || die_gitx 'unable to determine staged diff size'
((10#$size <= 10#$MAX_DIFF_BYTES)) ||
  die_gitx "Staged diff is ${size} bytes; limit is ${MAX_DIFF_BYTES}. Stage a smaller change or raise GITX_MAX_DIFF_BYTES explicitly."

system="$(cat -- "$PROMPT_FILE")"
diff="$(cat -- "$diff_file")"
if ((include_sensitive)); then
  # The common client still applies credential-pattern redaction by design.
  printf 'gitx: --include-sensitive keeps the full diff structure, but known credentials remain redacted.\n' >&2
fi

printf 'Analyzing staged changes through local llm...\n' >&2
commit_msg="$(ai_generate_context   'Analyze the supplied staged git diff and generate the commit message only.'   "$diff"   "$system")" || exit $?

[[ -n "$commit_msg" ]] || die_gitx 'generated commit message is empty'

printf '\n================ Generated Commit Message ================\n\n%s\n\n' "$commit_msg"
printf '==========================================================\n\n'

choice=''
read -r -p 'Do you want to commit with this message? (y/e/n) [y=yes, e=edit, n=no]: ' choice || choice=n
case "$choice" in
  y|Y)
    msg_file="$tmp/commit-message.txt"
    printf '%s\n' "$commit_msg" >"$msg_file"
    git_cmd commit -F "$msg_file"
    printf 'Committed successfully.\n'
    ;;
  e|E)
    msg_file="$tmp/commit-message.txt"
    printf '%s\n' "$commit_msg" >"$msg_file"
    editor_value="${EDITOR:-vi}"
    read -r -a editor_cmd <<<"$editor_value"
    [[ ${#editor_cmd[@]} -gt 0 ]] || editor_cmd=(vi)
    "${editor_cmd[@]}" "$msg_file"
    git_cmd commit -F "$msg_file"
    printf 'Committed successfully.\n'
    ;;
  *)
    printf 'Commit cancelled. Your changes remain staged.\n'
    ;;
esac
