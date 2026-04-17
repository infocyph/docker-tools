#!/usr/bin/env bash

set -euo pipefail

die(){ echo "Error: $*" >&2; exit 1; }

command -v git >/dev/null 2>&1 || die "git not found"

CURRENT_USER="${USER:-$(id -un 2>/dev/null || echo unknown)}"
HOME_DIR="${HOME_DIR:-${HOME:-/root}}"

GIT_CREDENTIAL_STORE="${GIT_CREDENTIAL_STORE:-${HOME_DIR}/.git-credentials}"
GIT_CREDENTIAL_MODE="${GIT_CREDENTIAL_MODE:-auto}" # auto|keychain+cache|cache|store|none
GIT_CREDENTIAL_CACHE_TIMEOUT="${GIT_CREDENTIAL_CACHE_TIMEOUT:-3600}"
GIT_USER_NAME="${GIT_USER_NAME:-}"
GIT_USER_EMAIL="${GIT_USER_EMAIL:-}"

detect_keychain_helper() {
  local helper_path git_exec_path

  if command -v git-credential-libsecret >/dev/null 2>&1; then
    echo "libsecret"
    return 0
  fi

  git_exec_path="$(git --exec-path 2>/dev/null || true)"
  helper_path="${git_exec_path}/git-credential-libsecret"
  if [[ -x "${helper_path}" ]]; then
    echo "${helper_path}"
    return 0
  fi

  return 1
}

configure_git_credentials() {
  local keychain_helper

  git config --global --unset-all credential.helper >/dev/null 2>&1 || true

  case "${GIT_CREDENTIAL_MODE}" in
    auto|keychain+cache)
      git config --global --add credential.helper "cache --timeout=${GIT_CREDENTIAL_CACHE_TIMEOUT}"
      if keychain_helper="$(detect_keychain_helper)"; then
        git config --global --add credential.helper "${keychain_helper}"
      fi
      ;;
    cache)
      git config --global --add credential.helper "cache --timeout=${GIT_CREDENTIAL_CACHE_TIMEOUT}"
      ;;
    store)
      mkdir -p "$(dirname "$GIT_CREDENTIAL_STORE")"
      git config --global credential.helper "store --file ${GIT_CREDENTIAL_STORE}"
      ( umask 077; touch "${GIT_CREDENTIAL_STORE}" )
      ;;
    none)
      ;;
    *)
      die "invalid GIT_CREDENTIAL_MODE: '${GIT_CREDENTIAL_MODE}' (expected: auto|keychain+cache|cache|store|none)"
      ;;
  esac
}

# ---- Safe directory (avoid "dubious ownership" in containers)
if ! git config --global --get-all safe.directory | grep -Fxq '/app/*'; then
  git config --global --add safe.directory '/app/*'
fi

# ---- Credential helpers
configure_git_credentials

# ---- Optional identity
if [[ -n "${GIT_USER_NAME}" ]]; then
  git config --global user.name "${GIT_USER_NAME}"
fi
if [[ -n "${GIT_USER_EMAIL}" ]]; then
  git config --global user.email "${GIT_USER_EMAIL}"
fi

# ---- Recommended defaults (LF, safer pull/push, better diffs)
git config --global core.autocrlf false
git config --global core.eol lf
git config --global core.safecrlf warn

git config --global pull.rebase true
git config --global rebase.autoStash true

git config --global fetch.prune true
git config --global fetch.pruneTags true

git config --global rerere.enabled true
git config --global merge.conflictStyle zdiff3
git config --global diff.algorithm histogram

git config --global push.default simple
git config --global push.autoSetupRemote true

echo "✅ Git defaults configured for user '${CURRENT_USER}'"
echo "   safe.directory: /app/*"
echo "   credential mode: ${GIT_CREDENTIAL_MODE}"
echo "   credential helpers:"
credential_helpers="$(git config --global --get-all credential.helper || true)"
if [[ -n "${credential_helpers}" ]]; then
  printf '%s\n' "${credential_helpers}" | sed 's/^/     - /'
else
  echo "     - (none)"
fi
if [[ "${GIT_CREDENTIAL_MODE}" == "store" ]]; then
  echo "   credential store: ${GIT_CREDENTIAL_STORE}"
fi
if [[ -n "${GIT_USER_NAME}" ]]; then echo "   user.name: ${GIT_USER_NAME}"; fi
if [[ -n "${GIT_USER_EMAIL}" ]]; then echo "   user.email: ${GIT_USER_EMAIL}"; fi
