#!/usr/bin/env bash
set -euo pipefail

die() {
  echo "Error: $*" >&2
  exit 1
}

note() {
  echo "[senv-smoke] $*"
}

if ! command -v sops >/dev/null 2>&1; then
  die "sops is required"
fi
if ! command -v age-keygen >/dev/null 2>&1; then
  die "age-keygen is required"
fi

SENV_SCRIPT_PATH="${SENV_SCRIPT_PATH:-}"
if [[ -z "$SENV_SCRIPT_PATH" ]]; then
  if command -v senv >/dev/null 2>&1; then
    SENV_SCRIPT_PATH="$(command -v senv)"
  else
    SENV_SCRIPT_PATH="/usr/local/bin/senv"
  fi
fi

SENV_CMD=()
if [[ -x "$SENV_SCRIPT_PATH" ]]; then
  SENV_CMD=("$SENV_SCRIPT_PATH")
elif [[ -f "$SENV_SCRIPT_PATH" ]]; then
  SENV_CMD=(bash "$SENV_SCRIPT_PATH")
elif [[ -f "./scripts/shells/senv.sh" ]]; then
  SENV_CMD=(bash "./scripts/shells/senv.sh")
else
  die "could not locate senv script (set SENV_SCRIPT_PATH)"
fi

senv_cmd() {
  "${SENV_CMD[@]}" "$@"
}

TMP_ROOT="$(mktemp -d)"
trap 'chmod -R u+w "$TMP_ROOT" >/dev/null 2>&1 || true; rm -rf "$TMP_ROOT"' EXIT

export SOPS_BASE_DIR="$TMP_ROOT/sops"
export SOPS_KEYS_DIR="$SOPS_BASE_DIR/keys"
export SOPS_CFG_DIR="$SOPS_BASE_DIR/config"
export SOPS_GLOBAL_DIR="$SOPS_BASE_DIR/global"
export SOPS_REPO_DIR="$TMP_ROOT/sops-repo"

WORK_DIR="$TMP_ROOT/work"
mkdir -p "$SOPS_KEYS_DIR" "$SOPS_CFG_DIR" "$SOPS_GLOBAL_DIR" "$SOPS_REPO_DIR" "$WORK_DIR"

note "1/5 init creates global key/config"
senv_cmd init >/dev/null
[[ -s "$SOPS_GLOBAL_DIR/age.keys" ]] || die "missing global key: $SOPS_GLOBAL_DIR/age.keys"
[[ -f "$SOPS_GLOBAL_DIR/.sops.yaml" ]] || die "missing global config: $SOPS_GLOBAL_DIR/.sops.yaml"

note "2/5 keygen refuses overwrite"
senv_cmd keygen --project smokeproj >/dev/null
if senv_cmd keygen --project smokeproj >/dev/null 2>&1; then
  die "keygen should refuse overwrite for an existing non-empty key"
fi

note "3/5 enc/dec roundtrip works"
cat >"$WORK_DIR/.env" <<'EOF'
APP_ENV=local
API_TOKEN=abc123
EOF
(
  cd "$WORK_DIR"
  senv_cmd enc --in ./.env --out ./.env.enc >/dev/null
  senv_cmd dec --in ./.env.enc --out ./.env.dec >/dev/null
  cmp -s ./.env ./.env.dec || die "enc/dec roundtrip mismatch"
)

note "4/5 push/pull alias flow works for project key"
cat >"$WORK_DIR/.env" <<'EOF'
SERVICE_KEY=smoke-project-key
EOF
(
  cd "$WORK_DIR"
  senv_cmd push --project smokeproj --in ./.env --out smokeproj/.env.enc >/dev/null
  [[ -f "$SOPS_REPO_DIR/smokeproj/.env.enc" ]] || die "push did not create repo alias output"
  senv_cmd pull --project smokeproj --in smokeproj/.env.enc --out ./.env.pulled >/dev/null
  cmp -s ./.env ./.env.pulled || die "push/pull decrypted content mismatch"
)

note "5/5 safe-path guard blocks out-of-root input unless --unsafe"
OUTSIDE_IN="$TMP_ROOT/outside.env.enc"
cp "$SOPS_REPO_DIR/smokeproj/.env.enc" "$OUTSIDE_IN"
(
  cd "$WORK_DIR"
  if senv_cmd dec --project smokeproj --in "$OUTSIDE_IN" --out ./.env.blocked 2>"$TMP_ROOT/safe.err"; then
    die "safe-path guard should block outside input path"
  fi
)
grep -q "outside safe roots" "$TMP_ROOT/safe.err" || die "safe-path guard error message not found"
(
  cd "$WORK_DIR"
  senv_cmd dec --project smokeproj --unsafe --in "$OUTSIDE_IN" --out ./.env.unblocked >/dev/null
  cmp -s ./.env ./.env.unblocked || die "--unsafe decrypt mismatch"
)

note "consume-only mode check (read-only SOPS tree remains non-fatal)"
chmod -R a-w "$SOPS_BASE_DIR"
senv_cmd init --project readonly >/dev/null

note "all checks passed"
